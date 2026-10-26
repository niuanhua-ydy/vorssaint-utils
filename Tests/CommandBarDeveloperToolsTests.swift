// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarDeveloperToolsTests {
    static func run(_ suite: TestSuite) {
        func convert(_ tool: String, _ operation: String, _ input: String) throws -> String {
            let entry = CommandBarDeveloperTools.all.first { $0.id == tool }!
            return try CommandBarDeveloperTools.run(entry.operations.first { $0.id == operation }!, input: input)
        }
        func rejects(_ tool: String, _ operation: String, _ input: String) -> Bool {
            do { _ = try convert(tool, operation, input); return false } catch { return true }
        }
        suite.expect(Set(CommandBarDeveloperTools.all.map(\.id)).count == 5, "unique plugin identities")
        for tool in CommandBarDeveloperTools.all {
            suite.expect(!tool.operations.isEmpty && Set(tool.operations.map(\.id)).count == tool.operations.count,
                         "operations have unique stable identities")
            let disabled = CommandBarDeveloperTools.setting(tool.id, enabled: false, disabledRaw: "future")
            suite.expect(!CommandBarDeveloperTools.enabled(disabledRaw: disabled).contains { $0.id == tool.id },
                         "disabled plugin disappears from catalog source")
            suite.expect(CommandBarDeveloperTools.setting(tool.id, enabled: true, disabledRaw: disabled) == "future",
                         "reenabling preserves unknown plugin preferences")
        }
        do {
            let input = "中文 😀\n+ / & = \" \\"
            let base64 = try convert("base64", "encode", input)
            suite.expect(try convert("base64", "decode", base64 + "\n") == input, "Base64 round trip with whitespace")
            let url = try convert("url", "encode", input)
            suite.expect(try convert("url", "decode", url) == input, "URL round trip Unicode and reserved characters")
            suite.expect(try convert("url", "encode", "+ /?&=") == "%2B%20%2F%3F%26%3D", "URL encodes a component, not an entire URL")
            suite.expect(try convert("url", "decode", "a+b") == "a+b", "URL decode is not form-urlencoded")
            let escaped = try convert("unicode", "escape", input)
            suite.expect(escaped.contains("\\ud83d\\ude00"), "Unicode uses surrogate pairs")
            suite.expect(try convert("unicode", "unescape", escaped) == input, "Unicode round trip")
            suite.expect(try convert("unicode", "unescape", "\"a\\n\\t\\\"\"") == "a\n\t\"", "standard JSON escapes")
            suite.expect(try convert("json", "minify", " { \"b\": 2, \"a\": [true,null] } ") == "{\"b\":2,\"a\":[true,null]}", "JSON minify preserves key order")
            suite.expect(try convert("json", "format", "{\"a\":1}").contains("\n"), "JSON format is multiline")
            let combining = "{\"text\":\"\u{0301} x\"}"
            suite.expect(try convert("json", "minify", convert("json", "format", combining)) == combining, "combining marks adjacent to quotes preserve string boundaries")
            let precise = "{\"n\":123456789012345678901234567890,\"d\":0.12345678901234567890123456789}"
            suite.expect(try convert("json", "minify", convert("json", "format", precise)) == precise, "JSON preserves numeric tokens exactly")
            let nested = "{\"a\":[{},[],{\"s\":\"a , : [ ] { } \\\" \\\\ b\"}]}"
            suite.expect(try convert("json", "minify", convert("json", "format", nested)) == nested, "JSON preserves escapes and punctuation inside strings")
            for fragment in ["null", "true", "42", "\"hello\"", "[]"] {
                suite.expect(try convert("json", "minify", fragment) == fragment, "JSON accepts scalar fragments")
            }
            suite.expect(try convert("sha256", "hash", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 known vector")
            suite.expect(try convert("base64", "decode", "") == "", "empty output is valid")
        } catch { suite.expect(false, "unexpected conversion error: \(error)") }
        for (tool, operation, input) in [
            ("json", "format", "{"), ("json", "minify", "{} trailing"),
            ("base64", "decode", "YWJj!"), ("base64", "decode", "/w=="),
            ("url", "decode", "%GG"), ("url", "decode", "%FF"),
            ("unicode", "unescape", "{}"), ("unicode", "unescape", "\"\\uD800\""),
        ] { suite.expect(rejects(tool, operation, input), "invalid input is rejected: \(tool)") }
        suite.expect(rejects("json", "format", String(repeating: "[", count: 100) + Array(repeating: "0", count: 12000).joined(separator: ",") + String(repeating: "]", count: 100)), "format expansion is bounded")
        suite.expect(rejects("sha256", "hash", String(repeating: "a", count: CommandBarDeveloperTools.maxInputBytes + 1)), "oversize inputs rejected")
        suite.expect(rejects("sha256", "hash", String(repeating: "字", count: CommandBarDeveloperTools.maxInputBytes / 3 + 1)), "limit counts bytes, not characters")
    }
}
