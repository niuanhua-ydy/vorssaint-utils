import Foundation

/// 剪贴板条目与分类的持久化层。
///
/// 存储结构（v2）：
/// - `clip_item`：窄表，只含元数据与短预览，列表 / 过滤 / 排序只读这张表。
/// - `clip_content`：完整正文与可搜索文本，只在粘贴、预览、建索引时读取。
/// - `seq`：按「最近使用时间」递增的唯一序号（0.1 秒精度的时间戳），条目被再次复制或粘贴时会刷新。
///   它同时是 `clip_content` 与两个 FTS 索引的 rowid，因此全文检索可以按时间倒序提前终止，
///   不必对全部命中计算相关度。
/// - `clip_fts`（trigram）负责 ≥3 字符的子串检索；`clip_word` 负责 1～2 字符的短词（见 SearchQuery）。
///
/// 读写分离：写入走写连接（串行队列），查询走只读连接（另一串行队列）。WAL 模式下读不等写，
/// 导入等大批量写入期间界面查询不会被阻塞。所有方法可从任意线程调用。
public final class ClipStore: @unchecked Sendable {
    public static let didChangeNotification = Notification.Name("ClipNote.ClipStoreDidChange")

    public let directory: URL
    public let imagesDirectory: URL
    public let dataDirectory: URL

    /// 列表中文本条目只携带前 N 个字符的预览，完整内容用 item(id:) 读取
    public static let previewLimit = 300
    /// 写入全文索引的最大字符数
    static let searchTextLimit = 100_000
    /// 搜索时每批取的候选数（按时间倒序），在批内按相关度、时间、使用频率重排
    static let candidateWindow = 600

    /// 写连接及其队列
    let db: SQLiteDatabase
    let queue = DispatchQueue(label: "clipnote.store.write")
    /// 只读连接及其队列
    private let reader: SQLiteDatabase
    private let readQueue = DispatchQueue(label: "clipnote.store.read")
    private let postsNotifications: Bool
    private var maxSeq: Int64 = 0
    /// 是否记录待同步的本地变更（开启同步时由 App 设置）
    public var isSyncRecording: Bool {
        get { syncFlagLock.withLock { syncRecording } }
        set { syncFlagLock.withLock { syncRecording = newValue } }
    }
    private var syncRecording = false
    private let syncFlagLock = NSLock()
    /// 正在应用远端变更时不记录（只在写队列内访问），避免把收到的变更再上传回去
    var applyingRemote = false
    /// 当前搜索的排序结果（只在读队列访问），翻页时复用；数据版本变化即失效
    private var searchCache: SearchCache?
    /// 每次写入提交后递增，用于判断搜索缓存是否过期
    private var dataVersion = 0
    private let versionLock = NSLock()

    public init(directory: URL, postsNotifications: Bool = true) throws {
        self.directory = directory
        self.postsNotifications = postsNotifications
        imagesDirectory = directory.appendingPathComponent("Images", isDirectory: true)
        dataDirectory = directory.appendingPathComponent("Data", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: directory.appendingPathComponent("clipnote.sqlite").path)
        try db.execute("""
            PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;
            PRAGMA temp_store=MEMORY; PRAGMA cache_size=-32000; PRAGMA mmap_size=268435456;
            """)
        try Migrator.migrate(db)
        maxSeq = try db.query("SELECT COALESCE(MAX(seq), 0) FROM clip_item") { $0.int(0) }.first ?? 0
        // 批量写入的暂存表：整批最后一条语句写入正文表，全文索引一次建好（逐行写入会频繁刷新索引段）
        try db.execute("CREATE TEMP TABLE clip_stage (seq INTEGER PRIMARY KEY, content TEXT NOT NULL, search_text TEXT)")

        reader = try SQLiteDatabase(path: directory.appendingPathComponent("clipnote.sqlite").path)
        try reader.execute("""
            PRAGMA query_only=ON; PRAGMA temp_store=MEMORY; PRAGMA cache_size=-32000; PRAGMA mmap_size=268435456;
            """)
    }

    func read<T>(_ body: (SQLiteDatabase) throws -> T) rethrows -> T {
        try readQueue.sync { try body(reader) }
    }

    private var currentVersion: Int {
        versionLock.withLock { dataVersion }
    }

    public func url(forRelativePath path: String) -> URL {
        directory.appendingPathComponent(path)
    }

    // MARK: - 写入

    /// 若已存在相同内容（hash），则移到最前并更新来源，返回 true（去重）
    @discardableResult
    public func touch(hash: String, sourceBundleID: String?, sourceAppName: String?) -> Bool {
        let changed = (try? mutate {
            try renewLocked(where: "hash = ?", [.text(hash)], source: (sourceBundleID, sourceAppName))
        }) ?? false
        if changed { notifyChange() }
        return changed
    }

    public func itemID(hash: String) -> Int64? {
        read { db in (try? db.query("SELECT id FROM clip_item WHERE hash = ?", [.text(hash)]) { $0.int(0) })?.first }
    }

    public func contains(hash: String) -> Bool {
        read { db in
            ((try? db.query("SELECT 1 FROM clip_item WHERE hash = ? LIMIT 1", [.text(hash)]) { _ in true }) ?? []).isEmpty == false
        }
    }

    @discardableResult
    public func insert(_ clip: NewClip, date: Date = Date()) throws -> Int64 {
        let id = try mutate { try insertLocked(clip, date: date) }
        notifyChange()
        return id
    }

    /// 批量写入（单个事务），用于导入与基准测试。dates 与 clips 一一对应。
    public func insertBatch(_ clips: [NewClip], dates: [Date]) throws {
        try mutate {
            for (clip, date) in zip(clips, dates) {
                try insertLocked(clip, date: date, staged: true)
            }
            try flushStageLocked()
        }
        notifyChange()
    }

    /// 导入条目（来自备份或其他剪贴板工具）：只合并，不覆盖、不删除。
    /// - 本地没有的内容：新增，保留原有时间、使用次数、分类与标题；
    /// - 本地已有的同一内容（按哈希）：保留本地条目，仅在本地尚无分类 / 标题时补上。
    /// recordSync 为 false 时，这批导入不上传到同步服务（避免大批量导入耗尽同步流量）。
    /// 整批在一个事务内完成：中途失败或进程被终止时整批回滚，不会留下半条数据。
    public func importClips(_ clips: [ImportedClip], notify: Bool = true,
                            recordSync: Bool = true) throws -> (inserted: Int, skipped: Int) {
        let result: (Int, Int) = try mutate {
            let previous = applyingRemote
            if !recordSync { applyingRemote = true }
            defer { applyingRemote = previous }
            var inserted = 0, skipped = 0
            for imported in clips {
                if let existing = try db.query("SELECT id, pinboard_id, title FROM clip_item WHERE hash = ?",
                                               [.text(imported.clip.hash)], map: { ($0.int(0), $0.optionalInt(1), $0.optionalText(2)) }).first {
                    var changed = false
                    if existing.1 == nil, let board = imported.pinboardID {
                        try db.run("UPDATE clip_item SET pinboard_id = ?, pinned_at = ? WHERE id = ?",
                                   [.int(board), .double(Date().timeIntervalSince1970), .int(existing.0)])
                        changed = true
                    }
                    if existing.2 == nil, let title = imported.title, !title.isEmpty {
                        try db.run("UPDATE clip_item SET title = ?, title_at = ? WHERE id = ?",
                                   [.text(title), .double(Date().timeIntervalSince1970), .int(existing.0)])
                        changed = true
                    }
                    if changed { try recordItemChangeLocked(where: "id = ?", [.int(existing.0)], kind: .meta) }
                    skipped += 1
                    continue
                }
                try insertLocked(imported.clip, date: imported.updatedAt, staged: true, imported: imported)
                inserted += 1
            }
            try flushStageLocked()
            return (inserted, skipped)
        }
        if notify { notifyChange() }
        return result
    }

    /// 清理 Images / Data 目录中没有被任何条目引用的文件（如导入或复制过程中进程被强制终止留下的）。
    /// 只处理修改时间早于 minimumAge 的文件，避免误删正在写入、尚未入库的文件。
    @discardableResult
    public func removeOrphanFiles(minimumAge: TimeInterval = 600) -> Int {
        let referenced: Set<String> = read { db in
            Set((try? db.query("""
                SELECT preview FROM clip_item WHERE type = 'image'
                UNION SELECT data_path FROM clip_item WHERE data_path IS NOT NULL
                """) { $0.text(0) }) ?? [])
        }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-minimumAge)
        var removed = 0
        for folder in ["Images", "Data"] {
            let dir = directory.appendingPathComponent(folder, isDirectory: true)
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where !referenced.contains("\(folder)/\(file.lastPathComponent)") {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                guard modified < cutoff else { continue }
                if (try? fm.removeItem(at: file)) != nil { removed += 1 }
            }
        }
        return removed
    }

    /// 按时间顺序（旧→新）分批读取完整条目，用于导出
    public func forEachItemBatch(onlyPinned: Bool = false, batchSize: Int = 500,
                                 _ body: ([ClipItem]) throws -> Void) throws {
        var cursor: Int64 = -1
        while true {
            let batch: [(Int64, ClipItem)] = try read { db in
                try db.query("""
                    SELECT \(Self.columns), cc.content, COALESCE(cc.search_text, substr(cc.content, 1, \(Self.searchTextLimit)))
                    FROM clip_item c JOIN clip_content cc ON cc.seq = c.seq
                    WHERE c.seq > ? \(onlyPinned ? "AND c.pinboard_id IS NOT NULL" : "")
                    ORDER BY c.seq LIMIT ?
                    """, [.int(cursor), .int(Int64(batchSize))]) { ($0.int(Self.seqColumn), Self.mapItem($0, full: true)) }
            }
            guard let last = batch.last else { return }
            try body(batch.map(\.1))
            cursor = last.0
        }
    }

    /// 粘贴后：使用次数 +1，并移到时间线最前
    public func markUsed(id: Int64) {
        write { try renewLocked(where: "id = ?", [.int(id)], bumpUse: true) }
    }

    /// 追加可搜索文本（如图片 OCR 结果）
    public func appendSearchText(id: Int64, text: String) {
        write {
            try db.run("""
                UPDATE clip_content SET search_text = trim(\(Self.searchTextExpr) || char(10) || ?)
                WHERE seq = (SELECT seq FROM clip_item WHERE id = ?)
                """, [.text(String(text.prefix(Self.searchTextLimit))), .int(id)])
            try recordItemChangeLocked(where: "id = ?", [.int(id)], kind: .meta)
        }
    }

    /// 设置卡片标题；传 nil 或空字符串恢复为默认标题
    public func setTitle(itemID: Int64, title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        write {
            try db.run("UPDATE clip_item SET title = ?, title_at = ? WHERE id = ?",
                       [trimmed.flatMap { $0.isEmpty ? nil : $0 }.map { .text($0) } ?? .null,
                        .double(Date().timeIntervalSince1970), .int(itemID)])
            try recordItemChangeLocked(where: "id = ?", [.int(itemID)], kind: .meta)
        }
    }

    /// 编辑正文。内容即身份（哈希，也是同步的键），所以编辑是以新正文替换原条目：原条目删除
    /// （同步为删除），新条目移到最前，沿用原有的创建时间、使用次数、分类、标题与 AI 字段。
    /// 更新时间取当前时间，否则改回曾经删除过的正文时，其他设备会因删除记录更晚而忽略它。
    /// 新正文与另一条已有条目相同时并入那一条（移到最前，仅在其尚无分类 / 标题时补上）。
    /// 返回编辑后条目的 id；原条目已不存在时返回 nil。
    @discardableResult
    public func replaceContent(itemID: Int64, with clip: NewClip) throws -> Int64? {
        var files: [String] = []
        let id: Int64? = try mutate {
            guard let old = try db.query("""
                SELECT hash, created_at, use_count, pinboard_id, pinned_at, title, title_at, tags, ai_summary
                FROM clip_item WHERE id = ?
                """, [.int(itemID)], map: { row in
                    (hash: row.text(0), createdAt: row.double(1), useCount: row.int(2), pinboardID: row.optionalInt(3),
                     pinnedAt: row.double(4), title: row.optionalText(5), titledAt: row.double(6),
                     tags: row.optionalText(7), aiSummary: row.optionalText(8))
                }).first else { return nil }
            guard old.hash != clip.hash else { return itemID }
            let now = Date().timeIntervalSince1970

            if let existing = try db.query("SELECT id, pinboard_id, title FROM clip_item WHERE hash = ?",
                                           [.text(clip.hash)], map: { ($0.int(0), $0.optionalInt(1), $0.optionalText(2)) }).first {
                files = try deleteLocked("id = ?", [.int(itemID)], recordSync: true, at: now)
                var changed = false
                if existing.1 == nil, let board = old.pinboardID {
                    try db.run("UPDATE clip_item SET pinboard_id = ?, pinned_at = ? WHERE id = ?",
                               [.int(board), .double(old.pinnedAt), .int(existing.0)])
                    changed = true
                }
                if existing.2 == nil, let title = old.title {
                    try db.run("UPDATE clip_item SET title = ?, title_at = ? WHERE id = ?",
                               [.text(title), .double(old.titledAt), .int(existing.0)])
                    changed = true
                }
                if changed { try recordItemChangeLocked(where: "id = ?", [.int(existing.0)], kind: .meta) }
                try renewLocked(where: "id = ?", [.int(existing.0)])
                return existing.0
            }

            files = try deleteLocked("id = ?", [.int(itemID)], recordSync: true, at: now)
            let date = Date()
            let imported = ImportedClip(clip: clip, createdAt: Date(timeIntervalSince1970: old.createdAt),
                                        updatedAt: date, useCount: Int(old.useCount), pinboardID: old.pinboardID,
                                        tags: old.tags, aiSummary: old.aiSummary, title: old.title, titledAt: old.titledAt)
            return try insertLocked(clip, date: date, imported: imported, pinnedAt: old.pinnedAt)
        }
        removeFiles(files)
        notifyChange()
        return id
    }

    // MARK: - 图片文字识别状态

    public enum OCRState: Int, Sendable {
        case pending = 0
        case done = 1
        case failed = 2
    }

    public struct OCRStats: Equatable, Sendable {
        public var total = 0
        public var done = 0
        public var failed = 0
        public var pending: Int { total - done - failed }

        public init() {}
    }

    public func ocrStats() -> OCRStats {
        read { db in
            var stats = OCRStats()
            for (state, count) in (try? db.query("SELECT ocr_state, COUNT(*) FROM clip_item WHERE type = 'image' GROUP BY ocr_state",
                                                 map: { ($0.int(0), Int($0.int(1))) })) ?? [] {
                stats.total += count
                if state == OCRState.done.rawValue { stats.done += count }
                if state == OCRState.failed.rawValue { stats.failed += count }
            }
            return stats
        }
    }

    /// 尚未识别的图片（最近的优先）
    public func pendingOCRImages(limit: Int) -> [(id: Int64, url: URL)] {
        read { db in
            ((try? db.query("""
                SELECT id, preview FROM clip_item WHERE type = 'image' AND ocr_state = 0 ORDER BY seq DESC LIMIT ?
                """, [.int(Int64(limit))]) { ($0.int(0), $0.text(1)) }) ?? []).map { ($0.0, url(forRelativePath: $0.1)) }
        }
    }

    /// 记录识别结果：text 为 nil 表示无法识别（不再重试）；识别出文字时追加到可搜索文本。
    /// recordSync 为 false 时不上传到同步服务（后台补充识别只在本机进行）；
    /// notify 为 false 时不立即通知界面刷新（批量处理时由调用方定期调用 postChangeNotification）。
    public func completeOCR(id: Int64, text: String?, recordSync: Bool = true, notify: Bool = true) {
        _ = try? mutate {
            let previous = applyingRemote
            if !recordSync { applyingRemote = true }
            defer { applyingRemote = previous }
            if let text, !text.isEmpty {
                try db.run("""
                    UPDATE clip_content SET search_text = trim(\(Self.searchTextExpr) || char(10) || ?)
                    WHERE seq = (SELECT seq FROM clip_item WHERE id = ?)
                    """, [.text(String(text.prefix(Self.searchTextLimit))), .int(id)])
                try recordItemChangeLocked(where: "id = ?", [.int(id)], kind: .meta)
            }
            try db.run("UPDATE clip_item SET ocr_state = ? WHERE id = ?",
                       [.int(Int64(text == nil ? OCRState.failed.rawValue : OCRState.done.rawValue)), .int(id)])
        }
        if notify { notifyChange() }
    }

    public func setPinboard(itemID: Int64, pinboardID: Int64?) {
        write {
            try db.run("UPDATE clip_item SET pinboard_id = ?, pinned_at = ? WHERE id = ?",
                       [pinboardID.map { .int($0) } ?? .null, .double(Date().timeIntervalSince1970), .int(itemID)])
            try recordItemChangeLocked(where: "id = ?", [.int(itemID)], kind: .meta)
        }
    }

    public func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        deleteMatching("id IN (\(placeholders))", ids.map { .int($0) }, recordSync: true)
    }

    /// 清空历史（默认保留已固定到分类的条目）
    public func clearHistory(keepPinned: Bool = true) {
        deleteMatching(keepPinned ? "pinboard_id IS NULL" : "1", [], recordSync: true)
    }

    /// 按保留时长与条数上限清理（已固定到分类的条目不受影响）。参数为 0 表示不限制。
    public func applyRetention(maxAgeDays: Int, maxItems: Int) {
        if maxAgeDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
            deleteMatching("pinboard_id IS NULL AND seq < ?", [.int(Self.seq(for: cutoff))])
        }
        if maxItems > 0 {
            deleteMatching("""
                pinboard_id IS NULL AND seq < (
                    SELECT seq FROM clip_item WHERE pinboard_id IS NULL ORDER BY seq DESC LIMIT 1 OFFSET ?)
                """, [.int(Int64(maxItems - 1))])
        }
    }

    // MARK: - 查询

    /// 读取完整条目（含完整正文与可搜索文本）
    public func item(id: Int64) -> ClipItem? {
        read { db in
            (try? db.query("""
                SELECT \(Self.columns), cc.content, COALESCE(cc.search_text, substr(cc.content, 1, \(Self.searchTextLimit)))
                FROM clip_item c JOIN clip_content cc ON cc.seq = c.seq WHERE c.id = ?
                """, [.int(id)]) { Self.mapItem($0, full: true) })?.first
        }
    }

    public func count() -> Int {
        read { db in Int((try? db.query("SELECT COUNT(*) FROM clip_item") { $0.int(0) })?.first ?? 0) }
    }

    /// 列表与搜索。结果中文本条目的 content 为预览；搜索时长文本的 content 为命中位置附近的摘要。
    public func fetch(_ query: ClipQuery) -> [ClipItem] {
        readQueue.sync {
            do {
                return try fetchLocked(query)
            } catch {
                log(error)
                return []
            }
        }
    }

    public func sourceApps() -> [SourceApp] {
        read { db in
            (try? db.query("SELECT bundle_id, name FROM source_app WHERE item_count > 0 ORDER BY item_count DESC") {
                SourceApp(bundleID: $0.text(0), name: $0.optionalText(1) ?? $0.text(0))
            }) ?? []
        }
    }

    /// 丢弃搜索结果缓存（基准测试用）
    public func discardSearchCache() {
        readQueue.sync { searchCache = nil }
    }

    // MARK: - 分类（Pinboard）

    public func pinboards() -> [Pinboard] {
        read { db in
            (try? db.query("SELECT id, name, color, sort_order FROM pinboard ORDER BY sort_order, id") {
                Pinboard(id: $0.int(0), name: $0.text(1), color: $0.text(2), sortOrder: Int($0.int(3)))
            }) ?? []
        }
    }

    @discardableResult
    public func createPinboard(name: String, color: String) -> Pinboard? {
        let board: Pinboard? = try? mutate {
            let order = try db.query("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM pinboard") { $0.int(0) }.first ?? 1
            try db.run("INSERT INTO pinboard (name, color, sort_order, updated_at) VALUES (?, ?, ?, ?)",
                       [.text(name), .text(color), .int(order), .double(Date().timeIntervalSince1970)])
            let id = db.lastInsertRowID
            try recordSyncChangeLocked(key: "board:" + name, kind: .board)
            return Pinboard(id: id, name: name, color: color, sortOrder: Int(order))
        }
        notifyChange()
        return board
    }

    public func updatePinboard(_ board: Pinboard) {
        write {
            let oldName = try db.query("SELECT name FROM pinboard WHERE id = ?", [.int(board.id)]) { $0.text(0) }.first
            let now = Date().timeIntervalSince1970
            try db.run("UPDATE pinboard SET name = ?, color = ?, sort_order = ?, updated_at = ? WHERE id = ?",
                       [.text(board.name), .text(board.color), .int(Int64(board.sortOrder)), .double(now), .int(board.id)])
            try recordSyncChangeLocked(key: "board:" + board.name, kind: .board)
            if let oldName, oldName != board.name {
                // 同步以名称识别分类：改名 = 新建新名称 + 删除旧名称，并更新其中条目的分类
                try recordSyncChangeLocked(key: "board:" + oldName, kind: .boardDelete)
                try db.run("UPDATE clip_item SET pinned_at = ? WHERE pinboard_id = ?", [.double(now), .int(board.id)])
                try recordItemChangeLocked(where: "pinboard_id = ?", [.int(board.id)], kind: .meta)
            }
        }
    }

    /// 删除分类；其中的条目回到普通历史（不删除）
    public func deletePinboard(id: Int64) {
        write {
            guard let name = try db.query("SELECT name FROM pinboard WHERE id = ?", [.int(id)], map: { $0.text(0) }).first else { return }
            let now = Date().timeIntervalSince1970
            try db.run("UPDATE clip_item SET pinned_at = ? WHERE pinboard_id = ?", [.double(now), .int(id)])
            try recordItemChangeLocked(where: "pinboard_id = ?", [.int(id)], kind: .meta)
            try db.run("DELETE FROM pinboard WHERE id = ?", [.int(id)])
            try recordSyncChangeLocked(key: "board:" + name, kind: .boardDelete)
        }
    }

    // MARK: - 写入实现（需在队列内调用）

    /// staged 为 true 时正文先写入暂存表，调用方需在同一事务内调用 flushStageLocked()
    @discardableResult
    func insertLocked(_ clip: NewClip, date: Date, staged: Bool = false, imported: ImportedClip? = nil,
                      pinnedAt: Double = 0) throws -> Int64 {
        if let id = try db.query("SELECT id FROM clip_item WHERE hash = ?", [.text(clip.hash)], map: { $0.int(0) }).first {
            try renewLocked(where: "id = ?", [.int(id)], date: date)
            return id
        }
        let seq = try nextSeqLocked(for: date)
        // 可搜索文本与正文相同时不重复存储（NULL 表示取正文前 searchTextLimit 个字符）
        let searchText = String(clip.searchText.prefix(Self.searchTextLimit))
        let storedSearchText: SQLValue = searchText == String(clip.content.prefix(Self.searchTextLimit)) ? .null : .text(searchText)
        try db.run("INSERT INTO \(staged ? "temp.clip_stage" : "clip_content") (seq, content, search_text) VALUES (?, ?, ?)",
                   [.int(seq), .text(clip.content), storedSearchText])
        try db.run("""
            INSERT INTO clip_item (type, preview, data_path, data_type, source_bundle_id, source_app_name,
                char_count, width, height, hash, created_at, updated_at, seq, use_count, pinboard_id, tags, ai_summary,
                pinned_at, title, title_at, ocr_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(clip.type.rawValue), .text(Self.preview(type: clip.type, content: clip.content)),
                clip.dataPath.sqlValue, clip.dataType.sqlValue, clip.sourceBundleID.sqlValue, clip.sourceAppName.sqlValue,
                .int(Int64(clip.charCount)), .int(Int64(clip.width)), .int(Int64(clip.height)),
                .text(clip.hash), .double((imported?.createdAt ?? date).timeIntervalSince1970), .double(date.timeIntervalSince1970),
                .int(seq), .int(Int64(imported?.useCount ?? 0)), imported?.pinboardID.map { .int($0) } ?? .null,
                imported?.tags.sqlValue ?? .null, imported?.aiSummary.sqlValue ?? .null,
                .double(imported?.pinboardID != nil && pinnedAt == 0 ? date.timeIntervalSince1970 : pinnedAt),
                imported?.title.flatMap { $0.isEmpty ? nil : $0 }.map { .text($0) } ?? .null,
                .double(imported?.title == nil ? 0 : (imported!.titledAt > 0 ? imported!.titledAt : date.timeIntervalSince1970)),
                // 带有识别文字的图片（来自同步或备份）视为已识别
                .int(Int64(clip.type == .image && !searchText.isEmpty ? OCRState.done.rawValue : OCRState.pending.rawValue)),
            ])
        let id = db.lastInsertRowID
        try recordSyncChangeLocked(key: "item:" + clip.hash, kind: .upsert)
        return id
    }

    /// 把暂存表中的正文一次性写入正文表（触发器在同一条语句内建立全文索引）
    func flushStageLocked() throws {
        try db.run("INSERT INTO clip_content (seq, content, search_text) SELECT seq, content, search_text FROM temp.clip_stage")
        try db.run("DELETE FROM temp.clip_stage")
    }

    /// 把条目移到时间线最前：刷新更新时间与时间序号（正文表与两个索引由触发器同步）
    @discardableResult
    func renewLocked(where condition: String, _ params: [SQLValue], bumpUse: Bool = false,
                             source: (String?, String?)? = nil, date: Date = Date()) throws -> Bool {
        guard let old = try db.query("SELECT seq FROM clip_item WHERE \(condition)", params, map: { $0.int(0) }).first else {
            return false
        }
        // 已是最新一条且新时间不晚于其序号时（如同一时刻重复复制）无需改序号，避免重建索引
        let seq = old == maxSeq && Self.seq(for: date) <= old ? old : try nextSeqLocked(for: date)
        if seq != old {
            try db.run("UPDATE clip_content SET seq = ? WHERE seq = ?", [.int(seq), .int(old)])
            // 同一批次中尚在暂存表里的正文也要同步序号
            try db.run("UPDATE temp.clip_stage SET seq = ? WHERE seq = ?", [.int(seq), .int(old)])
        }
        var sql = "UPDATE clip_item SET seq = ?, updated_at = ?"
        var values: [SQLValue] = [.int(seq), .double(date.timeIntervalSince1970)]
        if bumpUse { sql += ", use_count = use_count + 1" }
        if let source {
            sql += ", source_bundle_id = COALESCE(?, source_bundle_id), source_app_name = COALESCE(?, source_app_name)"
            values += [source.0.sqlValue, source.1.sqlValue]
        }
        try db.run(sql + " WHERE seq = ?", values + [.int(old)])
        try recordItemChangeLocked(where: "seq = ?", [.int(seq)], kind: .meta)
        return true
    }

    private func nextSeqLocked(for date: Date) throws -> Int64 {
        var candidate = Self.seq(for: date)
        if candidate <= maxSeq {
            if abs(date.timeIntervalSinceNow) < 5 {
                // 当前时间（同一时刻或时钟回拨）：保持严格递增
                candidate = maxSeq + 1
            } else {
                // 历史时间（导入、同步）：取该时间点附近的空闲序号，保持时间顺序
                while try !db.query("SELECT 1 FROM clip_item WHERE seq = ?", [.int(candidate)], map: { _ in 1 }).isEmpty {
                    candidate += 1
                }
            }
        }
        // 顺延出的序号可能超过当前最大值，必须同步更新，否则后续分配会撞号
        maxSeq = max(maxSeq, candidate)
        return candidate
    }

    /// 0.1 秒精度：FTS 的 doclist 以变长整数存相邻 rowid 的差值，精度越粗索引越小
    static let seqPerSecond: Double = 10

    static func seq(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * seqPerSecond)
    }

    static func preview(type: ClipType, content: String) -> String {
        type == .image || type == .file ? content : String(content.prefix(previewLimit))
    }

    /// 删除匹配的条目（正文与索引由触发器级联删除），并清理关联文件。
    /// recordSync：用户主动删除时同步到其他设备；保留策略的自动清理只作用于本机。
    private func deleteMatching(_ condition: String, _ params: [SQLValue], recordSync: Bool = false) {
        let files: [String] = (try? mutate {
            try deleteLocked(condition, params, recordSync: recordSync, at: Date().timeIntervalSince1970)
        }) ?? []
        removeFiles(files)
        notifyChange()
    }

    /// 返回需要在事务提交后删除的文件
    func deleteLocked(_ condition: String, _ params: [SQLValue], recordSync: Bool, at: Double) throws -> [String] {
        let rows = try db.query("SELECT type, preview, data_path, hash FROM clip_item WHERE \(condition)", params) { row in
            (row.text(0), row.text(1), row.optionalText(2), row.text(3))
        }
        if recordSync && isSyncRecordingActive {
            for row in rows {
                try recordSyncChangeLocked(key: "item:" + row.3, kind: .delete, at: at)
                try db.run("""
                    INSERT INTO sync_tombstone (key, deleted_at) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET deleted_at = max(deleted_at, excluded.deleted_at)
                    """, [.text("item:" + row.3), .double(at)])
            }
        }
        try db.run("DELETE FROM clip_item WHERE \(condition)", params)
        return rows.flatMap { row -> [String] in
            var paths: [String] = []
            if row.0 == ClipType.image.rawValue { paths.append(row.1) }
            if let data = row.2 { paths.append(data) }
            return paths
        }
    }

    public func removeFiles(_ files: [String]) {
        let fm = FileManager.default
        for path in files where !path.isEmpty {
            try? fm.removeItem(at: url(forRelativePath: path))
        }
    }

    /// 在队列内以事务执行写操作，并使搜索缓存失效
    func mutate<T>(_ body: () throws -> T) throws -> T {
        try queue.sync {
            do {
                let result = try db.transaction(body)
                versionLock.withLock { dataVersion += 1 }
                return result
            } catch {
                try? db.run("DELETE FROM temp.clip_stage")
                log(error)
                throw error
            }
        }
    }

    private func write(_ body: () throws -> Void) {
        _ = try? mutate(body)
        notifyChange()
    }

    /// 批量操作（如导入）结束后统一通知一次
    public func postChangeNotification() {
        notifyChange()
    }

    func notifyChange() {
        guard postsNotifications else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    func log(_ error: Error) {
        NSLog("[ClipStore] \(error)")
    }

    // MARK: - 查询实现

    private final class SearchCache {
        let key: String
        let version: Int
        var ranked: [ClipItem] = []
        /// 已在结果中的条目（标题命中与全文命中去重）
        var seen = Set<Int64>()
        /// 下一批候选从这个序号之前开始取
        var cursor: Int64?
        var exhausted = false

        init(key: String, version: Int) {
            self.key = key
            self.version = version
        }
    }

    private func fetchLocked(_ query: ClipQuery) throws -> [ClipItem] {
        var filters: [String] = []
        var params: [SQLValue] = []
        if case .pinboard(let id) = query.scope {
            filters.append("c.pinboard_id = ?")
            params.append(.int(id))
        }
        if let type = query.type {
            filters.append("c.type = ?")
            params.append(.text(type.rawValue))
        }
        if let bundleID = query.sourceBundleID {
            filters.append("c.source_bundle_id = ?")
            params.append(.text(bundleID))
        }

        let search = SearchQuery(query.text)
        guard !search.isEmpty else {
            let whereClause = filters.isEmpty ? "" : "WHERE " + filters.joined(separator: " AND ")
            return try reader.query("""
                SELECT \(Self.columns) FROM clip_item c \(whereClause)
                ORDER BY c.seq DESC LIMIT ? OFFSET ?
                """, params + [.int(Int64(query.limit)), .int(Int64(query.offset))]) { Self.mapItem($0, full: false) }
        }

        let key = [query.text, "\(query.scope)", query.type?.rawValue ?? "", query.sourceBundleID ?? ""].joined(separator: "\u{1}")
        let version = currentVersion
        let cache: SearchCache
        if let existing = searchCache, existing.key == key, existing.version == version {
            cache = existing
        } else {
            cache = SearchCache(key: key, version: version)
            searchCache = cache
            // 自定义标题命中的条目排在最前（每个词都出现在标题中）
            var titleConditions = ["c.title IS NOT NULL"] + filters
            var titleParams = params
            for term in search.terms {
                titleConditions.append("c.title LIKE ? ESCAPE '\\'")
                titleParams.append(.text(SearchQuery.likePattern(term)))
            }
            let titled = try reader.query("""
                SELECT \(Self.columns) FROM clip_item c WHERE \(titleConditions.joined(separator: " AND "))
                ORDER BY c.seq DESC LIMIT 200
                """, titleParams) { Self.mapItem($0, full: false) }
            cache.ranked = titled
            cache.seen = Set(titled.map(\.id))
        }
        while cache.ranked.count < query.offset + query.limit && !cache.exhausted {
            try extendSearchLocked(cache, search: search, filters: filters, filterParams: params)
        }
        guard query.offset < cache.ranked.count else { return [] }
        var page = Array(cache.ranked[query.offset..<min(cache.ranked.count, query.offset + query.limit)])
        try attachSnippetsLocked(&page, terms: search.terms)
        return page
    }

    /// 取下一批候选（按时间序号倒序，FTS 可提前终止），批内重排后追加到结果
    private func extendSearchLocked(_ cache: SearchCache, search: SearchQuery,
                                    filters: [String], filterParams: [SQLValue]) throws {
        var conditions: [String] = []
        var params: [SQLValue] = []
        let sql: String
        let hasRelevance = search.trigramExpression != nil

        if let expression = search.trigramExpression ?? search.wordExpression {
            let table = hasRelevance ? "clip_fts" : "clip_word"
            conditions.append("f.\(table) MATCH ?")
            params.append(.text(expression))
            if hasRelevance, let word = search.wordExpression {
                // "+" 阻止把这个条件下推给 FTS 作为 rowid 约束（否则会对短词的每个命中逐一执行 trigram 匹配）
                conditions.append("+f.rowid IN (SELECT rowid FROM clip_word WHERE clip_word MATCH ?)")
                params.append(.text(word))
            }
            for term in search.likeTerms {
                conditions.append("(SELECT \(Self.searchTextExpr) FROM clip_content WHERE seq = f.rowid) LIKE ? ESCAPE '\\'")
                params.append(.text(SearchQuery.likePattern(term)))
            }
            conditions += filters
            params += filterParams
            if let cursor = cache.cursor {
                conditions.append("f.rowid < ?")
                params.append(.int(cursor))
            }
            let join = filters.isEmpty ? "" : "JOIN clip_item c ON c.seq = f.rowid"
            sql = """
                SELECT f.rowid, \(hasRelevance ? "bm25(clip_fts)" : "0") FROM \(table) f \(join)
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY f.rowid DESC LIMIT \(Self.candidateWindow)
                """
        } else {
            // 只有少见的短词：按时间倒序扫描正文表
            for term in search.likeTerms {
                conditions.append("\(Self.searchTextExpr) LIKE ? ESCAPE '\\'")
                params.append(.text(SearchQuery.likePattern(term)))
            }
            conditions += filters
            params += filterParams
            if let cursor = cache.cursor {
                conditions.append("f.seq < ?")
                params.append(.int(cursor))
            }
            let join = filters.isEmpty ? "" : "JOIN clip_item c ON c.seq = f.seq"
            sql = """
                SELECT f.seq, 0 FROM clip_content f \(join)
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY f.seq DESC LIMIT \(Self.candidateWindow)
                """
        }

        let candidates = try reader.query(sql, params) { ($0.int(0), $0.double(1)) }
        cache.cursor = candidates.last?.0
        if candidates.count < Self.candidateWindow { cache.exhausted = true }
        guard !candidates.isEmpty else { return }

        let placeholders = candidates.map { _ in "?" }.joined(separator: ",")
        let items = try reader.query("SELECT \(Self.columns) FROM clip_item c WHERE c.seq IN (\(placeholders))",
                                 candidates.map { .int($0.0) }) { ($0.int(Self.seqColumn), Self.mapItem($0, full: false)) }
        let itemsBySeq = Dictionary(items, uniquingKeysWith: { a, _ in a })

        // 综合排序：相关度（bm25，越小越相关）+ 时间衰减 + 使用频率
        let maxRelevance = max(candidates.map { -$0.1 }.max() ?? 1, 1e-9)
        let maxUse = Double(items.map(\.1.useCount).max() ?? 0)
        let now = Date().timeIntervalSince1970
        let ranked = candidates.compactMap { seq, bm25 -> (ClipItem, Double)? in
            guard let item = itemsBySeq[seq] else { return nil }
            let relevance = hasRelevance ? -bm25 / maxRelevance : 1
            let ageDays = max(0, now - item.updatedAt.timeIntervalSince1970) / 86400
            let frequency = maxUse > 0 ? log1p(Double(item.useCount)) / log1p(maxUse) : 0
            return (item, 0.45 * relevance + 0.4 * exp(-ageDays / 30) + 0.15 * frequency)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
        .filter { cache.seen.insert($0.id).inserted }
        cache.ranked += ranked
    }

    /// 长文本的命中位置可能不在预览里：为当前页的长文本条目截取命中附近的摘要
    private func attachSnippetsLocked(_ page: inout [ClipItem], terms: [String]) throws {
        guard let term = terms.max(by: { $0.count < $1.count })?.lowercased() else { return }
        let ids = page.filter { $0.type.isTextual && $0.charCount > Self.previewLimit }.map(\.id)
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let snippets = try reader.query("""
            SELECT c.id, instr(lower(cc.content), ?) AS pos,
                   substr(cc.content, max(1, instr(lower(cc.content), ?) - 40), \(Self.previewLimit + 60))
            FROM clip_item c JOIN clip_content cc ON cc.seq = c.seq WHERE c.id IN (\(placeholders))
            """, [.text(term), .text(term)] + ids.map { .int($0) }) { row in
            (row.int(0), (row.int(1) > 41 ? "…" : "") + row.text(2))
        }
        let byID = Dictionary(snippets, uniquingKeysWith: { a, _ in a })
        for i in page.indices {
            if let snippet = byID[page[i].id] { page[i].content = snippet }
        }
    }

    /// clip_content 中实际的可搜索文本
    static let searchTextExpr = "COALESCE(search_text, substr(content, 1, \(searchTextLimit)))"

    static let columnNames = [
        "id", "type", "preview", "data_path", "data_type", "source_bundle_id", "source_app_name",
        "char_count", "width", "height", "hash", "created_at", "updated_at", "use_count", "pinboard_id",
        "tags", "ai_summary", "seq", "title",
    ]
    static let columns = columnNames.map { "c.\($0)" }.joined(separator: ", ")
    static let seqColumn = Int32(columnNames.firstIndex(of: "seq")!)

    static func mapItem(_ row: SQLiteDatabase.Row, full: Bool) -> ClipItem {
        let fullStart = Int32(columnNames.count)
        return ClipItem(
            id: row.int(0),
            type: ClipType(rawValue: row.text(1)) ?? .text,
            content: full ? row.text(fullStart) : row.text(2),
            dataPath: row.optionalText(3),
            dataType: row.optionalText(4),
            searchText: full ? row.text(fullStart + 1) : "",
            sourceBundleID: row.optionalText(5),
            sourceAppName: row.optionalText(6),
            charCount: Int(row.int(7)),
            width: Int(row.int(8)),
            height: Int(row.int(9)),
            hash: row.text(10),
            createdAt: Date(timeIntervalSince1970: row.double(11)),
            updatedAt: Date(timeIntervalSince1970: row.double(12)),
            useCount: Int(row.int(13)),
            pinboardID: row.optionalInt(14),
            tags: row.optionalText(15),
            aiSummary: row.optionalText(16),
            title: row.optionalText(18)
        )
    }
}

private extension Optional where Wrapped == String {
    var sqlValue: SQLValue { map { .text($0) } ?? .null }
}

/// 基于 PRAGMA user_version 的数据库迁移
enum Migrator {
    /// v1：初始结构（单表 + trigram 索引）
    static let v1Schema = """
        CREATE TABLE pinboard (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE clip_item (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            data_path TEXT,
            data_type TEXT,
            search_text TEXT NOT NULL DEFAULT '',
            source_bundle_id TEXT,
            source_app_name TEXT,
            char_count INTEGER NOT NULL DEFAULT 0,
            width INTEGER NOT NULL DEFAULT 0,
            height INTEGER NOT NULL DEFAULT 0,
            hash TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            use_count INTEGER NOT NULL DEFAULT 0,
            pinboard_id INTEGER REFERENCES pinboard(id) ON DELETE SET NULL,
            tags TEXT,
            ai_summary TEXT,
            embedding BLOB
        );
        CREATE INDEX idx_clip_updated ON clip_item(updated_at DESC);
        CREATE INDEX idx_clip_pinboard ON clip_item(pinboard_id, updated_at DESC);
        CREATE INDEX idx_clip_source ON clip_item(source_bundle_id);

        CREATE VIRTUAL TABLE clip_fts USING fts5(
            search_text, content='clip_item', content_rowid='id', tokenize='trigram'
        );
        CREATE TRIGGER clip_ai AFTER INSERT ON clip_item BEGIN
            INSERT INTO clip_fts(rowid, search_text) VALUES (new.id, new.search_text);
        END;
        CREATE TRIGGER clip_ad AFTER DELETE ON clip_item BEGIN
            INSERT INTO clip_fts(clip_fts, rowid, search_text) VALUES ('delete', old.id, old.search_text);
        END;
        CREATE TRIGGER clip_au AFTER UPDATE OF search_text ON clip_item BEGIN
            INSERT INTO clip_fts(clip_fts, rowid, search_text) VALUES ('delete', old.id, old.search_text);
            INSERT INTO clip_fts(rowid, search_text) VALUES (new.id, new.search_text);
        END;
        """

    /// v2：大小表分离、时间序号、短词索引、来源应用统计表
    static func migrateToV2(_ db: SQLiteDatabase) throws {
        try db.execute("""
            DROP TRIGGER clip_ai; DROP TRIGGER clip_ad; DROP TRIGGER clip_au;
            DROP TABLE clip_fts;
            DROP INDEX idx_clip_updated; DROP INDEX idx_clip_pinboard; DROP INDEX idx_clip_source;
            ALTER TABLE clip_item ADD COLUMN seq INTEGER NOT NULL DEFAULT 0;
            ALTER TABLE clip_item ADD COLUMN preview TEXT NOT NULL DEFAULT '';
            """)
        // 按更新时间分配唯一、递增的时间序号
        let rows = try db.query("SELECT id, updated_at FROM clip_item ORDER BY updated_at, id") { ($0.int(0), $0.double(1)) }
        var last: Int64 = 0
        for (id, updatedAt) in rows {
            let seq = max(Int64(updatedAt * ClipStore.seqPerSecond), last + 1)
            last = seq
            try db.run("UPDATE clip_item SET seq = ? WHERE id = ?", [.int(seq), .int(id)])
        }
        let newText = "COALESCE(new.search_text, substr(new.content, 1, \(ClipStore.searchTextLimit)))"
        let oldText = "COALESCE(old.search_text, substr(old.content, 1, \(ClipStore.searchTextLimit)))"
        try db.execute("""
            UPDATE clip_item SET preview = CASE WHEN type IN ('image', 'file') THEN content
                                                ELSE substr(content, 1, \(ClipStore.previewLimit)) END;

            -- search_text 为 NULL 表示与正文相同（不重复存储）
            CREATE TABLE clip_content (
                seq INTEGER PRIMARY KEY,
                content TEXT NOT NULL,
                search_text TEXT
            );
            INSERT INTO clip_content (seq, content, search_text)
                SELECT seq, content, NULLIF(search_text, substr(content, 1, \(ClipStore.searchTextLimit))) FROM clip_item;
            CREATE VIEW clip_search AS SELECT seq, \(ClipStore.searchTextExpr) AS search_text FROM clip_content;
            ALTER TABLE clip_item DROP COLUMN content;
            ALTER TABLE clip_item DROP COLUMN search_text;

            CREATE UNIQUE INDEX idx_clip_seq ON clip_item(seq);
            CREATE INDEX idx_clip_type_seq ON clip_item(type, seq);
            CREATE INDEX idx_clip_source_seq ON clip_item(source_bundle_id, seq);
            CREATE INDEX idx_clip_pinboard_seq ON clip_item(pinboard_id, seq);

            CREATE VIRTUAL TABLE clip_fts USING fts5(
                search_text, content='clip_search', content_rowid='seq', tokenize='trigram'
            );
            INSERT INTO clip_fts(clip_fts) VALUES ('rebuild');
            CREATE VIRTUAL TABLE clip_word USING fts5(
                body, content='', contentless_delete=1, detail=none, prefix='1',
                tokenize='unicode61 remove_diacritics 2'
            );
            INSERT INTO clip_word(rowid, body) SELECT seq, clipnote_segment(search_text) FROM clip_search;

            CREATE TRIGGER content_ai AFTER INSERT ON clip_content BEGIN
                INSERT INTO clip_fts(rowid, search_text) VALUES (new.seq, \(newText));
                INSERT INTO clip_word(rowid, body) VALUES (new.seq, clipnote_segment(\(newText)));
            END;
            CREATE TRIGGER content_ad AFTER DELETE ON clip_content BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, search_text) VALUES ('delete', old.seq, \(oldText));
                DELETE FROM clip_word WHERE rowid = old.seq;
            END;
            CREATE TRIGGER content_au AFTER UPDATE OF seq, search_text ON clip_content BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, search_text) VALUES ('delete', old.seq, \(oldText));
                DELETE FROM clip_word WHERE rowid = old.seq;
                INSERT INTO clip_fts(rowid, search_text) VALUES (new.seq, \(newText));
                INSERT INTO clip_word(rowid, body) VALUES (new.seq, clipnote_segment(\(newText)));
            END;
            CREATE TRIGGER item_ad AFTER DELETE ON clip_item BEGIN
                DELETE FROM clip_content WHERE seq = old.seq;
            END;

            CREATE TABLE source_app (
                bundle_id TEXT PRIMARY KEY,
                name TEXT,
                item_count INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO source_app (bundle_id, name, item_count)
                SELECT source_bundle_id, MAX(source_app_name), COUNT(*) FROM clip_item
                WHERE source_bundle_id IS NOT NULL GROUP BY source_bundle_id;
            CREATE TRIGGER source_ai AFTER INSERT ON clip_item WHEN new.source_bundle_id IS NOT NULL BEGIN
                INSERT INTO source_app (bundle_id, name, item_count) VALUES (new.source_bundle_id, new.source_app_name, 1)
                ON CONFLICT(bundle_id) DO UPDATE SET item_count = item_count + 1, name = COALESCE(excluded.name, name);
            END;
            CREATE TRIGGER source_ad AFTER DELETE ON clip_item WHEN old.source_bundle_id IS NOT NULL BEGIN
                UPDATE source_app SET item_count = item_count - 1 WHERE bundle_id = old.source_bundle_id;
            END;
            CREATE TRIGGER source_au AFTER UPDATE OF source_bundle_id ON clip_item
            WHEN old.source_bundle_id IS NOT new.source_bundle_id BEGIN
                UPDATE source_app SET item_count = item_count - 1 WHERE bundle_id = old.source_bundle_id;
                INSERT INTO source_app (bundle_id, name, item_count)
                    SELECT new.source_bundle_id, new.source_app_name, 1 WHERE new.source_bundle_id IS NOT NULL
                ON CONFLICT(bundle_id) DO UPDATE SET item_count = item_count + 1, name = COALESCE(excluded.name, name);
            END;
            """)
    }

    /// v3：同步支持（分类与固定时间戳、待同步变更、删除记录、同步状态）
    static let v3Schema = """
        ALTER TABLE clip_item ADD COLUMN pinned_at REAL NOT NULL DEFAULT 0;
        ALTER TABLE pinboard ADD COLUMN updated_at REAL NOT NULL DEFAULT 0;
        CREATE TABLE sync_outbox (
            key TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            at REAL NOT NULL
        );
        CREATE TABLE sync_tombstone (
            key TEXT PRIMARY KEY,
            deleted_at REAL NOT NULL
        );
        CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """

    /// v4：卡片自定义标题
    static let v4Schema = """
        ALTER TABLE clip_item ADD COLUMN title TEXT;
        ALTER TABLE clip_item ADD COLUMN title_at REAL NOT NULL DEFAULT 0;
        CREATE INDEX idx_clip_title ON clip_item(title) WHERE title IS NOT NULL;
        """

    /// v5：暂存「条目尚未到达」的远端元数据（来自其他设备的修改先于正文到达时）
    static let v5Schema = """
        CREATE TABLE sync_orphan (
            hash TEXT PRIMARY KEY,
            op TEXT NOT NULL,
            received_at REAL NOT NULL
        );
        """

    /// v6：图片文字识别状态（0 未识别，1 已识别，2 无法识别），用于后台补充识别与断点续传。
    /// 已有可搜索文字的图片视为已识别。
    static let v6Schema = """
        ALTER TABLE clip_item ADD COLUMN ocr_state INTEGER NOT NULL DEFAULT 0;
        UPDATE clip_item SET ocr_state = 1
            WHERE type = 'image' AND seq IN (SELECT seq FROM clip_content WHERE COALESCE(search_text, '') <> '');
        CREATE INDEX idx_clip_ocr_pending ON clip_item(seq) WHERE type = 'image' AND ocr_state = 0;
        """

    static let migrations: [(SQLiteDatabase) throws -> Void] = [
        { try $0.execute(v1Schema) },
        migrateToV2,
        { try $0.execute(v3Schema) },
        { try $0.execute(v4Schema) },
        { try $0.execute(v5Schema) },
        { try $0.execute(v6Schema) },
    ]

    static func migrate(_ db: SQLiteDatabase) throws {
        let current = Int(try db.query("PRAGMA user_version") { $0.int(0) }.first ?? 0)
        guard current < migrations.count else { return }
        for version in current..<migrations.count {
            try db.transaction {
                try migrations[version](db)
                try db.execute("PRAGMA user_version = \(version + 1)")
            }
        }
        // v2 的结构迁移（删列重写表）会留下大量空闲页，回收空间
        if current > 0 && current < 2 { try db.execute("VACUUM") }
    }
}
