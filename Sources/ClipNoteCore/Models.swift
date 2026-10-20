import Foundation

public enum ClipType: String, CaseIterable, Sendable {
    case text
    case rich
    case link
    case image
    case file

    public var displayName: String {
        switch self {
        case .text: return "文本"
        case .rich: return "富文本"
        case .link: return "链接"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    /// 是否有可用的纯文本表示
    public var isTextual: Bool {
        self == .text || self == .rich || self == .link
    }
}

public struct ClipItem: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var type: ClipType
    /// text/rich: 纯文本；link: URL；image: 相对图片路径；file: 换行分隔的文件路径。
    /// 列表 / 搜索结果中文本条目只含预览或命中摘要，完整内容用 ClipStore.item(id:) 读取。
    public var content: String
    /// 富文本原始数据文件（相对路径）
    public var dataPath: String?
    /// dataPath 对应的 pasteboard 类型（public.rtf / public.html）
    public var dataType: String?
    public var searchText: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var charCount: Int
    public var width: Int
    public var height: Int
    public var hash: String
    public var createdAt: Date
    public var updatedAt: Date
    public var useCount: Int
    public var pinboardID: Int64?
    // AI 扩展字段（Phase 3 使用）
    public var tags: String?
    public var aiSummary: String?
    /// 用户自定义标题；为空时显示类型名称
    public var title: String? = nil

    public var displayTitle: String { title ?? type.displayName }

    public var filePaths: [String] {
        type == .file ? content.split(separator: "\n").map(String.init) : []
    }
}

/// 待写入的新条目
public struct NewClip: Sendable {
    public var type: ClipType
    public var content: String
    public var dataPath: String?
    public var dataType: String?
    public var searchText: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var charCount: Int
    public var width: Int
    public var height: Int
    public var hash: String

    public init(type: ClipType, content: String, dataPath: String? = nil, dataType: String? = nil,
                searchText: String, sourceBundleID: String? = nil, sourceAppName: String? = nil,
                charCount: Int = 0, width: Int = 0, height: Int = 0, hash: String) {
        self.type = type
        self.content = content
        self.dataPath = dataPath
        self.dataType = dataType
        self.searchText = searchText
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.charCount = charCount
        self.width = width
        self.height = height
        self.hash = hash
    }
}

public struct Pinboard: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    /// 十六进制颜色，如 #FF9F0A
    public var color: String
    public var sortOrder: Int

    public static let presetColors = [
        "#FF5F57", "#FF9F0A", "#FFD60A", "#30D158", "#64D2FF",
        "#0A84FF", "#BF5AF2", "#FF375F", "#8E8E93",
    ]
}

public struct SourceApp: Hashable, Sendable {
    public var bundleID: String
    public var name: String
}

public struct ClipQuery: Sendable {
    public enum Scope: Hashable, Sendable {
        case all
        case pinboard(Int64)
    }

    public var text: String
    public var scope: Scope
    public var type: ClipType?
    public var sourceBundleID: String?
    public var limit: Int
    public var offset: Int

    public init(text: String = "", scope: Scope = .all, type: ClipType? = nil,
                sourceBundleID: String? = nil, limit: Int = 200, offset: Int = 0) {
        self.text = text
        self.scope = scope
        self.type = type
        self.sourceBundleID = sourceBundleID
        self.limit = limit
        self.offset = offset
    }
}

/// 从备份导入的条目
public struct ImportedClip: Sendable {
    public var clip: NewClip
    public var createdAt: Date
    public var updatedAt: Date
    public var useCount: Int
    public var pinboardID: Int64?
    public var tags: String?
    public var aiSummary: String?
    public var title: String?
    /// 标题的修改时间（同步合并用），为 0 时取 updatedAt
    public var titledAt: Double

    public init(clip: NewClip, createdAt: Date, updatedAt: Date, useCount: Int = 0, pinboardID: Int64? = nil,
                tags: String? = nil, aiSummary: String? = nil, title: String? = nil, titledAt: Double = 0) {
        self.clip = clip
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.pinboardID = pinboardID
        self.tags = tags
        self.aiSummary = aiSummary
        self.title = title
        self.titledAt = titledAt
    }
}
