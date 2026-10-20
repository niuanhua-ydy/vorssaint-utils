import Foundation

/// 同步相关的存储操作：记录本地变更、生成上传记录与快照、合并远端变更。
extension ClipStore {
    /// 正在记录且不是在应用远端变更
    var isSyncRecordingActive: Bool { isSyncRecording && !applyingRemote }

    // MARK: - 记录本地变更（需在写队列内调用）

    /// 记录待同步变更。同一个键只保留一条：upsert 优先于 meta，删除覆盖之前的记录。
    func recordSyncChangeLocked(key: String, kind: SyncChange.Kind, at: Double = Date().timeIntervalSince1970) throws {
        guard isSyncRecordingActive else { return }
        try db.run("""
            INSERT INTO sync_outbox (key, kind, at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                kind = CASE WHEN excluded.kind = 'meta' AND sync_outbox.kind = 'upsert' THEN 'upsert' ELSE excluded.kind END,
                at = excluded.at
            """, [.text(key), .text(kind.rawValue), .double(at)])
    }

    func recordItemChangeLocked(where condition: String, _ params: [SQLValue], kind: SyncChange.Kind) throws {
        guard isSyncRecordingActive else { return }
        let hashes = try db.query("SELECT hash FROM clip_item WHERE \(condition)", params) { $0.text(0) }
        for hash in hashes {
            try recordSyncChangeLocked(key: "item:" + hash, kind: kind)
        }
    }

    // MARK: - 同步状态

    public func syncMeta(_ key: String) -> String? {
        read { db in (try? db.query("SELECT value FROM sync_meta WHERE key = ?", [.text(key)]) { $0.text(0) })?.first }
    }

    public func setSyncMeta(_ key: String, _ value: String?) {
        _ = try? mutate {
            if let value {
                try db.run("INSERT INTO sync_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           [.text(key), .text(value)])
            } else {
                try db.run("DELETE FROM sync_meta WHERE key = ?", [.text(key)])
            }
        }
    }

    /// 切换同步目标（账号、目录）时重置进度：保留设备 ID 与删除记录，清空待上传变更（之后会重新上传全量快照）
    public func resetSyncProgress() {
        _ = try? mutate {
            try db.run("DELETE FROM sync_meta WHERE key <> 'deviceID'")
            try db.run("DELETE FROM sync_outbox")
        }
    }

    // MARK: - 上传

    public func pendingSyncChanges(limit: Int = 2000) -> [SyncChange] {
        read { db in
            (try? db.query("SELECT key, kind, at FROM sync_outbox ORDER BY at LIMIT ?", [.int(Int64(limit))]) { row in
                SyncChange(key: row.text(0), kind: SyncChange.Kind(rawValue: row.text(1)) ?? .meta, at: row.double(2))
            }) ?? []
        }
    }

    public var pendingSyncChangeCount: Int {
        read { db in Int((try? db.query("SELECT COUNT(*) FROM sync_outbox") { $0.int(0) })?.first ?? 0) }
    }

    /// 上传成功后移除；期间又有新变更（at 变化）的保留
    public func markSyncChangesUploaded(_ changes: [SyncChange]) {
        _ = try? mutate {
            for change in changes {
                try db.run("DELETE FROM sync_outbox WHERE key = ? AND at = ?", [.text(change.key), .double(change.at)])
            }
        }
    }

    /// 把待同步变更转换为上传记录。
    /// - Returns: ops、需随批次上传的文件（同步键 → 本地路径）、实际处理的变更数（文件总大小超过 maxBatchFileBytes 时提前截断）
    public func buildSyncOps(for changes: [SyncChange], includeImages: Bool, maxFileBytes: Int,
                             maxBatchFileBytes: Int) -> (ops: [SyncOp], files: [String: URL], consumed: Int) {
        let itemHashes = changes.filter { ($0.kind == .upsert || $0.kind == .meta) && $0.key.hasPrefix("item:") }
            .map { String($0.key.dropFirst(5)) }
        let rows = itemRows(hashes: itemHashes)
        let boards = Dictionary(pinboardRows().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        var boardOps: [SyncOp] = [], itemOps: [SyncOp] = [], deleteOps: [SyncOp] = [], boardDeleteOps: [SyncOp] = []
        var files: [String: URL] = [:]
        var batchBytes = 0
        var consumed = 0
        for change in changes {
            let name = String(change.key.drop(while: { $0 != ":" }).dropFirst())
            switch change.kind {
            case .board:
                if let board = boards[name] {
                    var op = SyncOp(op: .board, at: board.updatedAt)
                    op.name = name
                    op.color = board.color
                    op.sortOrder = board.sortOrder
                    boardOps.append(op)
                }
            case .boardDelete:
                var op = SyncOp(op: .boardDelete, at: change.at)
                op.name = name
                boardDeleteOps.append(op)
            case .delete:
                var op = SyncOp(op: .delete, at: change.at)
                op.hash = name
                deleteOps.append(op)
            case .upsert, .meta:
                guard let row = rows[name] else { break } // 已被删除，之后的 delete 变更会处理
                if row.item.type == .image && !includeImages { break }
                if change.kind == .upsert {
                    let (op, itemFiles) = makeItemOp(row, maxFileBytes: maxFileBytes)
                    guard op.op == .item else { break }
                    let bytes = itemFiles.values.reduce(0) { $0 + Self.fileSize($1) }
                    if batchBytes > 0 && batchBytes + bytes > maxBatchFileBytes { return finish() }
                    batchBytes += bytes
                    files.merge(itemFiles) { a, _ in a }
                    itemOps.append(op)
                } else {
                    itemOps.append(makeMetaOp(row))
                }
            }
            consumed += 1
        }
        return finish()

        func finish() -> (ops: [SyncOp], files: [String: URL], consumed: Int) {
            (boardOps + itemOps + deleteOps + boardDeleteOps, files, consumed)
        }
    }

    /// 全量快照的一批：第一批（cursor 为 nil）包含分类与删除记录，之后按时间顺序分批输出条目。
    /// - Returns: 下一批的游标（nil 表示结束）
    public func syncSnapshotBatch(after cursor: Int64?, includeImages: Bool, maxFileBytes: Int, batchSize: Int = 1000,
                                  maxBatchFileBytes: Int) -> (ops: [SyncOp], files: [String: URL], next: Int64?) {
        var ops: [SyncOp] = []
        if cursor == nil {
            for board in pinboardRows() {
                var op = SyncOp(op: .board, at: board.updatedAt)
                op.name = board.name
                op.color = board.color
                op.sortOrder = board.sortOrder
                ops.append(op)
            }
            let tombstones = read { db in
                (try? db.query("SELECT key, deleted_at FROM sync_tombstone") { ($0.text(0), $0.double(1)) }) ?? []
            }
            for (key, at) in tombstones {
                let value = String(key.drop(while: { $0 != ":" }).dropFirst())
                var op = SyncOp(op: key.hasPrefix("board:") ? .boardDelete : .delete, at: at)
                if key.hasPrefix("board:") { op.name = value } else { op.hash = value }
                ops.append(op)
            }
        }
        let rows = read { db in
            (try? db.query("""
                SELECT \(Self.columns), cc.content, COALESCE(cc.search_text, substr(cc.content, 1, \(Self.searchTextLimit))),
                       p.name, c.pinned_at, c.title_at
                FROM clip_item c JOIN clip_content cc ON cc.seq = c.seq LEFT JOIN pinboard p ON p.id = c.pinboard_id
                WHERE c.seq > ? ORDER BY c.seq LIMIT ?
                """, [.int(cursor ?? -1), .int(Int64(batchSize))]) { row in
                (row.int(Self.seqColumn), Self.mapSyncRow(row))
            }) ?? []
        }
        var files: [String: URL] = [:]
        var batchBytes = 0
        var lastSeq: Int64?
        for (seq, row) in rows {
            if row.item.type == .image && !includeImages {
                lastSeq = seq
                continue
            }
            let (op, itemFiles) = makeItemOp(row, maxFileBytes: maxFileBytes)
            let bytes = itemFiles.values.reduce(0) { $0 + Self.fileSize($1) }
            if batchBytes > 0 && batchBytes + bytes > maxBatchFileBytes { break }
            batchBytes += bytes
            lastSeq = seq
            if op.op == .item {
                files.merge(itemFiles) { a, _ in a }
                ops.append(op)
            }
        }
        let next: Int64? = rows.isEmpty ? nil : (lastSeq ?? cursor)
        return (ops, files, next)
    }

    struct SyncRow {
        var item: ClipItem
        var pinboardName: String?
        var pinnedAt: Double
        var titledAt: Double
    }

    static func mapSyncRow(_ row: SQLiteDatabase.Row) -> SyncRow {
        let base = Int32(columnNames.count) + 2
        return SyncRow(item: mapItem(row, full: true), pinboardName: row.optionalText(base), pinnedAt: row.double(base + 1),
                       titledAt: row.double(base + 2))
    }

    private func itemRows(hashes: [String]) -> [String: SyncRow] {
        guard !hashes.isEmpty else { return [:] }
        var result: [String: SyncRow] = [:]
        for chunk in stride(from: 0, to: hashes.count, by: 500).map({ Array(hashes[$0..<min($0 + 500, hashes.count)]) }) {
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
            let rows = read { db in
                (try? db.query("""
                    SELECT \(Self.columns), cc.content, COALESCE(cc.search_text, substr(cc.content, 1, \(Self.searchTextLimit))),
                           p.name, c.pinned_at, c.title_at
                    FROM clip_item c JOIN clip_content cc ON cc.seq = c.seq LEFT JOIN pinboard p ON p.id = c.pinboard_id
                    WHERE c.hash IN (\(placeholders))
                    """, chunk.map { .text($0) }, map: Self.mapSyncRow)) ?? []
            }
            for row in rows { result[row.item.hash] = row }
        }
        return result
    }

    private struct BoardRow {
        var id: Int64
        var name: String
        var color: String
        var sortOrder: Int
        var updatedAt: Double
    }

    private func pinboardRows() -> [BoardRow] {
        read { db in
            (try? db.query("SELECT id, name, color, sort_order, updated_at FROM pinboard") {
                BoardRow(id: $0.int(0), name: $0.text(1), color: $0.text(2), sortOrder: Int($0.int(3)), updatedAt: $0.double(4))
            }) ?? []
        }
    }

    /// 同步存储中的文件键：由条目哈希决定，各设备一致
    static func syncFileKey(hash: String, prefix: String, path: String) -> String {
        let ext = (path as NSString).pathExtension
        return "\(prefix)-\(ContentHash.sha256(hash).prefix(32))" + (ext.isEmpty ? "" : ".\(ext)")
    }

    static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    /// maxFileBytes：单条内容（文字、图片、格式数据）的同步上限，超过的条目只保留在本机
    private func makeItemOp(_ row: SyncRow, maxFileBytes: Int) -> (SyncOp, [String: URL]) {
        let item = row.item
        let skipped = (SyncOp(op: .meta, at: 0), [String: URL]())
        if item.type != .image && item.content.utf8.count > maxFileBytes { return skipped }
        var op = SyncOp(op: .item, at: item.updatedAt.timeIntervalSince1970)
        op.hash = item.hash
        op.type = item.type.rawValue
        op.content = item.content
        if item.searchText != String(item.content.prefix(Self.searchTextLimit)) { op.searchText = item.searchText }
        op.sourceBundleID = item.sourceBundleID
        op.sourceAppName = item.sourceAppName
        op.charCount = item.charCount
        op.width = item.width
        op.height = item.height
        op.createdAt = item.createdAt.timeIntervalSince1970
        op.updatedAt = item.updatedAt.timeIntervalSince1970
        op.useCount = item.useCount
        op.pinboard = row.pinboardName
        op.pinnedAt = row.pinnedAt
        op.tags = item.tags
        op.aiSummary = item.aiSummary
        if row.titledAt > 0 {
            op.title = item.title ?? ""
            op.titledAt = row.titledAt
        }

        var files: [String: URL] = [:]
        if item.type == .image {
            let url = self.url(forRelativePath: item.content)
            let size = Self.fileSize(url)
            // 图片文件缺失或过大时不同步该条目
            guard size > 0, size <= maxFileBytes else { return skipped }
            let key = Self.syncFileKey(hash: item.hash, prefix: "f", path: item.content)
            op.file = key
            op.content = nil
            files[key] = url
        }
        if let dataPath = item.dataPath, let type = item.dataType {
            let url = self.url(forRelativePath: dataPath)
            let size = Self.fileSize(url)
            // 格式数据过大时只同步纯文字（对方得到的是纯文本条目）
            if size > 0 && size <= maxFileBytes {
                let key = Self.syncFileKey(hash: item.hash, prefix: "d", path: dataPath)
                op.dataFile = key
                op.dataType = type
                files[key] = url
            }
        }
        return (op, files)
    }

    private func makeMetaOp(_ row: SyncRow) -> SyncOp {
        var op = SyncOp(op: .meta, at: row.item.updatedAt.timeIntervalSince1970)
        op.hash = row.item.hash
        op.updatedAt = row.item.updatedAt.timeIntervalSince1970
        op.useCount = row.item.useCount
        op.pinboard = row.pinboardName
        op.pinnedAt = row.pinnedAt
        if row.titledAt > 0 {
            op.title = row.item.title ?? ""
            op.titledAt = row.titledAt
        }
        if row.item.type == .image, !row.item.searchText.isEmpty { op.searchText = row.item.searchText }
        return op
    }

    // MARK: - 合并远端变更

    /// 需要下载文件的条目：本地还没有、且带文件引用
    public func needsFiles(for op: SyncOp) -> Bool {
        guard op.op == .item, op.file != nil || op.dataFile != nil, let hash = op.hash else { return false }
        return !contains(hash: hash)
    }

    /// 应用远端变更。files：同步键 → 已下载到本地的临时文件。
    @discardableResult
    public func applySyncOps(_ ops: [SyncOp], files: [String: URL]) throws -> SyncApplyStats {
        var removed: [String] = []
        let stats: SyncApplyStats = try mutate {
            applyingRemote = true
            defer { applyingRemote = false }
            var stats = SyncApplyStats()
            for op in ops {
                try applyLocked(op, files: files, stats: &stats, removedFiles: &removed)
            }
            try flushStageLocked()
            // 等了 30 天仍未到达的条目，其暂存元数据不再保留
            try db.run("DELETE FROM sync_orphan WHERE received_at < ?", [.double(Date().timeIntervalSince1970 - 30 * 86400)])
            return stats
        }
        removeFiles(removed)
        if stats != SyncApplyStats() { notifyChange() }
        return stats
    }

    /// 暂存本地尚不存在的条目的元数据；同一条目的多次修改先合并（各字段取较新者）
    private func storeOrphanLocked(_ op: SyncOp) throws {
        guard let hash = op.hash else { return }
        var merged = op
        if let json = try db.query("SELECT op FROM sync_orphan WHERE hash = ?", [.text(hash)], map: { $0.text(0) }).first,
           let existing = try? JSONDecoder().decode(SyncOp.self, from: Data(json.utf8)) {
            merged = SyncEngine.reduce([existing, op]).first ?? op
        }
        let data = try JSONEncoder().encode(merged)
        try db.run("""
            INSERT INTO sync_orphan (hash, op, received_at) VALUES (?, ?, ?)
            ON CONFLICT(hash) DO UPDATE SET op = excluded.op, received_at = excluded.received_at
            """, [.text(hash), .text(String(decoding: data, as: UTF8.self)), .double(Date().timeIntervalSince1970)])
    }

    /// 取出并删除暂存的元数据
    private func takeOrphanLocked(_ hash: String) throws -> SyncOp? {
        guard let json = try db.query("SELECT op FROM sync_orphan WHERE hash = ?", [.text(hash)], map: { $0.text(0) }).first else {
            return nil
        }
        try db.run("DELETE FROM sync_orphan WHERE hash = ?", [.text(hash)])
        return try? JSONDecoder().decode(SyncOp.self, from: Data(json.utf8))
    }

    private func tombstoneLocked(_ key: String) throws -> Double {
        try db.query("SELECT deleted_at FROM sync_tombstone WHERE key = ?", [.text(key)]) { $0.double(0) }.first ?? -.infinity
    }

    private func addTombstoneLocked(_ key: String, at: Double) throws {
        try db.run("""
            INSERT INTO sync_tombstone (key, deleted_at) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET deleted_at = max(deleted_at, excluded.deleted_at)
            """, [.text(key), .double(at)])
    }

    /// 按名称找分类，不存在则创建（属性时间戳为 0，之后的分类记录会覆盖颜色等属性）
    private func boardIDLocked(named name: String, at: Double) throws -> Int64? {
        if let id = try db.query("SELECT id FROM pinboard WHERE name = ? ORDER BY id LIMIT 1", [.text(name)], map: { $0.int(0) }).first {
            return id
        }
        guard try tombstoneLocked("board:" + name) < at else { return nil }
        let order = try db.query("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM pinboard") { $0.int(0) }.first ?? 1
        try db.run("INSERT INTO pinboard (name, color, sort_order, updated_at) VALUES (?, '#8E8E93', ?, 0)",
                   [.text(name), .int(order)])
        return db.lastInsertRowID
    }

    private func applyLocked(_ op: SyncOp, files: [String: URL], stats: inout SyncApplyStats,
                             removedFiles: inout [String]) throws {
        switch op.op {
        case .board:
            guard let name = op.name, try tombstoneLocked("board:" + name) < op.at else { return }
            if let local = try db.query("SELECT id, updated_at FROM pinboard WHERE name = ? ORDER BY id LIMIT 1", [.text(name)],
                                        map: { ($0.int(0), $0.double(1)) }).first {
                if op.at > local.1 {
                    try db.run("UPDATE pinboard SET color = COALESCE(?, color), sort_order = COALESCE(?, sort_order), updated_at = ? WHERE id = ?",
                               [op.color.map { .text($0) } ?? .null, op.sortOrder.map { .int(Int64($0)) } ?? .null,
                                .double(op.at), .int(local.0)])
                    stats.updated += 1
                }
            } else {
                let order = try db.query("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM pinboard") { $0.int(0) }.first ?? 1
                try db.run("INSERT INTO pinboard (name, color, sort_order, updated_at) VALUES (?, ?, ?, ?)",
                           [.text(name), .text(op.color ?? "#8E8E93"), .int(Int64(op.sortOrder ?? Int(order))), .double(op.at)])
                stats.inserted += 1
            }

        case .boardDelete:
            guard let name = op.name else { return }
            try addTombstoneLocked("board:" + name, at: op.at)
            let local = try db.query("SELECT id, updated_at FROM pinboard WHERE name = ?", [.text(name)]) { ($0.int(0), $0.double(1)) }
            for (id, updatedAt) in local where updatedAt <= op.at {
                try db.run("DELETE FROM pinboard WHERE id = ?", [.int(id)])
                stats.deleted += 1
            }

        case .delete:
            guard let hash = op.hash else { return }
            try addTombstoneLocked("item:" + hash, at: op.at)
            if let local = try db.query("SELECT id, updated_at FROM clip_item WHERE hash = ?", [.text(hash)],
                                        map: { ($0.int(0), $0.double(1)) }).first, local.1 <= op.at {
                removedFiles += try deleteLocked("id = ?", [.int(local.0)], recordSync: false, at: op.at)
                stats.deleted += 1
            }

        case .item, .meta:
            guard let hash = op.hash else { return }
            let updatedAt = op.updatedAt ?? op.at
            if let local = try db.query("""
                SELECT c.id, c.updated_at, c.use_count, c.pinned_at, c.created_at, c.type, c.title_at FROM clip_item c WHERE c.hash = ?
                """, [.text(hash)], map: { ($0.int(0), $0.double(1), Int($0.int(2)), $0.double(3), $0.double(4), $0.text(5), $0.double(6)) }).first {
                var changed = false
                if updatedAt > local.1 + 0.001 {
                    try renewLocked(where: "id = ?", [.int(local.0)], date: Date(timeIntervalSince1970: updatedAt))
                    changed = true
                }
                if let useCount = op.useCount, useCount > local.2 {
                    try db.run("UPDATE clip_item SET use_count = ? WHERE id = ?", [.int(Int64(useCount)), .int(local.0)])
                    changed = true
                }
                if let createdAt = op.createdAt, createdAt < local.4 {
                    try db.run("UPDATE clip_item SET created_at = ? WHERE id = ?", [.double(createdAt), .int(local.0)])
                }
                if let pinnedAt = op.pinnedAt, pinnedAt > local.3 {
                    let boardID = try op.pinboard.flatMap { try boardIDLocked(named: $0, at: pinnedAt) }
                    try db.run("UPDATE clip_item SET pinboard_id = ?, pinned_at = ? WHERE id = ?",
                               [boardID.map { .int($0) } ?? .null, .double(pinnedAt), .int(local.0)])
                    changed = true
                }
                if let titledAt = op.titledAt, titledAt > local.6 {
                    let title = op.title.flatMap { $0.isEmpty ? nil : $0 }
                    try db.run("UPDATE clip_item SET title = ?, title_at = ? WHERE id = ?",
                               [title.map { .text($0) } ?? .null, .double(titledAt), .int(local.0)])
                    changed = true
                }
                if local.5 == ClipType.image.rawValue, let text = op.searchText {
                    try db.run("""
                        UPDATE clip_content SET search_text = ?
                        WHERE seq = (SELECT seq FROM clip_item WHERE id = ?) AND COALESCE(search_text, '') <> ?
                        """, [.text(text), .int(local.0), .text(text)])
                    changed = changed || db.changes > 0
                    if !text.isEmpty {
                        try db.run("UPDATE clip_item SET ocr_state = ? WHERE id = ?", [.int(Int64(OCRState.done.rawValue)), .int(local.0)])
                    }
                }
                if changed { stats.updated += 1 }
                return
            }

            // 本地还没有这个条目：元数据先暂存，等正文从其他设备到达后再合并
            if op.op == .meta {
                try storeOrphanLocked(op)
                return
            }
            guard let typeRaw = op.type, let type = ClipType(rawValue: typeRaw),
                  try tombstoneLocked("item:" + hash) < updatedAt else { return }
            var content = op.content ?? ""
            var dataPath: String?
            if type == .image {
                guard let key = op.file, let source = files[key],
                      let copied = copyIntoStore(source, folder: "Images", key: key) else {
                    stats.missingFiles += 1
                    return
                }
                content = copied
            }
            if let key = op.dataFile, let source = files[key] {
                dataPath = copyIntoStore(source, folder: "Data", key: key)
            }
            let effectiveType: ClipType = type == .rich && dataPath == nil ? .text : type
            let boardID = try op.pinboard.flatMap { try boardIDLocked(named: $0, at: op.pinnedAt ?? updatedAt) }
            let clip = NewClip(type: effectiveType, content: content, dataPath: dataPath,
                               dataType: dataPath == nil ? nil : op.dataType,
                               searchText: op.searchText ?? (type == .image ? "" : content),
                               sourceBundleID: op.sourceBundleID, sourceAppName: op.sourceAppName,
                               charCount: op.charCount ?? content.count, width: op.width ?? 0, height: op.height ?? 0, hash: hash)
            let imported = ImportedClip(clip: clip, createdAt: Date(timeIntervalSince1970: op.createdAt ?? updatedAt),
                                        updatedAt: Date(timeIntervalSince1970: updatedAt), useCount: op.useCount ?? 0,
                                        pinboardID: boardID, tags: op.tags, aiSummary: op.aiSummary,
                                        title: op.title.flatMap { $0.isEmpty ? nil : $0 }, titledAt: op.titledAt ?? 0)
            try insertLocked(clip, date: imported.updatedAt, staged: true, imported: imported,
                             pinnedAt: boardID == nil ? 0 : (op.pinnedAt ?? updatedAt))
            stats.inserted += 1
            // 合并此前先于正文到达的修改
            if let orphan = try takeOrphanLocked(hash) {
                var ignored = SyncApplyStats()
                try applyLocked(orphan, files: files, stats: &ignored, removedFiles: &removedFiles)
            }
        }
    }

    private func copyIntoStore(_ source: URL, folder: String, key: String) -> String? {
        let ext = (key as NSString).pathExtension
        let relative = "\(folder)/\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: url(forRelativePath: relative))
            return relative
        } catch {
            return nil
        }
    }
}
