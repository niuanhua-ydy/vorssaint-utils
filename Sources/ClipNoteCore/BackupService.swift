import Foundation

/// 备份的导出与导入。
///
/// 备份文件为 zip，内容：
/// - `manifest.json`：格式版本、导出时间、条目数、分类列表
/// - `items.jsonl`：每行一条记录（流式读写，十万级条目也不需要一次性载入内存）
/// - `files/`：图片与富文本原始数据（保持 Images/、Data/ 相对路径）
public enum BackupService {
    public static let formatIdentifier = "clipnote-backup"
    public static let formatVersion = 1

    public struct Manifest: Codable {
        public var format: String
        public var version: Int
        public var exportedAt: Date
        public var appVersion: String
        public var itemCount: Int
        public var pinboards: [PinboardRecord]
    }

    public struct PinboardRecord: Codable {
        public var name: String
        public var color: String
    }

    struct ItemRecord: Codable {
        var type: String
        var content: String
        /// 与 content 不同时才写出（如 OCR 文本）
        var searchText: String?
        var dataPath: String?
        var dataType: String?
        var sourceBundleID: String?
        var sourceAppName: String?
        var charCount: Int
        var width: Int
        var height: Int
        var hash: String
        var createdAt: Date
        var updatedAt: Date
        var useCount: Int
        var pinboard: String?
        var tags: String?
        var aiSummary: String?
        var title: String?
    }

    public struct ImportSummary: Sendable {
        public var inserted: Int
        /// 本地已有相同内容而跳过
        public var skipped: Int
        /// 备份中缺少图片文件而无法导入
        public var missingFiles: Int
        public var pinboardsCreated: Int
    }

    public enum BackupError: LocalizedError {
        case invalidArchive(String)
        case archiveTool(String)

        public var errorDescription: String? {
            switch self {
            case .invalidArchive(let reason): return "不是有效的 ClipNote 备份：\(reason)"
            case .archiveTool(let output): return "压缩 / 解压失败：\(output)"
            }
        }
    }

    // MARK: - 导出

    /// 导出到 zip 文件，返回导出的条目数。progress 回调参数为已处理条目数。
    @discardableResult
    public static func export(store: ClipStore, to archive: URL, onlyPinned: Bool = false, appVersion: String = "",
                              progress: ((Int) -> Void)? = nil) throws -> Int {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("clipnote-export-\(UUID().uuidString)")
        let root = work.appendingPathComponent("ClipNote-Backup")
        let filesDir = root.appendingPathComponent("files")
        try fm.createDirectory(at: filesDir.appendingPathComponent("Images"), withIntermediateDirectories: true)
        try fm.createDirectory(at: filesDir.appendingPathComponent("Data"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let boards = store.pinboards()
        let boardNames = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0.name) })
        let itemsURL = root.appendingPathComponent("items.jsonl")
        fm.createFile(atPath: itemsURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: itemsURL)
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        var count = 0
        try store.forEachItemBatch(onlyPinned: onlyPinned) { batch in
            var chunk = Data()
            for item in batch {
                let record = ItemRecord(
                    type: item.type.rawValue, content: item.content,
                    searchText: item.searchText == String(item.content.prefix(ClipStore.searchTextLimit)) ? nil : item.searchText,
                    dataPath: item.dataPath, dataType: item.dataType,
                    sourceBundleID: item.sourceBundleID, sourceAppName: item.sourceAppName,
                    charCount: item.charCount, width: item.width, height: item.height, hash: item.hash,
                    createdAt: item.createdAt, updatedAt: item.updatedAt, useCount: item.useCount,
                    pinboard: item.pinboardID.flatMap { boardNames[$0] }, tags: item.tags, aiSummary: item.aiSummary,
                    title: item.title)
                chunk.append(try encoder.encode(record))
                chunk.append(0x0A)
                for relative in [item.type == .image ? item.content : nil, item.dataPath].compactMap({ $0 }) {
                    let source = store.url(forRelativePath: relative)
                    if fm.fileExists(atPath: source.path) {
                        try? fm.copyItem(at: source, to: filesDir.appendingPathComponent(relative))
                    }
                }
                count += 1
            }
            try handle.write(contentsOf: chunk)
            progress?(count)
        }

        let manifest = Manifest(format: formatIdentifier, version: formatVersion, exportedAt: Date(), appVersion: appVersion,
                                itemCount: count, pinboards: boards.map { PinboardRecord(name: $0.name, color: $0.color) })
        let manifestEncoder = JSONEncoder()
        manifestEncoder.dateEncodingStrategy = .iso8601
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try manifestEncoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"))

        try? fm.removeItem(at: archive)
        try runDitto(["-c", "-k", "--keepParent", root.path, archive.path])
        return count
    }

    // MARK: - 导入

    public static func readManifest(from archive: URL) throws -> Manifest {
        try withExtractedArchive(archive) { root in try loadManifest(root) }
    }

    /// 从 zip 备份合并导入。progress 回调参数为已处理条目数。
    public static func importBackup(from archive: URL, into store: ClipStore,
                                    progress: ((Int) -> Void)? = nil) throws -> ImportSummary {
        try withExtractedArchive(archive) { root in
            let manifest = try loadManifest(root)
            let fm = FileManager.default

            // 分类按名称对应，不存在则创建
            var boardIDs = Dictionary(store.pinboards().map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
            var created = 0
            for board in manifest.pinboards where boardIDs[board.name] == nil {
                if let new = store.createPinboard(name: board.name, color: board.color) {
                    boardIDs[board.name] = new.id
                    created += 1
                }
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            var summary = ImportSummary(inserted: 0, skipped: 0, missingFiles: 0, pinboardsCreated: created)
            var batch: [ImportedClip] = []
            var processed = 0

            func flush() throws {
                guard !batch.isEmpty else { return }
                let result = try store.importClips(batch, notify: false)
                summary.inserted += result.inserted
                summary.skipped += result.skipped
                processed += batch.count
                batch.removeAll(keepingCapacity: true)
                progress?(processed)
            }

            try forEachLine(of: root.appendingPathComponent("items.jsonl")) { line in
                guard !line.isEmpty else { return }
                var record = try decoder.decode(ItemRecord.self, from: line)
                guard let type = ClipType(rawValue: record.type) else { return }
                // 带文件的条目先查重，已存在就不必复制文件（其余条目在写入时批量去重）
                let hasFiles = type == .image || record.dataPath != nil
                if hasFiles && store.contains(hash: record.hash) {
                    summary.skipped += 1
                    processed += 1
                    return
                }
                if type == .image {
                    guard let copied = copyFile(record.content, from: root, into: store, fm: fm) else {
                        summary.missingFiles += 1
                        processed += 1
                        return
                    }
                    record.content = copied
                }
                if let dataPath = record.dataPath {
                    record.dataPath = copyFile(dataPath, from: root, into: store, fm: fm)
                    if record.dataPath == nil { record.dataType = nil }
                }
                let clip = NewClip(
                    type: record.dataPath == nil && type == .rich ? .text : type,
                    content: record.content, dataPath: record.dataPath, dataType: record.dataType,
                    searchText: record.searchText ?? (type == .image ? "" : record.content),
                    sourceBundleID: record.sourceBundleID, sourceAppName: record.sourceAppName,
                    charCount: record.charCount, width: record.width, height: record.height, hash: record.hash)
                batch.append(ImportedClip(clip: clip, createdAt: record.createdAt, updatedAt: record.updatedAt,
                                          useCount: record.useCount, pinboardID: record.pinboard.flatMap { boardIDs[$0] },
                                          tags: record.tags, aiSummary: record.aiSummary, title: record.title))
                if batch.count >= 1000 { try flush() }
            }
            try flush()
            store.postChangeNotification()
            return summary
        }
    }

    // MARK: - 内部

    private static func loadManifest(_ root: URL) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) else {
            throw BackupError.invalidArchive("缺少 manifest.json")
        }
        let manifest = try decoder.decode(Manifest.self, from: data)
        guard manifest.format == formatIdentifier else { throw BackupError.invalidArchive("格式标识不符") }
        guard manifest.version <= formatVersion else {
            throw BackupError.invalidArchive("备份来自更新版本的 ClipNote（格式 v\(manifest.version)），请先升级")
        }
        return manifest
    }

    /// 复制备份中的文件到数据目录，使用新文件名避免冲突；返回新的相对路径
    private static func copyFile(_ relative: String, from root: URL, into store: ClipStore, fm: FileManager) -> String? {
        let source = root.appendingPathComponent("files").appendingPathComponent(relative)
        guard fm.fileExists(atPath: source.path) else { return nil }
        let folder = (relative as NSString).deletingLastPathComponent
        let ext = (relative as NSString).pathExtension
        let newRelative = "\(folder)/\(UUID().uuidString).\(ext)"
        do {
            try fm.copyItem(at: source, to: store.url(forRelativePath: newRelative))
            return newRelative
        } catch {
            return nil
        }
    }

    private static func withExtractedArchive<T>(_ archive: URL, _ body: (URL) throws -> T) throws -> T {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("clipnote-import-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try runDitto(["-x", "-k", archive.path, work.path])
        // 兼容压缩包内有一层顶级目录或没有
        let candidates = [work] + ((try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? [])
        guard let root = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) else {
            throw BackupError.invalidArchive("缺少 manifest.json")
        }
        return try body(root)
    }

    /// 逐行读取大文件
    private static func forEachLine(of url: URL, _ body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                try body(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
        if !buffer.isEmpty { try body(buffer) }
    }

    static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BackupError.archiveTool(output)
        }
    }
}
