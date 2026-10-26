// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CryptoKit

/// One text tool: what finds it in the bar and what it can do to a piece of
/// text. The first operation is the default, so it is the direction people
/// reach for most (decoding, formatting).
struct CommandBarDeveloperTool: Identifiable {
    struct Operation: Identifiable {
        let id: String
        let name: String
        let chineseName: String
        let transform: (String) throws -> String
    }
    let id: String
    let name: String
    let chineseName: String
    /// The tool's name inside a matched row's title ("JSON · 格式化").
    let shortName: String
    let chineseShortName: String
    let symbol: String
    let keywords: String
    let operations: [Operation]

    var rowID: String { "action.devtool.\(id)" }

    func operation(_ id: String) -> Operation? { operations.first { $0.id == id } }
}

enum CommandBarDeveloperTools {
    static let maxInputBytes = 256 * 1024

    enum Failure: Error, Equatable {
        case tooLarge, outputTooLarge, invalidBase64, invalidUTF8, invalidURL, invalidEscape, invalidTimestamp, invalidJWT
        /// Foundation's own words for where the JSON broke ("around line 2, column 6").
        case invalidJSON(String)
    }

    /// A tool that already knows what to do with a piece of text: the row the
    /// bar offers for what was typed, selected or just copied.
    struct Match {
        let tool: CommandBarDeveloperTool
        let operation: CommandBarDeveloperTool.Operation
        let input: String
        let output: String
    }

    static let all: [CommandBarDeveloperTool] = [
        .init(id: "json", name: "JSON", chineseName: "JSON 工具", shortName: "JSON", chineseShortName: "JSON",
              symbol: "curlybraces",
              keywords: "json format pretty minify validate 格式化 压缩 校验", operations: [
                .init(id: "format", name: "Format", chineseName: "格式化") { try json($0, pretty: true) },
                .init(id: "minify", name: "Minify", chineseName: "压缩") { try json($0, pretty: false) },
              ]),
        .init(id: "base64", name: "Base64", chineseName: "Base64", shortName: "Base64", chineseShortName: "Base64",
              symbol: "textformat.abc",
              keywords: "base64 base64url encode decode 编码 解码", operations: [
                .init(id: "decode", name: "Decode", chineseName: "解码") { input in
                    guard let data = base64Data(input) else { throw Failure.invalidBase64 }
                    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidUTF8 }
                    return text
                },
                .init(id: "encode", name: "Encode", chineseName: "编码") { Data($0.utf8).base64EncodedString() },
                .init(id: "encodeURL", name: "Encode (URL-safe)", chineseName: "编码（URL 安全）") {
                    Data($0.utf8).base64EncodedString()
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: "=", with: "")
                },
              ]),
        .init(id: "url", name: "URL", chineseName: "URL 工具", shortName: "URL", chineseShortName: "URL",
              symbol: "link",
              keywords: "url percent uri encode decode query params 编码 解码 百分号 参数", operations: [
                .init(id: "decode", name: "Decode", chineseName: "解码") {
                    guard let value = $0.removingPercentEncoding else { throw Failure.invalidURL }
                    return value
                },
                .init(id: "encode", name: "Encode", chineseName: "编码") {
                    $0.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
                },
                .init(id: "parse", name: "Parse", chineseName: "解析参数") { try parseURL($0) },
              ]),
        .init(id: "unicode", name: "Unicode", chineseName: "Unicode 转义", shortName: "Unicode", chineseShortName: "Unicode",
              symbol: "character.cursor.ibeam",
              keywords: "unicode escape unescape utf \\u 转义 反转义 中文", operations: [
                .init(id: "unescape", name: "Unescape", chineseName: "还原") { try unescape($0) },
                .init(id: "escape", name: "Escape", chineseName: "转义") { escape($0) },
              ]),
        .init(id: "timestamp", name: "Timestamp", chineseName: "时间戳", shortName: "Timestamp", chineseShortName: "时间戳",
              symbol: "clock",
              keywords: "timestamp unix epoch time date 时间戳 时间 日期", operations: [
                .init(id: "convert", name: "Convert", chineseName: "转换") { try timestamp($0) },
              ]),
        .init(id: "jwt", name: "JWT", chineseName: "JWT 解析", shortName: "JWT", chineseShortName: "JWT",
              symbol: "key",
              keywords: "jwt token bearer decode 解析 令牌", operations: [
                .init(id: "decode", name: "Decode", chineseName: "解析") { try jwt($0) },
              ]),
        .init(id: "hash", name: "Hash", chineseName: "哈希", shortName: "Hash", chineseShortName: "哈希",
              symbol: "number",
              keywords: "hash digest sha256 sha1 sha512 md5 哈希 摘要", operations: [
                .init(id: "sha256", name: "SHA-256", chineseName: "SHA-256") { hex(SHA256.hash(data: Data($0.utf8))) },
                .init(id: "md5", name: "MD5", chineseName: "MD5") { hex(Insecure.MD5.hash(data: Data($0.utf8))) },
                .init(id: "sha1", name: "SHA-1", chineseName: "SHA-1") { hex(Insecure.SHA1.hash(data: Data($0.utf8))) },
                .init(id: "sha512", name: "SHA-512", chineseName: "SHA-512") { hex(SHA512.hash(data: Data($0.utf8))) },
              ]),
    ]

    static func tool(_ id: String) -> CommandBarDeveloperTool? { all.first { $0.id == id } }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.commandBarDeveloperToolsEnabled) as? Bool ?? true
    }

    static func run(_ operation: CommandBarDeveloperTool.Operation, input: String) throws -> String {
        guard input.utf8.count <= maxInputBytes else { throw Failure.tooLarge }
        return try operation.transform(input)
    }

    static func message(for error: Error, chinese: Bool) -> String {
        func label(_ en: String, _ zh: String) -> String { chinese ? zh : en }
        guard let failure = error as? Failure else { return error.localizedDescription }
        switch failure {
        case .tooLarge: return label("Input exceeds 256 KiB.", "输入超过 256 KiB。")
        case .outputTooLarge: return label("Formatted output exceeds 2 MiB; use Minify instead.", "格式化结果超过 2 MiB，请改用压缩。")
        case .invalidBase64: return label("Not valid Base64.", "不是有效的 Base64。")
        case .invalidUTF8: return label("Decoded bytes are not UTF-8 text.", "解码结果不是 UTF-8 文本。")
        case .invalidURL: return label("Invalid percent encoding or URL.", "百分号编码或 URL 无效。")
        case .invalidEscape: return label("Invalid escape sequence.", "转义序列无效。")
        case .invalidTimestamp: return label("Enter a Unix timestamp or a date like 2026-10-26 14:30:00.",
                                             "请输入 Unix 时间戳，或 2026-10-26 14:30:00 这样的日期。")
        case .invalidJWT: return label("Not a JWT (header.payload.signature).", "不是 JWT（header.payload.signature）。")
        case .invalidJSON(let detail): return label("Invalid JSON", "JSON 无效") + (detail.isEmpty ? "" : ": " + detail)
        }
    }

    // MARK: - Recognizing text

    /// The tools that know what to do with this text, most specific first.
    /// Only confident guesses: "test" is valid Base64 too, and a row that turns
    /// every search word into mojibake is worse than no row.
    static func matches(for text: String, limit: Int = 3) -> [Match] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxInputBytes else { return [] }
        var candidates: [(tool: String, operation: String)] = []
        if looksLikeJWT(trimmed) { candidates.append(("jwt", "decode")) }
        if let first = trimmed.first, first == "{" || first == "[" {
            candidates.append(("json", "format"))
            if trimmed.contains("\n") { candidates.append(("json", "minify")) }
        }
        if timestampDate(trimmed) != nil { candidates.append(("timestamp", "convert")) }
        if trimmed.range(of: #"\\u(\{[0-9a-fA-F]{1,6}\}|[0-9a-fA-F]{4})"#, options: .regularExpression) != nil {
            candidates.append(("unicode", "unescape"))
        }
        if let components = URLComponents(string: trimmed), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
           !(components.percentEncodedQuery ?? "").isEmpty {
            candidates.append(("url", "parse"))
        }
        if trimmed.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil {
            candidates.append(("url", "decode"))
        }
        if looksLikeBase64(trimmed) { candidates.append(("base64", "decode")) }

        var result: [Match] = []
        for candidate in candidates {
            guard let tool = tool(candidate.tool), let operation = tool.operation(candidate.operation),
                  let output = try? run(operation, input: trimmed),
                  !output.isEmpty, output != trimmed else { continue }
            result.append(Match(tool: tool, operation: operation, input: trimmed, output: output))
            if result.count >= limit { break }
        }
        return result
    }

    /// The operation to start a tool on: the one that recognizes the text,
    /// otherwise the tool's default.
    static func preferredOperation(of tool: CommandBarDeveloperTool, for text: String) -> CommandBarDeveloperTool.Operation {
        matches(for: text, limit: 8).first { $0.tool.id == tool.id }?.operation ?? tool.operations[0]
    }

    private static func looksLikeJWT(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].hasPrefix("eyJ"), parts[1].hasPrefix("eyJ") else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    private static func looksLikeBase64(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count >= 8,
              compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=-_".contains($0)) }),
              // A hex digest or a plain word is not Base64 anyone meant.
              !compact.allSatisfy(\.isHexDigit),
              compact.contains(where: { $0.isNumber || "+/=".contains($0) })
                || (compact.contains(where: \.isUppercase) && compact.contains(where: \.isLowercase)),
              let data = base64Data(compact), let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else { return false }
        return decoded.unicodeScalars.allSatisfy { scalar in
            if scalar == "\n" || scalar == "\t" || scalar == "\r" { return true }
            return scalar.value >= 0x20 && scalar.value != 0x7F && scalar != "\u{FFFD}"
                && !(0x80...0x9F).contains(scalar.value)
        }
    }

    // MARK: - Transforms

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Standard and URL-safe alphabets, with or without padding: JWT segments
    /// and most URL tokens drop the `=`.
    static func base64Data(_ input: String) -> Data? {
        var compact = String(input.unicodeScalars.filter { !$0.properties.isWhitespace })
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch compact.count % 4 {
        case 1: return nil
        case 2: compact += "=="
        case 3: compact += "="
        default: break
        }
        return Data(base64Encoded: compact)
    }

    private static func json(_ input: String, pretty: Bool) throws -> String {
        // Foundation validates syntax; format the original tokens instead of serializing
        // NSNumber values, which can round large integers and high-precision decimals.
        do {
            _ = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
        } catch let error as NSError {
            throw Failure.invalidJSON(error.userInfo[NSDebugDescriptionErrorKey] as? String ?? "")
        }
        var quoted = false
        var escaped = false
        var compact = ""
        for character in input.unicodeScalars {
            if quoted || !character.properties.isWhitespace { compact.unicodeScalars.append(character) }
            if escaped { escaped = false }
            else if quoted && character == "\\" { escaped = true }
            else if character == "\"" { quoted.toggle() }
        }
        guard pretty else { return compact }
        let characters = Array(compact.unicodeScalars)
        var output = ""
        var depth = 0
        func newline() { output += "\n" + String(repeating: "  ", count: depth) }
        for (index, character) in characters.enumerated() {
            guard output.utf8.count <= 2 * 1024 * 1024 else { throw Failure.outputTooLarge }
            if quoted {
                output.unicodeScalars.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
                continue
            }
            switch character {
            case "\"": quoted = true; output.unicodeScalars.append(character)
            case "{", "[":
                output.unicodeScalars.append(character)
                depth += 1
                let closing: Unicode.Scalar = character == "{" ? "}" : "]"
                if characters[index + 1] != closing { newline() }
            case "}", "]":
                depth -= 1
                let opening: Unicode.Scalar = character == "}" ? "{" : "["
                if characters[index - 1] != opening { newline() }
                output.unicodeScalars.append(character)
            case ",": output.unicodeScalars.append(character); newline()
            case ":": output += ": "
            default: output.unicodeScalars.append(character)
            }
        }
        return output
    }

    /// Every query parameter on its own line, form-decoded (`+` is a space
    /// there, unlike in a path).
    private static func parseURL(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme != nil || components.host != nil
        else { throw Failure.invalidURL }
        var lines: [String] = []
        if let scheme = components.scheme { lines.append("scheme    \(scheme)") }
        if let host = components.host { lines.append("host      \(host)") }
        if let port = components.port { lines.append("port      \(port)") }
        if !components.path.isEmpty { lines.append("path      \(components.path)") }
        if let query = components.percentEncodedQuery, !query.isEmpty {
            lines.append("query")
            for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                func decode(_ part: Substring) -> String {
                    let spaced = part.replacingOccurrences(of: "+", with: " ")
                    return spaced.removingPercentEncoding ?? spaced
                }
                lines.append("  \(decode(parts[0])) = \(parts.count > 1 ? decode(parts[1]) : "")")
            }
        }
        if let fragment = components.fragment { lines.append("fragment  \(fragment)") }
        return lines.joined(separator: "\n")
    }

    /// Only what is not ASCII becomes `\uXXXX` (UTF-16, so emoji become a
    /// surrogate pair): the form logs, Java and JavaScript sources use.
    private static func escape(_ input: String) -> String {
        var output = ""
        for scalar in input.unicodeScalars {
            if scalar.isASCII { output.unicodeScalars.append(scalar); continue }
            for unit in String(scalar).utf16 { output += String(format: "\\u%04x", Int(unit)) }
        }
        return output
    }

    /// `\uXXXX`, `\u{…}` and the JSON escapes, with or without surrounding
    /// quotes. A quoted JSON string is read exactly as JSON reads it.
    private static func unescape(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\""),
           let value = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]) as? String {
            return value
        }
        let scalars = Array(input.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        func hexValue(_ range: Range<Int>) -> UInt32? {
            guard range.upperBound <= scalars.count else { return nil }
            return UInt32(String(String.UnicodeScalarView(scalars[range])), radix: 16)
        }
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\\", index + 1 < scalars.count else {
                output.append(scalar); index += 1; continue
            }
            let next = scalars[index + 1]
            switch next {
            case "u" where index + 2 < scalars.count && scalars[index + 2] == "{":
                guard let close = scalars[(index + 3)...].firstIndex(of: "}"), close - index - 3 <= 6,
                      let value = hexValue((index + 3)..<close), let decoded = Unicode.Scalar(value)
                else { throw Failure.invalidEscape }
                output.append(decoded)
                index = close + 1
            case "u":
                guard let unit = hexValue((index + 2)..<(index + 6)) else {
                    output.append(scalar); index += 1; continue
                }
                index += 6
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 6 <= scalars.count, scalars[index] == "\\", scalars[index + 1] == "u",
                          let low = hexValue((index + 2)..<(index + 6)), (0xDC00...0xDFFF).contains(low),
                          let decoded = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                    else { throw Failure.invalidEscape }
                    output.append(decoded)
                    index += 6
                } else {
                    guard let decoded = Unicode.Scalar(unit) else { throw Failure.invalidEscape }
                    output.append(decoded)
                }
            default:
                let simple: [Unicode.Scalar: Unicode.Scalar] = ["n": "\n", "t": "\t", "r": "\r", "\"": "\"",
                                                                "\\": "\\", "/": "/", "b": "\u{08}", "f": "\u{0C}"]
                if let mapped = simple[next] {
                    output.append(mapped)
                    index += 2
                } else {
                    output.append(scalar); index += 1
                }
            }
        }
        return String(output)
    }

    private static let dateFormats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss",
                                      "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd"]

    /// A Unix timestamp in seconds or milliseconds from 2001 to 2100, or a
    /// date written the way logs and databases write one.
    static func timestampDate(_ text: String) -> Date? {
        if text.count == 10 || text.count == 13, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber),
           let value = Double(text) {
            let seconds = text.count == 13 ? value / 1000 : value
            return (1_000_000_000...4_102_444_800).contains(seconds) ? Date(timeIntervalSince1970: seconds) : nil
        }
        guard text.count >= 10, text.first?.isNumber == true else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Either direction, read from the input: a number becomes dates, a date
    /// becomes numbers. Empty input is now.
    private static func timestamp(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let date: Date
        if trimmed.isEmpty {
            date = Date()
        } else if let parsed = timestampDate(trimmed) {
            date = parsed
        } else if trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }), let value = Double(trimmed) {
            // Out of the recognizable range but still a number: take it at its word by its size.
            date = Date(timeIntervalSince1970: trimmed.count > 11 ? value / 1000 : value)
        } else {
            throw Failure.invalidTimestamp
        }
        return describe(date)
    }

    private static func describe(_ date: Date) -> String {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = date.timeIntervalSince1970
        return [
            local.string(from: date),
            iso.string(from: date),
            "s   \(Int64(seconds.rounded(.down)))",
            "ms  \(Int64((seconds * 1000).rounded(.down)))",
        ].joined(separator: "\n")
    }

    /// Header and payload, formatted, with the standard time claims read out.
    /// The signature is shown as present only: verifying it needs the key.
    private static func jwt(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Bearer ", with: "")
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Failure.invalidJWT }
        func section(_ part: Substring) throws -> (text: String, object: Any) {
            guard let data = base64Data(String(part)), let text = String(data: data, encoding: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { throw Failure.invalidJWT }
            return (try json(text, pretty: true), object)
        }
        let header = try section(parts[0])
        let payload = try section(parts[1])
        var lines = ["// header", header.text, "", "// payload", payload.text]
        if let claims = payload.object as? [String: Any] {
            let times = ["iat", "nbf", "exp"].compactMap { key -> String? in
                guard let value = (claims[key] as? NSNumber)?.doubleValue else { return nil }
                let date = Date(timeIntervalSince1970: value)
                let local = DateFormatter()
                local.locale = Locale(identifier: "en_US_POSIX")
                local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
                let expired = key == "exp" && date < Date() ? "  (expired)" : ""
                return "// \(key)  \(local.string(from: date))\(expired)"
            }
            if !times.isEmpty { lines += [""] + times }
        }
        lines += ["", parts[2].isEmpty ? "// unsigned" : "// signature not verified"]
        return lines.joined(separator: "\n")
    }
}

/// The tool page's state, shared by the page inside the bar and a detached
/// window. Results follow the input as it is typed; nothing is kept once the
/// page closes.
final class CommandBarDeveloperToolModel: ObservableObject {
    @Published var toolID = CommandBarDeveloperTools.all[0].id {
        didSet {
            guard toolID != oldValue else { return }
            operationID = CommandBarDeveloperTools.preferredOperation(of: tool, for: input).id
            compute()
        }
    }
    @Published var operationID = CommandBarDeveloperTools.all[0].operations[0].id {
        didSet { if operationID != oldValue { compute() } }
    }
    @Published var input = "" { didSet { if input != oldValue { scheduleCompute() } } }
    @Published private(set) var output = ""
    @Published private(set) var error: String?
    private var pending: DispatchWorkItem?

    var tool: CommandBarDeveloperTool { CommandBarDeveloperTools.tool(toolID) ?? CommandBarDeveloperTools.all[0] }
    var operation: CommandBarDeveloperTool.Operation { tool.operation(operationID) ?? tool.operations[0] }
    var canCopy: Bool { error == nil && !output.isEmpty }

    func open(toolID: String, operationID: String? = nil, input: String) {
        pending?.cancel()
        self.input = input
        self.toolID = toolID
        self.operationID = operationID ?? CommandBarDeveloperTools.preferredOperation(of: tool, for: input).id
        compute()
    }

    func selectOperation(at index: Int) {
        guard tool.operations.indices.contains(index) else { return }
        operationID = tool.operations[index].id
    }

    func reset() {
        pending?.cancel()
        input = ""
        output = ""
        error = nil
    }

    /// Small inputs answer on the keystroke; a long paste waits for typing to
    /// settle instead of formatting a quarter megabyte per key.
    private func scheduleCompute() {
        pending?.cancel()
        guard input.utf8.count > 32 * 1024 else { compute(); return }
        let work = DispatchWorkItem { [weak self] in self?.compute() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func compute() {
        pending?.cancel()
        // An empty field is not an error, except for tools that answer without input (the time now).
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, toolID != "timestamp" {
            output = ""
            error = nil
            return
        }
        do {
            output = try CommandBarDeveloperTools.run(operation, input: input)
            error = nil
        } catch {
            output = ""
            self.error = CommandBarDeveloperTools.message(for: error,
                                                          chinese: L10n.shared.language.rawValue.hasPrefix("zh"))
        }
    }
}
