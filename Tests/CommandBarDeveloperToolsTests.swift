// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarDeveloperToolsTests {
    static func run(_ suite: TestSuite) {
        func convert(_ tool: String, _ operation: String, _ input: String) throws -> String {
            let entry = CommandBarDeveloperTools.tool(tool)!
            return try CommandBarDeveloperTools.run(entry.operation(operation)!, input: input)
        }
        func rejects(_ tool: String, _ operation: String, _ input: String) -> Bool {
            do { _ = try convert(tool, operation, input); return false } catch { return true }
        }
        func matched(_ text: String) -> [String] {
            CommandBarDeveloperTools.matches(for: text).map { "\($0.tool.id).\($0.operation.id)" }
        }

        suite.expect(Set(CommandBarDeveloperTools.all.map(\.id)).count == CommandBarDeveloperTools.all.count,
                     "unique tool identities")
        for tool in CommandBarDeveloperTools.all {
            suite.expect(!tool.operations.isEmpty && Set(tool.operations.map(\.id)).count == tool.operations.count,
                         "operations have unique stable identities")
        }
        suite.expect(CommandBarDeveloperTools.tool("base64")?.operations.first?.id == "decode"
                     && CommandBarDeveloperTools.tool("url")?.operations.first?.id == "decode"
                     && CommandBarDeveloperTools.tool("unicode")?.operations.first?.id == "unescape",
                     "decoding is the default direction")

        do {
            let input = "中文 😀\n+ / & = \" !"
            let base64 = try convert("base64", "encode", input)
            suite.expect(try convert("base64", "decode", base64 + "\n") == input, "Base64 round trip with whitespace")
            let urlSafe = try convert("base64", "encodeURL", "??>>")
            suite.expect(!urlSafe.contains("=") && !urlSafe.contains("+") && !urlSafe.contains("/"), "URL-safe Base64 alphabet")
            suite.expect(try convert("base64", "decode", urlSafe) == "??>>", "Base64 decodes URL-safe unpadded text")
            let url = try convert("url", "encode", input)
            suite.expect(try convert("url", "decode", url) == input, "URL round trip Unicode and reserved characters")
            suite.expect(try convert("url", "encode", "+ /?&=") == "%2B%20%2F%3F%26%3D", "URL encodes a component")
            suite.expect(try convert("url", "decode", "a+b") == "a+b", "component decode keeps +")
            let parsed = try convert("url", "parse", "https://example.com:8080/a?q=hello+world&x=%E4%B8%AD#top")
            suite.expect(parsed.contains("host      example.com") && parsed.contains("q = hello world")
                         && parsed.contains("x = 中") && parsed.contains("fragment  top"), "URL parse form-decodes the query")

            let escaped = try convert("unicode", "escape", input)
            suite.expect(escaped.contains("\\u4e2d") && escaped.contains("\\ud83d\\ude00") && escaped.contains("+ / &"),
                         "Unicode escapes only non-ASCII, emoji as surrogate pairs")
            suite.expect(try convert("unicode", "unescape", escaped) == input, "Unicode round trip")
            suite.expect(try convert("unicode", "unescape", "\\u4e2d\\u6587") == "中文", "unquoted escapes from a log")
            suite.expect(try convert("unicode", "unescape", "\\u{1F600} a\\nb") == "😀 a\nb", "brace escapes and JSON escapes")
            suite.expect(try convert("unicode", "unescape", "\"a\\n\\t\\\"\"") == "a\n\t\"", "quoted JSON string")
            suite.expect(try convert("unicode", "unescape", "C:\\path") == "C:\\path", "unknown escapes stay")

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

            let seconds = try convert("timestamp", "convert", "1700000000")
            suite.expect(seconds.contains("2023-11-14T22:13:20.000Z") && seconds.contains("ms  1700000000000"), "timestamp in seconds")
            suite.expect(try convert("timestamp", "convert", "1700000000123").contains("2023-11-14T22:13:20.123Z"), "timestamp in milliseconds")
            suite.expect(try convert("timestamp", "convert", "2023-11-14T22:13:20Z").contains("s   1700000000"), "ISO date to timestamp")
            suite.expect(try convert("timestamp", "convert", "").contains("ms  "), "empty input is now")

            let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
            let decoded = try convert("jwt", "decode", "Bearer " + jwt)
            suite.expect(decoded.contains("\"alg\": \"HS256\"") && decoded.contains("\"name\": \"John Doe\"")
                         && decoded.contains("// iat  2018-01-18") && decoded.contains("not verified"), "JWT header, payload and claims")

            suite.expect(try convert("hash", "sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 known vector")
            suite.expect(try convert("hash", "md5", "abc") == "900150983cd24fb0d6963f7d28e17f72", "MD5 known vector")
            suite.expect(try convert("base64", "decode", "") == "", "empty output is valid")
        } catch { suite.expect(false, "unexpected conversion error: \(error)") }

        for (tool, operation, input) in [
            ("json", "format", "{"), ("json", "minify", "{} trailing"),
            ("base64", "decode", "YWJj!"), ("base64", "decode", "/w=="), ("base64", "decode", "YWJjZ"),
            ("url", "decode", "%GG"), ("url", "decode", "%FF"),
            ("unicode", "unescape", "\"\\uD800\""), ("unicode", "unescape", "\\ud83d"),
            ("timestamp", "convert", "yesterday"), ("jwt", "decode", "a.b"),
        ] { suite.expect(rejects(tool, operation, input), "invalid input is rejected: \(tool) \(input)") }
        do {
            _ = try convert("json", "format", "{\"a\": 1,\n \"b\": x}")
            suite.expect(false, "broken JSON is rejected")
        } catch {
            let message = CommandBarDeveloperTools.message(for: error, chinese: false)
            suite.expect(message.contains("line 2"), "JSON error says where it broke: \(message)")
        }
        suite.expect(rejects("json", "format", String(repeating: "[", count: 100) + Array(repeating: "0", count: 12000).joined(separator: ",") + String(repeating: "]", count: 100)), "format expansion is bounded")
        suite.expect(rejects("hash", "sha256", String(repeating: "a", count: CommandBarDeveloperTools.maxInputBytes + 1)), "oversize inputs rejected")
        suite.expect(rejects("hash", "sha256", String(repeating: "字", count: CommandBarDeveloperTools.maxInputBytes / 3 + 1)), "limit counts bytes, not characters")

        // Recognizing text: confident guesses only.
        suite.expect(matched("{\"a\": [1, 2]}").first == "json.format", "JSON object is recognized")
        suite.expect(matched("{\n  \"a\": 1\n}").contains("json.minify"), "multi-line JSON also offers minify")
        suite.expect(matched("1700000000") == ["timestamp.convert"], "seconds timestamp is recognized")
        suite.expect(matched("1700000000123") == ["timestamp.convert"], "milliseconds timestamp is recognized")
        suite.expect(matched("\\u4e2d\\u6587").first == "unicode.unescape", "escapes are recognized")
        suite.expect(matched("a%20b%E4%B8%AD").first == "url.decode", "percent encoding is recognized")
        suite.expect(matched("https://example.com/?q=1&b=2").first == "url.parse", "URL with a query is recognized")
        suite.expect(matched("SGVsbG8sIHdvcmxkIQ==").first == "base64.decode", "Base64 text is recognized")
        suite.expect(matched("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc").first == "jwt.decode", "JWT is recognized first")
        for plain in ["test", "terminal", "systemsettings", "Settings", "safari", "1234", "12345678901",
                      "2+2", "d41d8cd98f00b204e9800998ecf8427e", "hello world", "https://example.com",
                      "4102444801", "brightness 40", "中文"] {
            suite.expect(matched(plain).isEmpty, "plain search text is left alone: \(plain)")
        }
        suite.expect(CommandBarDeveloperTools.matches(for: "{\"a\":1}\n{\"b\":2}\n", limit: 3).count <= 3, "match count is capped")

        // The tool page follows typing and starts on the operation the text needs.
        let model = CommandBarDeveloperToolModel()
        model.open(toolID: "base64", input: "SGVsbG8=")
        suite.expect(model.operationID == "decode" && model.output == "Hello" && model.canCopy, "page decodes as it opens")
        model.selectOperation(at: 1)
        suite.expect(model.operationID == "encode" && model.output == "U0dWc2JHOD0=", "switching operation recomputes")
        model.input = "{"
        model.toolID = "json"
        suite.expect(model.operationID == "format" && model.error != nil && !model.canCopy, "errors block copying")
        model.input = ""
        suite.expect(model.error == nil && model.output.isEmpty, "empty input is not an error")
        model.open(toolID: "url", input: "https://a.com/?x=1")
        suite.expect(model.operationID == "parse", "a URL with a query opens on parse")
    }
}
