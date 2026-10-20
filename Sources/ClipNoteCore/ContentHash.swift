import CryptoKit
import Foundation

public enum ContentHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    /// 文本类条目（纯文本、富文本）共用同一前缀，使同一段文字不论以何种格式复制都只保留一条
    public static func forText(_ text: String) -> String { sha256("t:" + text) }
    public static func forLink(_ url: String) -> String { sha256("l:" + url) }
    public static func forFiles(_ paths: [String]) -> String { sha256("f:" + paths.joined(separator: "\n")) }
    public static func forImage(_ data: Data) -> String { "i:" + sha256(data) }
}
