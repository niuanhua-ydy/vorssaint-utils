import Foundation

/// 读取 Paste（com.wiheads.paste）本机数据库，用于迁移。records / summary / count 需在同一线程调用，decode 可并行。只读：先把数据库复制到临时目录再打开，
/// 大文件（_EXTERNAL_DATA）直接从 Paste 目录读取，不做任何写入。
///
/// Paste 使用 Core Data（SQLite）：
/// - `ZITEMENTITY`：条目（创建 / 最近使用时间、来源应用、所属 Pinboard、标题）
/// - `ZITEMDATAENTITY.ZRAWPASTEBOARDITEMS`：复制当时的剪贴板原始数据（个别条目有多份，取最新一份）。首字节 1 = 内联数据，
///   2 = 外部文件（其后为文件名）；数据本身是二进制 plist，可能经过 LZFSE 压缩（以 "bvx" 开头）。
///   plist 结构：[{ "types": [类型], "dataByType": { 类型: 数据 } }]，每个元素对应剪贴板上的一项。
/// - `ZLISTENTITY`：Pinboard（ZRAWATTRIBUTES 为 JSON：{"type":"pinboard","colorCode":整数 RGB}）
/// - `ZAPPLICATIONENTITY`：来源应用
public final class PasteLibrary: @unchecked Sendable {
    public static let bundleIdentifier = "com.wiheads.paste"

    /// Paste 默认的数据目录
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste",
                                    isDirectory: true)
    }

    public struct Pinboard: Sendable {
        public var name: String
        /// 如 "#F0544D"
        public var color: String
    }

    public struct Record: Sendable {
        /// Paste 内部主键，按它的顺序读取，也用作断点续传的位置
        public var key: Int64
        public var createdAt: Date
        public var lastUsedAt: Date
        public var sourceBundleID: String?
        public var sourceAppName: String?
        public var pinboard: String?
        public var title: String?
        /// 原始数据（尚未解码，解码放到并行阶段做）
        public var raw: Data
    }

    public struct Summary: Sendable {
        /// Core Data 存储的唯一标识，用来判断断点续传是否针对同一个 Paste 数据库
        public var storeID: String
        public var itemCount: Int
        public var pinboards: [Pinboard]
        public var earliest: Date?
        public var latest: Date?
    }

    public enum LibraryError: LocalizedError {
        case notFound(URL)
        case notReadable(URL, String)
        case unsupported(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let url): return "没有找到 Paste 的数据库：\(url.path)"
            case .notReadable(_, let reason): return "无法读取 Paste 的数据库：\(reason)"
            case .unsupported(let reason): return "不支持的 Paste 数据格式：\(reason)"
            }
        }
    }

    public let directory: URL
    private let externalDirectory: URL
    private let workDirectory: URL
    private let db: SQLiteDatabase
    private var apps: [Int64: (String?, String?)] = [:]
    private var lists: [Int64: Pinboard] = [:]

    /// directory：Paste 数据目录（包含 db.sqlite）。会复制数据库到临时目录。
    public init(directory: URL = PasteLibrary.defaultDirectory) throws {
        self.directory = directory
        externalDirectory = directory.appendingPathComponent(".db_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        let fm = FileManager.default
        let source = directory.appendingPathComponent("db.sqlite")
        guard fm.fileExists(atPath: source.path) else { throw LibraryError.notFound(source) }
        workDirectory = fm.temporaryDirectory.appendingPathComponent("clipnote-paste-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        do {
            // 连同 WAL 一起复制，才能读到 Paste 最近写入、尚未合并进主文件的数据
            for suffix in ["", "-wal", "-shm"] {
                let file = directory.appendingPathComponent("db.sqlite" + suffix)
                guard fm.fileExists(atPath: file.path) else { continue }
                try fm.copyItem(at: file, to: workDirectory.appendingPathComponent("db.sqlite" + suffix))
            }
        } catch {
            try? fm.removeItem(at: workDirectory)
            throw LibraryError.notReadable(source, error.localizedDescription)
        }
        do {
            db = try SQLiteDatabase(path: workDirectory.appendingPathComponent("db.sqlite").path)
            let tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.text(0) })
            guard ["ZITEMENTITY", "ZITEMDATAENTITY", "ZLISTENTITY", "ZAPPLICATIONENTITY"].allSatisfy(tables.contains) else {
                throw LibraryError.unsupported("缺少必要的数据表")
            }
            for (pk, bundle, name) in try db.query("SELECT Z_PK, ZBUNDLEIDENTIFIER, ZNAME FROM ZAPPLICATIONENTITY", map: {
                ($0.int(0), $0.optionalText(1), $0.optionalText(2))
            }) {
                apps[pk] = (bundle, name)
            }
            for (pk, name, attributes) in try db.query("SELECT Z_PK, ZNAME, ZRAWATTRIBUTES FROM ZLISTENTITY", map: {
                ($0.int(0), $0.optionalText(1), $0.data(2))
            }) {
                // 只取 Pinboard（另有一个类型为 clipboard 的列表，代表历史本身）
                guard let name, !name.isEmpty, let attributes,
                      let json = try? JSONSerialization.jsonObject(with: attributes) as? [String: Any],
                      json["type"] as? String == "pinboard" else { continue }
                let code = (json["colorCode"] as? NSNumber)?.intValue ?? 0x8E8E93
                lists[pk] = Pinboard(name: name, color: String(format: "#%06X", code & 0xFFFFFF))
            }
        } catch {
            try? fm.removeItem(at: workDirectory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Core Data 时间戳以 2001-01-01 为起点
    private static func date(_ value: Double) -> Date { Date(timeIntervalSinceReferenceDate: value) }

    public func summary() throws -> Summary {
        let storeID = (try? db.query("SELECT Z_UUID FROM Z_METADATA") { $0.text(0) })?.first ?? directory.path
        let row = try db.query("""
            SELECT COUNT(*), MIN(i.ZCREATEDAT), MAX(i.ZTIMESTAMP)
            FROM ZITEMENTITY i JOIN ZITEMDATAENTITY d ON d.Z_PK = (SELECT MAX(Z_PK) FROM ZITEMDATAENTITY WHERE ZITEM = i.Z_PK)
            """) { ($0.int(0), $0.isNull(1) ? nil : Self.date($0.double(1)), $0.isNull(2) ? nil : Self.date($0.double(2))) }.first
        return Summary(storeID: storeID, itemCount: Int(row?.0 ?? 0),
                       pinboards: lists.values.sorted { $0.name < $1.name }, earliest: row?.1, latest: row?.2)
    }

    /// 主键大于 after 的条目数（用于断点续传时计算剩余量）
    public func count(after key: Int64) throws -> Int {
        Int(try db.query("""
            SELECT COUNT(*) FROM ZITEMENTITY i JOIN ZITEMDATAENTITY d ON d.Z_PK = (SELECT MAX(Z_PK) FROM ZITEMDATAENTITY WHERE ZITEM = i.Z_PK) WHERE i.Z_PK > ?
            """, [.int(key)]) { $0.int(0) }.first ?? 0)
    }

    /// 按主键顺序读取一批条目
    public func records(after key: Int64, limit: Int) throws -> [Record] {
        try db.query("""
            SELECT i.Z_PK, i.ZCREATEDAT, i.ZTIMESTAMP, i.ZUPDATEDAT, i.ZSOURCEAPPLICATION, i.ZLIST, i.ZTITLE,
                   d.ZRAWPASTEBOARDITEMS
            FROM ZITEMENTITY i JOIN ZITEMDATAENTITY d ON d.Z_PK = (SELECT MAX(Z_PK) FROM ZITEMDATAENTITY WHERE ZITEM = i.Z_PK)
            WHERE i.Z_PK > ? ORDER BY i.Z_PK LIMIT ?
            """, [.int(key), .int(Int64(limit))]) { row -> Record in
            let created = row.isNull(1) ? nil : Self.date(row.double(1))
            let used = [row.isNull(2) ? nil : Self.date(row.double(2)), row.isNull(3) ? nil : Self.date(row.double(3)), created]
                .compactMap { $0 }.max() ?? Date()
            let app = row.optionalInt(4).flatMap { apps[$0] }
            let title = row.optionalText(6)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Record(key: row.int(0), createdAt: created ?? used, lastUsedAt: used,
                          sourceBundleID: app?.0, sourceAppName: app?.1,
                          pinboard: row.optionalInt(5).flatMap { lists[$0]?.name },
                          title: title?.isEmpty == false ? title : nil, raw: row.data(7) ?? Data())
        }
    }

    /// 把原始数据解码为剪贴板各项的「类型 → 数据」。线程安全，可并行调用。
    public func decode(_ raw: Data) throws -> [[String: Data]] {
        guard let marker = raw.first else { return [] }
        var body = raw.dropFirst()
        if marker == 2 {
            // 外部文件：其后是以 0 结尾的文件名
            let nameBytes = body.prefix { $0 != 0 }
            guard let name = String(data: Data(nameBytes), encoding: .utf8), !name.isEmpty, !name.contains("/") else {
                throw LibraryError.unsupported("外部文件名无效")
            }
            body = try Data(contentsOf: externalDirectory.appendingPathComponent(name), options: .mappedIfSafe)[...]
        }
        var plistData = Data(body)
        if plistData.starts(with: Array("bvx".utf8)) {
            plistData = try (plistData as NSData).decompressed(using: .lzfse) as Data
        }
        guard let items = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [[String: Any]] else {
            throw LibraryError.unsupported("剪贴板数据结构不符")
        }
        return items.map { item in
            (item["dataByType"] as? [String: Data]) ?? [:]
        }
    }
}
