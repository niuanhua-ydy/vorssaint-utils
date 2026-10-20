import CommonCrypto
import CryptoKit
import Foundation

/// 同步存储后端（坚果云 WebDAV、本地文件夹等）。路径相对于同步根目录，以 "/" 分隔。
public protocol SyncRemote: Sendable {
    /// 文件不存在时返回 nil
    func read(_ path: String) async throws -> Data?
    func write(_ path: String, data: Data) async throws
    func delete(_ path: String) async throws
    /// 创建目录（含上级目录），已存在时不报错
    func makeDirectory(_ path: String) async throws
    /// 子目录名称列表
    func listDirectories(_ path: String) async throws -> [String]
}

public struct SyncConfiguration: Sendable {
    public var deviceName: String
    /// 端到端加密的同步密码；为空表示不加密
    public var passphrase: String?
    public var includeImages: Bool
    /// 单条内容（文字、图片、格式数据）超过此大小不同步，只保留在本机
    public var maxFileBytes: Int
    /// 单个批次中文件的总大小上限（控制单次上传 / 下载的内存与流量）
    public var maxBatchFileBytes: Int
    /// 同步目标标识（服务器 + 账号 + 目录），变化时重新上传全量快照
    public var target: String
    /// 本机批次文件超过此数量时合并
    public var compactionThreshold: Int

    public init(deviceName: String, passphrase: String?, includeImages: Bool, target: String,
                maxFileBytes: Int = 5 * 1024 * 1024, maxBatchFileBytes: Int = 40 * 1024 * 1024,
                compactionThreshold: Int = 64) {
        self.deviceName = deviceName
        self.passphrase = passphrase
        self.includeImages = includeImages
        self.target = target
        self.maxFileBytes = maxFileBytes
        self.maxBatchFileBytes = maxBatchFileBytes
        self.compactionThreshold = compactionThreshold
    }
}

public enum SyncError: LocalizedError, Equatable {
    case passphraseRequired
    case wrongPassphrase
    case remoteNotEncrypted
    case unsupportedFormat(Int)
    case corruptData(String)

    public var errorDescription: String? {
        switch self {
        case .passphraseRequired: return "云端数据已加密，请填写与其他设备相同的同步密码"
        case .wrongPassphrase: return "同步密码不正确，请与其他设备保持一致"
        case .remoteNotEncrypted: return "云端数据未加密：请清空同步密码，或在设置中重置云端数据后再启用加密"
        case .unsupportedFormat(let v): return "云端数据来自更新版本的 ClipNote（格式 v\(v)），请先升级"
        case .corruptData(let what): return "云端数据损坏：\(what)"
        }
    }
}

public struct SyncReport: Sendable {
    public var uploadedOps = 0
    public var uploadedSegments = 0
    public var applied = SyncApplyStats()
    public var otherDevices = 0
}

/// AES-GCM 加密，密钥由同步密码经 PBKDF2-SHA256 派生
public struct SyncCipher: Sendable {
    let key: SymmetricKey

    public static func derive(passphrase: String, salt: Data, rounds: UInt32 = 200_000) -> SyncCipher {
        var derived = [UInt8](repeating: 0, count: 32)
        let password = Array(passphrase.utf8)
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     password.map { Int8(bitPattern: $0) }, password.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     &derived, derived.count)
        }
        return SyncCipher(key: SymmetricKey(data: derived))
    }

    public func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw SyncError.corruptData("加密失败") }
        return combined
    }

    public func open(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}

/// 同步引擎。
///
/// 云端布局（同步根目录下）：
/// - `format.json`：格式版本与加密信息（第一台设备创建）
/// - `devices/<设备ID>/head.json`：该设备的批次范围 {oldest, latest}，其他设备每次只读这个小文件
/// - `devices/<设备ID>/<n>.jsonl`：第 n 批变更（JSON Lines，可加密）
/// - `devices/<设备ID>/<n>.files.zip`：第 n 批引用的图片等文件（可加密）
///
/// 每台设备只写自己的目录，互不冲突；读取时按批次顺序合并，合并规则见 SyncOp。
public actor SyncEngine {
    struct Format: Codable {
        var format = "clipnote-sync"
        var version = 1
        var encrypted: Bool
        var salt: String?
        var verifier: String?
    }

    struct Head: Codable {
        var name: String
        var oldest: Int
        var latest: Int
        var updatedAt: Double
    }

    static let formatVersion = 1
    static let verifierText = Data("clipnote-sync-verifier".utf8)

    private let store: ClipStore
    private let remote: SyncRemote
    private var config: SyncConfiguration
    private var cipher: SyncCipher?
    private var prepared = false
    private let ownCache: URL

    public init(store: ClipStore, remote: SyncRemote, configuration: SyncConfiguration) {
        self.store = store
        self.remote = remote
        self.config = configuration
        ownCache = store.directory.appendingPathComponent("SyncCache/own", isDirectory: true)
    }

    public var deviceID: String {
        if let id = store.syncMeta("deviceID") { return id }
        let id = UUID().uuidString
        store.setSyncMeta("deviceID", id)
        return id
    }

    private var devicePath: String { "devices/\(deviceID)" }

    /// 完整同步一次：上传本机变更，再拉取并合并其他设备的变更
    public func syncOnce() async throws -> SyncReport {
        var report = SyncReport()
        try await prepare()
        try await upload(&report)
        try await pull(&report)
        try await compactIfNeeded()
        store.setSyncMeta("lastSync", String(Date().timeIntervalSince1970))
        return report
    }

    // MARK: - 准备

    private func prepare() async throws {
        if store.syncMeta("target") != config.target {
            store.resetSyncProgress()
            try? FileManager.default.removeItem(at: ownCache)
            store.setSyncMeta("target", config.target)
            prepared = false
        }
        guard !prepared else { return }
        try FileManager.default.createDirectory(at: ownCache, withIntermediateDirectories: true)

        let passphrase = config.passphrase?.isEmpty == false ? config.passphrase : nil
        // 先建好本机目录（同时建出同步根目录），再读取 format.json
        try await remote.makeDirectory(devicePath)
        if let data = try await remote.read("format.json") {
            guard let format = try? JSONDecoder().decode(Format.self, from: data) else { throw SyncError.corruptData("format.json") }
            guard format.version <= Self.formatVersion else { throw SyncError.unsupportedFormat(format.version) }
            if format.encrypted {
                guard let passphrase else { throw SyncError.passphraseRequired }
                guard let salt = format.salt.flatMap({ Data(base64Encoded: $0) }),
                      let verifier = format.verifier.flatMap({ Data(base64Encoded: $0) }) else {
                    throw SyncError.corruptData("format.json")
                }
                let cipher = SyncCipher.derive(passphrase: passphrase, salt: salt)
                guard (try? cipher.open(verifier)) == Self.verifierText else { throw SyncError.wrongPassphrase }
                self.cipher = cipher
            } else {
                guard passphrase == nil else { throw SyncError.remoteNotEncrypted }
                cipher = nil
            }
        } else {
            var format = Format(encrypted: passphrase != nil)
            if let passphrase {
                let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
                let cipher = SyncCipher.derive(passphrase: passphrase, salt: salt)
                format.salt = salt.base64EncodedString()
                format.verifier = try cipher.seal(Self.verifierText).base64EncodedString()
                self.cipher = cipher
            }
            try await remote.write("format.json", data: try JSONEncoder().encode(format))
        }
        prepared = true
    }

    // MARK: - 上传

    private var nextSegment: Int { Int(store.syncMeta("nextSeg") ?? "") ?? 1 }
    private var oldestSegment: Int? { Int(store.syncMeta("oldestSeg") ?? "") }

    private func upload(_ report: inout SyncReport) async throws {
        var uploaded = false
        // 首次同步：上传本机全部数据的快照
        if store.syncMeta("snapshotDone") != "1" {
            var cursor: Int64?
            repeat {
                let batch = store.syncSnapshotBatch(after: cursor, includeImages: config.includeImages,
                                                    maxFileBytes: config.maxFileBytes,
                                                    maxBatchFileBytes: config.maxBatchFileBytes)
                if !batch.ops.isEmpty {
                    try await uploadSegment(batch.ops, files: batch.files)
                    report.uploadedOps += batch.ops.count
                    report.uploadedSegments += 1
                    uploaded = true
                }
                cursor = batch.next
            } while cursor != nil
            store.setSyncMeta("snapshotDone", "1")
        }
        // 增量变更
        while true {
            let changes = store.pendingSyncChanges()
            guard !changes.isEmpty else { break }
            let built = store.buildSyncOps(for: changes, includeImages: config.includeImages,
                                           maxFileBytes: config.maxFileBytes, maxBatchFileBytes: config.maxBatchFileBytes)
            if !built.ops.isEmpty {
                try await uploadSegment(built.ops, files: built.files)
                report.uploadedOps += built.ops.count
                report.uploadedSegments += 1
                uploaded = true
            }
            store.markSyncChangesUploaded(Array(changes.prefix(max(built.consumed, 1))))
        }
        if uploaded { try await writeHead() }
    }

    private func uploadSegment(_ ops: [SyncOp], files: [String: URL]) async throws {
        let n = nextSegment
        var ops = ops
        if !files.isEmpty {
            let zip = try Self.makeZip(files)
            try await remote.write("\(devicePath)/\(n).files.zip", data: try seal(zip))
            for i in ops.indices where ops[i].file != nil || ops[i].dataFile != nil {
                ops[i].fileSeg = n
            }
        }
        let plain = try Self.encode(ops)
        try await remote.write("\(devicePath)/\(n).jsonl", data: try seal(plain))
        try plain.write(to: ownCache.appendingPathComponent("\(n).jsonl"))
        store.setSyncMeta("nextSeg", String(n + 1))
        if oldestSegment == nil { store.setSyncMeta("oldestSeg", String(n)) }
    }

    private func writeHead() async throws {
        let latest = nextSegment - 1
        guard latest >= 1 else { return }
        let head = Head(name: config.deviceName, oldest: oldestSegment ?? 1, latest: latest,
                        updatedAt: Date().timeIntervalSince1970)
        try await remote.write("\(devicePath)/head.json", data: try JSONEncoder().encode(head))
    }

    // MARK: - 拉取

    private func pull(_ report: inout SyncReport) async throws {
        let me = deviceID
        for device in try await remote.listDirectories("devices") where device != me {
            guard let headData = try await remote.read("devices/\(device)/head.json"),
                  let head = try? JSONDecoder().decode(Head.self, from: headData) else { continue }
            report.otherDevices += 1
            let applied = Int(store.syncMeta("applied.\(device)") ?? "") ?? 0
            guard head.latest > applied else { continue }
            // 对方合并过批次时，从合并后的批次开始（重复应用是安全的）
            for n in max(applied + 1, head.oldest)...head.latest {
                guard let data = try await remote.read("devices/\(device)/\(n).jsonl") else { break }
                let ops = try Self.decode(try open(data))
                let files = try await fetchFiles(for: ops, device: device)
                defer { files.cleanup() }
                report.applied = report.applied + (try store.applySyncOps(ops, files: files.map))
                store.setSyncMeta("applied.\(device)", String(n))
            }
        }
    }

    private struct FetchedFiles {
        var map: [String: URL] = [:]
        var directories: [URL] = []

        func cleanup() {
            directories.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// 只下载本地缺少的条目所在批次的文件包
    private func fetchFiles(for ops: [SyncOp], device: String) async throws -> FetchedFiles {
        var fetched = FetchedFiles()
        let segments = Set(ops.filter { store.needsFiles(for: $0) }.compactMap(\.fileSeg))
        for segment in segments.sorted() {
            guard let data = try await remote.read("devices/\(device)/\(segment).files.zip") else { continue }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipnote-sync-\(UUID().uuidString)")
            fetched.directories.append(directory)
            try Self.unzip(try open(data), to: directory)
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                fetched.map[url.lastPathComponent] = url
            }
        }
        return fetched
    }

    // MARK: - 合并本机批次

    /// 本机批次过多时合并为一个，减少云端文件数。图片文件包保持不动（合并后的记录仍指向原批次）。
    private func compactIfNeeded() async throws {
        guard let oldest = oldestSegment else { return }
        let latest = nextSegment - 1
        guard latest - oldest + 1 >= config.compactionThreshold else { return }
        var ops: [SyncOp] = []
        for n in oldest...latest {
            // 本地缓存不完整（如重装后）时跳过合并
            guard let data = try? Data(contentsOf: ownCache.appendingPathComponent("\(n).jsonl")) else { return }
            ops += try Self.decode(data)
        }
        let merged = Self.reduce(ops)
        let n = latest + 1
        let plain = try Self.encode(merged)
        try await remote.write("\(devicePath)/\(n).jsonl", data: try seal(plain))
        try plain.write(to: ownCache.appendingPathComponent("\(n).jsonl"))
        store.setSyncMeta("nextSeg", String(n + 1))
        store.setSyncMeta("oldestSeg", String(n))
        try await writeHead()
        for old in oldest...latest {
            try? await remote.delete("\(devicePath)/\(old).jsonl")
            try? FileManager.default.removeItem(at: ownCache.appendingPathComponent("\(old).jsonl"))
        }
    }

    /// 合并一组按顺序排列的记录：同一条目 / 分类只保留合并后的最终状态
    static func reduce(_ ops: [SyncOp]) -> [SyncOp] {
        var items: [String: SyncOp] = [:]
        var itemOrder: [String] = []
        var boards: [String: SyncOp] = [:]
        var boardOrder: [String] = []
        for op in ops {
            switch op.op {
            case .board, .boardDelete:
                guard let name = op.name else { continue }
                if boards[name] == nil { boardOrder.append(name) }
                if (boards[name]?.at ?? -.infinity) <= op.at { boards[name] = op }
            case .item, .meta, .delete:
                guard let hash = op.hash else { continue }
                if items[hash] == nil { itemOrder.append(hash) }
                guard let existing = items[hash] else {
                    items[hash] = op
                    continue
                }
                switch (existing.op, op.op) {
                case (.item, .meta), (.meta, .meta):
                    var merged = existing
                    if (op.updatedAt ?? 0) > (merged.updatedAt ?? 0) {
                        merged.updatedAt = op.updatedAt
                        merged.at = op.at
                    }
                    merged.useCount = max(merged.useCount ?? 0, op.useCount ?? 0)
                    if (op.pinnedAt ?? 0) > (merged.pinnedAt ?? 0) {
                        merged.pinnedAt = op.pinnedAt
                        merged.pinboard = op.pinboard
                    }
                    if let text = op.searchText { merged.searchText = text }
                    if (op.titledAt ?? 0) > (merged.titledAt ?? 0) {
                        merged.title = op.title
                        merged.titledAt = op.titledAt
                    }
                    items[hash] = merged
                case (.delete, .meta):
                    continue
                default:
                    items[hash] = op
                }
            }
        }
        let boardOps = boardOrder.compactMap { boards[$0] }
        let itemOps = itemOrder.compactMap { items[$0] }
        return boardOps.filter { $0.op == .board } + itemOps.filter { $0.op != .delete }
            + itemOps.filter { $0.op == .delete } + boardOps.filter { $0.op == .boardDelete }
    }

    // MARK: - 编解码

    private func seal(_ data: Data) throws -> Data {
        try cipher?.seal(data) ?? data
    }

    private func open(_ data: Data) throws -> Data {
        guard let cipher else { return data }
        do {
            return try cipher.open(data)
        } catch {
            throw SyncError.corruptData("解密失败")
        }
    }

    static func encode(_ ops: [SyncOp]) throws -> Data {
        let encoder = JSONEncoder()
        var data = Data()
        for op in ops {
            data.append(try encoder.encode(op))
            data.append(0x0A)
        }
        return data
    }

    static func decode(_ data: Data) throws -> [SyncOp] {
        let decoder = JSONDecoder()
        return try data.split(separator: 0x0A).filter { !$0.isEmpty }.map { line in
            do {
                return try decoder.decode(SyncOp.self, from: Data(line))
            } catch {
                throw SyncError.corruptData("变更记录无法解析")
            }
        }
    }

    static func makeZip(_ files: [String: URL]) throws -> Data {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("clipnote-zip-\(UUID().uuidString)")
        let folder = work.appendingPathComponent("files")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for (key, url) in files {
            try fm.copyItem(at: url, to: folder.appendingPathComponent(key))
        }
        let archive = work.appendingPathComponent("files.zip")
        try BackupService.runDitto(["-c", "-k", folder.path, archive.path])
        return try Data(contentsOf: archive)
    }

    static func unzip(_ data: Data, to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent(".download.zip")
        try data.write(to: archive)
        defer { try? fm.removeItem(at: archive) }
        try BackupService.runDitto(["-x", "-k", archive.path, directory.path])
    }
}

/// 以本地文件夹作为同步存储（测试用，也可指向 iCloud 云盘等同步文件夹）
public struct LocalDirectoryRemote: SyncRemote {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    public func read(_ path: String) async throws -> Data? {
        let url = url(path)
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    public func write(_ path: String, data: Data) async throws {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func delete(_ path: String) async throws {
        try? FileManager.default.removeItem(at: url(path))
    }

    public func makeDirectory(_ path: String) async throws {
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
    }

    public func listDirectories(_ path: String) async throws -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: url(path), includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }
}
