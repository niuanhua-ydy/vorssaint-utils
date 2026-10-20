import Foundation

/// 搜索查询计划。
///
/// 使用两套 FTS5 索引：
/// - `clip_fts`（trigram）：≥3 个字符的词做子串匹配，中英文通用，并提供 bm25 相关度。
/// - `clip_word`（unicode61 + 预切分）：1～2 个字符的短词。中文按相邻二字切分（外加每段末字），
///   因此两字词精确命中、单字前缀命中；英文按单词前缀命中。
/// 两类都无法覆盖的少见短词（如 `c#`、中英混合两字）退化为对候选行的 LIKE 过滤。
public struct SearchQuery {
    public let terms: [String]
    public let trigramTerms: [String]
    public let wordTerms: [String]
    public let likeTerms: [String]

    public init(_ text: String) {
        terms = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var trigram: [String] = [], word: [String] = [], like: [String] = []
        for term in terms {
            let scalars = Array(term.unicodeScalars)
            if scalars.count >= 3 {
                trigram.append(term)
            } else if scalars.allSatisfy({ Segmenter.isCJK($0.value) }) {
                word.append(term)
            } else if scalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }) {
                word.append(term.lowercased())
            } else {
                like.append(term)
            }
        }
        trigramTerms = trigram
        wordTerms = word
        likeTerms = like
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// 每个词作为短语加引号，空格分隔即 AND
    public var trigramExpression: String? {
        trigramTerms.isEmpty ? nil : trigramTerms.map(Self.quote).joined(separator: " ")
    }

    /// 两字中文词精确匹配，其余（单字、英文短词）前缀匹配
    public var wordExpression: String? {
        guard !wordTerms.isEmpty else { return nil }
        return wordTerms.map { term in
            let isCJKPair = term.unicodeScalars.count == 2 && term.unicodeScalars.allSatisfy { Segmenter.isCJK($0.value) }
            return isCJKPair ? Self.quote(term) : Self.quote(term) + "*"
        }.joined(separator: " ")
    }

    static func quote(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func likePattern(_ term: String) -> String {
        let escaped = term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}

/// 为短词索引预切分文本：中文连续段落输出相邻二字组 + 末字，其余字符原样保留交给 unicode61 分词。
/// 例："部署docker服务器" → " 部署 署 docker 服务 务器 器 "
public enum Segmenter {
    public static func isCJK(_ v: UInt32) -> Bool {
        switch v {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF, // 汉字
             0x3040...0x30FF, // 假名
             0xAC00...0xD7AF: // 韩文
            return true
        default:
            return false
        }
    }

    public static func segment(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var run: [Unicode.Scalar] = []
        let space: Unicode.Scalar = " "

        func flush() {
            guard let last = run.last else { return }
            out.append(space)
            for i in 0..<(run.count - 1) {
                out.append(run[i])
                out.append(run[i + 1])
                out.append(space)
            }
            out.append(last)
            out.append(space)
            run.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if isCJK(scalar.value) {
                run.append(scalar)
            } else {
                flush()
                out.append(scalar)
            }
        }
        flush()
        return String(out)
    }
}

public enum Snippet {
    /// 围绕第一个命中位置截取摘要；无命中时返回开头部分。
    public static func make(_ text: String, terms: [String], maxLength: Int = 400, leading: Int = 24) -> String {
        let hits = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
        guard let first = hits.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return String(text.prefix(maxLength))
        }
        var start = text.index(first.lowerBound, offsetBy: -leading, limitedBy: text.startIndex) ?? text.startIndex
        // 如果窗口内有换行，从换行之后开始，让摘要更整齐
        if let newline = text[start..<first.lowerBound].lastIndex(of: "\n") {
            start = text.index(after: newline)
        }
        let body = String(text[start...].prefix(maxLength))
        return start > text.startIndex ? "…" + body : body
    }
}
