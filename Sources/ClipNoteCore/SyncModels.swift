import Foundation

/// 同步变更记录。每台设备把自己的变更写成一批批 JSON Lines 文件，其他设备按顺序读取并合并。
///
/// 合并规则（与顺序无关、可重复应用）：
/// - 条目以内容哈希识别；最近使用时间取较新者，使用次数取较大者，创建时间取较早者；
/// - 所属分类以 pinnedAt 较新者为准；
/// - 删除留下删除记录（tombstone），晚于删除时间的更新才能让条目重新出现；
/// - 分类以名称识别，属性以 at 较新者为准。
public struct SyncOp: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 完整条目（含正文与文件引用）
        case item
        /// 仅元数据（使用时间、次数、分类、OCR 文本），本地没有该条目时忽略
        case meta
        case delete
        case board
        case boardDelete
    }

    public var op: Kind
    public var at: Double
    public var hash: String?

    // 条目
    public var type: String?
    public var content: String?
    /// 与正文不同时才携带（如图片 OCR 文本）
    public var searchText: String?
    /// 图片文件在同步存储中的键
    public var file: String?
    /// 富文本原始数据在同步存储中的键
    public var dataFile: String?
    public var dataType: String?
    /// 文件所在批次（该批次的 zip 中包含此文件）
    public var fileSeg: Int?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var charCount: Int?
    public var width: Int?
    public var height: Int?
    public var createdAt: Double?
    public var updatedAt: Double?
    public var useCount: Int?
    public var pinboard: String?
    public var pinnedAt: Double?
    public var tags: String?
    public var aiSummary: String?
    /// 自定义标题（空字符串表示恢复默认标题）及其修改时间
    public var title: String?
    public var titledAt: Double?

    // 分类
    public var name: String?
    public var color: String?
    public var sortOrder: Int?

    public init(op: Kind, at: Double) {
        self.op = op
        self.at = at
    }
}

/// 应用远端变更的统计
public struct SyncApplyStats: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var deleted = 0
    public var missingFiles = 0

    public init() {}

    public static func + (a: SyncApplyStats, b: SyncApplyStats) -> SyncApplyStats {
        var r = a
        r.inserted += b.inserted
        r.updated += b.updated
        r.deleted += b.deleted
        r.missingFiles += b.missingFiles
        return r
    }
}

/// 待上传的本地变更
public struct SyncChange: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case upsert, meta, delete, board, boardDelete
    }

    public var key: String
    public var kind: Kind
    public var at: Double
}
