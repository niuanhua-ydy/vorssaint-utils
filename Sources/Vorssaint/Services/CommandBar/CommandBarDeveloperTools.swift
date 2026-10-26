// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CryptoKit

/// An in-process plugin: register a descriptor, with no changes to the editor or catalog.
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
    let symbol: String
    let keywords: String
    let operations: [Operation]

    var rowID: String { "action.devtool.\(id)" }
}

enum CommandBarDeveloperTools {
    static let maxInputBytes = 256 * 1024

    enum Failure: Error { case tooLarge, outputTooLarge, invalidBase64, invalidUTF8, invalidURL, invalidEscape }

    static let all: [CommandBarDeveloperTool] = [
        .init(id: "json", name: "JSON", chineseName: "JSON 工具", symbol: "curlybraces",
              keywords: "json format pretty minify validate 格式化 压缩 校验", operations: [
                .init(id: "format", name: "Format / validate", chineseName: "格式化 / 校验") {
                    try json($0, pretty: true)
                },
                .init(id: "minify", name: "Minify", chineseName: "压缩") {
                    try json($0, pretty: false)
                },
              ]),
        .init(id: "base64", name: "Base64 · UTF-8", chineseName: "Base64 · UTF-8", symbol: "textformat.abc",
              keywords: "base64 encode decode 编码 解码", operations: [
                .init(id: "encode", name: "Encode", chineseName: "编码") { Data($0.utf8).base64EncodedString() },
                .init(id: "decode", name: "Decode", chineseName: "解码") { input in
                    let compact = input.filter { !$0.isWhitespace }
                    guard let data = Data(base64Encoded: compact) else { throw Failure.invalidBase64 }
                    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidUTF8 }
                    return text
                },
              ]),
        .init(id: "url", name: "URL component", chineseName: "URL 参数编码", symbol: "link",
              keywords: "url percent uri encode decode 编码 解码 百分号", operations: [
                .init(id: "encode", name: "Encode component", chineseName: "编码参数值") {
                    $0.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
                },
                .init(id: "decode", name: "Decode component", chineseName: "解码参数值") {
                    guard let value = $0.removingPercentEncoding else { throw Failure.invalidURL }
                    return value
                },
              ]),
        .init(id: "unicode", name: "Unicode / JSON string", chineseName: "Unicode / JSON 字符串", symbol: "character.cursor.ibeam",
              keywords: "unicode escape unescape utf 转义 反转义 中文", operations: [
                .init(id: "escape", name: "Escape (JSON quoted)", chineseName: "转义（含 JSON 引号）") { input in
                    // UTF-16 units preserve supplementary characters as surrogate pairs.
                    "\"" + input.utf16.map { String(format: "\\u%04x", Int($0)) }.joined() + "\""
                },
                .init(id: "unescape", name: "Unescape JSON string", chineseName: "还原 JSON 字符串") { input in
                    guard let value = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]) as? String
                    else { throw Failure.invalidEscape }
                    return value
                },
              ]),
        .init(id: "sha256", name: "SHA-256 · UTF-8", chineseName: "SHA-256 · UTF-8", symbol: "number",
              keywords: "sha256 hash digest 哈希 摘要", operations: [
                .init(id: "hash", name: "Calculate", chineseName: "计算") {
                    SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
                },
              ]),
    ]

    static func enabled(disabledRaw: String) -> [CommandBarDeveloperTool] {
        let disabled = Set(disabledRaw.split(separator: ",").map(String.init))
        return all.filter { !disabled.contains($0.id) }
    }

    static func setting(_ id: String, enabled: Bool, disabledRaw: String) -> String {
        var disabled = Set(disabledRaw.split(separator: ",").map(String.init))
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        return disabled.sorted().joined(separator: ",")
    }

    static func run(_ operation: CommandBarDeveloperTool.Operation, input: String) throws -> String {
        guard input.utf8.count <= maxInputBytes else { throw Failure.tooLarge }
        return try operation.transform(input)
    }

    private static func json(_ input: String, pretty: Bool) throws -> String {
        // Foundation validates syntax; format the original tokens instead of serializing
        // NSNumber values, which can round large integers and high-precision decimals.
        _ = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
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
}
