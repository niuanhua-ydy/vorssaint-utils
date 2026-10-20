import Foundation

/// 文本清洗工具（P1：去格式、去多余空行、合并为一行）
public enum TextCleaner {
    /// 去掉每行行尾空白，并把连续多个空行压缩为一个空行
    public static func collapseBlankLines(_ text: String) -> String {
        var result: [String] = []
        var previousBlank = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = trimTrailing(line)
            let isBlank = trimmed.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousBlank && !result.isEmpty { result.append("") }
                previousBlank = true
            } else {
                result.append(trimmed)
                previousBlank = false
            }
        }
        while result.last == "" { result.removeLast() }
        return result.joined(separator: "\n")
    }

    /// 合并为一行：中文之间直接拼接，其他情况用空格连接
    public static func joinLines(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = ""
        for line in lines {
            if let last = result.last, let first = line.first, !(isCJK(last) && isCJK(first)) {
                result += " "
            }
            result += line
        }
        return result
    }

    /// 去除首尾空白
    public static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimTrailing(_ line: String) -> String {
        var s = Substring(line)
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return String(s)
    }

    static func isCJK(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3000...0x303F, 0xFF00...0xFFEF, 0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
