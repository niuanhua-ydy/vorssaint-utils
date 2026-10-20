// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// ClipNote's two network clients: the model client behind its AI actions
/// (Anthropic Messages, OpenAI Responses and Chat Completions, streamed) and
/// the WebDAV remote its sync writes to. Requests and parsing are checked
/// offline. The live cases run only when asked for:
///
///   CLIPNOTE_AI_KEY=… [CLIPNOTE_AI_URL=…] [CLIPNOTE_AI_MODEL=…]
///   CLIPNOTE_WEBDAV_URL=http://127.0.0.1:8765/dav/ CLIPNOTE_WEBDAV_USER=… CLIPNOTE_WEBDAV_PASSWORD=…
///   CLIPNOTE_WEBDAV_TLS_URL=https://127.0.0.1:8766/dav/  (a self-signed server)
///
/// Tools/clipnote_mock_webdav.py serves a local stand-in for both WebDAV cases.
enum ClipNoteNetworkTests {
    static func run(_ suite: TestSuite) {
        endpoints(suite)
        requests(suite)
        streams(suite)
        errors(suite)
        propfind(suite)
        liveModel(suite)
        liveWebDAV(suite)
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: Model client

    private static func endpoints(_ suite: TestSuite) {
        func url(_ provider: AIProvider, _ base: String) -> String? {
            AIClient.endpoint(provider: provider, baseURL: base)?.absoluteString
        }
        let completions: [(AIProvider, String, String)] = [
            (.anthropic, "https://api.anthropic.com", "https://api.anthropic.com/v1/messages"),
            (.anthropic, "https://api.anthropic.com/", "https://api.anthropic.com/v1/messages"),
            (.anthropic, "https://proxy.example/v1", "https://proxy.example/v1/messages"),
            (.anthropic, "https://proxy.example/v1/messages", "https://proxy.example/v1/messages"),
            (.openAIResponses, "https://api.openai.com", "https://api.openai.com/v1/responses"),
            (.openAIChat, "https://api.deepseek.com/v1", "https://api.deepseek.com/v1/chat/completions"),
            (.openAIChat, "http://localhost:11434/v1/chat/completions", "http://localhost:11434/v1/chat/completions"),
        ]
        for (provider, base, expected) in completions {
            suite.expectEqual(url(provider, base), expected, "\(provider) endpoint from \(base)")
        }
        suite.expect(url(.anthropic, "api.anthropic.com") == nil, "an address without a scheme is rejected")
        suite.expect(url(.anthropic, "") == nil, "an empty address is rejected")
    }

    private static func jsonObject(_ request: URLRequest) throws -> [String: Any] {
        let body = try clipNoteUnwrap(request.httpBody, "the request body")
        return try clipNoteUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any], "the JSON body")
    }

    private static func requests(_ suite: TestSuite) {
        suite.clipNoteCase("Anthropic request") { _ in
            let client = AIClient(config: AIConfig(provider: .anthropic, baseURL: "https://api.anthropic.com",
                                                   apiKey: "k", model: "claude-opus-5-5", effort: .low))
            let request = try client.makeRequest(system: "sys", prompt: "hi")
            suite.expectEqual(request.value(forHTTPHeaderField: "x-api-key"), "k", "the key goes in x-api-key")
            suite.expectEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01", "the API version is sent")
            suite.expectEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01",
                              "server-side fallback is asked for")
            let body = try jsonObject(request)
            suite.expectEqual(body["system"] as? String, "sys", "the system prompt is sent")
            suite.expectEqual(body["stream"] as? Bool, true, "the reply is streamed")
            suite.expectEqual(body["fallbacks"] as? String, "default", "the default fallbacks are used")
            suite.expectEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low", "the effort is sent")
            suite.expect(body["thinking"] == nil, "no thinking block is sent")

            // The retry after a 400 drops every optional parameter.
            let plain = try client.makeRequest(system: "sys", prompt: "hi", extras: false)
            let plainBody = try jsonObject(plain)
            suite.expect(plainBody["fallbacks"] == nil, "the plain retry drops fallbacks")
            suite.expect(plainBody["output_config"] == nil, "the plain retry drops the effort")
            suite.expect(plain.value(forHTTPHeaderField: "anthropic-beta") == nil, "the plain retry drops the beta header")
        }

        suite.clipNoteCase("OpenAI requests") { _ in
            let responses = AIClient(config: AIConfig(provider: .openAIResponses, baseURL: "https://api.openai.com",
                                                      apiKey: "k", model: "gpt-x", effort: .low))
            let request = try responses.makeRequest(system: "sys", prompt: "hi")
            suite.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k", "the key is a bearer token")
            let body = try jsonObject(request)
            suite.expectEqual(body["instructions"] as? String, "sys", "the system prompt goes in instructions")
            suite.expectEqual(body["store"] as? Bool, false, "the reply is not stored")
            suite.expectEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low", "the effort is sent")

            let chat = AIClient(config: AIConfig(provider: .openAIChat, baseURL: "https://api.deepseek.com", apiKey: "k",
                                                 model: "deepseek-chat"))
            let chatBody = try jsonObject(try chat.makeRequest(system: "sys", prompt: "hi"))
            let messages = try clipNoteUnwrap(chatBody["messages"] as? [[String: String]], "the chat messages")
            suite.expectEqual(messages.map { $0["role"] }, ["system", "user"], "chat sends system then user")
            suite.expect(chatBody["reasoning_effort"] == nil, "chat sends no effort unless one is chosen")
        }

        let unconfigured = AIClient(config: AIConfig(provider: .anthropic, baseURL: "https://api.anthropic.com",
                                                     apiKey: " ", model: "claude-opus-5-5"))
        let error = suite.expectThrows("a blank key is refused") {
            _ = try unconfigured.makeRequest(system: "", prompt: "")
        }
        suite.expectEqual(error as? AIError, .notConfigured(" API Key"), "a blank key asks for the key")
    }

    private static func parse(_ provider: AIProvider, _ lines: [String]) throws -> [AIStreamEvent] {
        var parser = AIStreamParser(provider: provider)
        var events: [AIStreamEvent] = []
        for line in lines { events += try parser.consume(line: line) }
        events += try parser.finish()
        return events
    }

    private static func parseError(_ provider: AIProvider, _ lines: [String]) -> AIError? {
        do {
            _ = try parse(provider, lines)
            return nil
        } catch {
            return error as? AIError
        }
    }

    private static func streams(_ suite: TestSuite) {
        suite.clipNoteCase("model streams") { _ in
            suite.expectEqual(try parse(.anthropic, [
                "event: message_start",
                #"data: {"type":"message_start","message":{"id":"msg_1","content":[]}}"#,
                #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}"#,
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"，世界"}}"#,
                #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
                #"data: {"type":"message_stop"}"#,
            ]), [.text("你好"), .text("，世界"), .finished(truncated: true)], "an Anthropic stream cut at max tokens")

            suite.expectEqual(try parse(.anthropic, [
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"a"}}"#,
                #"data: {"type":"content_block_start","index":1,"content_block":{"type":"fallback"}}"#,
                #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"b"}}"#,
                #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
                #"data: {"type":"message_stop"}"#,
            ]), [.text("a"), .reset, .text("b"), .finished(truncated: false)],
                "a fallback discards what was streamed before it")

            suite.expectEqual(try parse(.openAIResponses, [
                "event: response.created",
                #"data: {"type":"response.created","response":{"id":"resp_1"}}"#,
                #"data: {"type":"response.output_text.delta","delta":"早"}"#,
                #"data: {"type":"response.output_text.delta","delta":"上好"}"#,
                #"data: {"type":"response.completed","response":{"id":"resp_1","status":"completed"}}"#,
            ]), [.text("早"), .text("上好"), .finished(truncated: false)], "a Responses stream")

            suite.expectEqual(try parse(.openAIResponses, [
                #"data: {"type":"response.output_text.delta","delta":"x"}"#,
                #"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#,
            ]), [.text("x"), .finished(truncated: true)], "an incomplete Responses stream is truncated")

            suite.expectEqual(try parse(.openAIChat, [
                #"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#,
                #"data: {"choices":[{"index":0,"delta":{"content":"Hi"}}]}"#,
                #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
                "data: [DONE]",
            ]), [.text("Hi"), .finished(truncated: false)], "a Chat Completions stream")

            let body = Data(#"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#.utf8)
            suite.expectEqual(try AIStreamParser.completeText(provider: .anthropic, body: body), "ok",
                              "a reply that ignored streaming is read whole")
        }

        suite.expectEqual(parseError(.anthropic, [#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#]),
                          .refused, "a refusal is reported")
        suite.expectEqual(parseError(.anthropic, [
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ]), .server("Overloaded"), "a streamed error is reported")
        suite.expectEqual(parseError(.anthropic, []), .emptyResponse, "an empty stream is reported")
        suite.expectEqual(parseError(.openAIResponses, [
            #"data: {"type":"response.failed","response":{"error":{"code":"upstream_error","message":"Upstream request failed"}}}"#,
        ]), .server("Upstream request failed"), "a failed Responses stream is reported")
    }

    private static func errors(_ suite: TestSuite) {
        suite.expectEqual(AIClient.errorMessage(in: Data(#"{"type":"error","error":{"type":"x","message":"bad"}}"#.utf8)),
                          "bad", "an Anthropic error body")
        suite.expectEqual(AIClient.errorMessage(in: Data(#"{"code":"INVALID_API_KEY","message":"Invalid API key"}"#.utf8)),
                          "Invalid API key", "a flat error body")
        suite.expectEqual(AIClient.errorMessage(in: Data("Bad Gateway".utf8)), "Bad Gateway", "a plain-text error body")
    }

    private static func liveModel(_ suite: TestSuite) {
        guard let key = environment["CLIPNOTE_AI_KEY"], !key.isEmpty else { return }
        suite.clipNoteAsyncCase("live model") { _ in
            let env = environment
            let client = AIClient(config: AIConfig(provider: .anthropic,
                                                   baseURL: env["CLIPNOTE_AI_URL"] ?? AIProvider.anthropic.defaultBaseURL,
                                                   apiKey: key, model: env["CLIPNOTE_AI_MODEL"] ?? "claude-opus-5-5",
                                                   effort: .low, maxOutputTokens: 1000))
            var text = ""
            var finished = false
            for try await event in client.stream(system: "只输出译文", prompt: "把 good morning 翻译成中文") {
                switch event {
                case .text(let delta): text += delta
                case .reset: text = ""
                case .finished: finished = true
                }
            }
            suite.expect(finished, "the live stream finishes")
            suite.expect(!text.isEmpty, "the live stream returns text")
            print("[live] \(text)")
        }
    }

    // MARK: WebDAV

    private static func propfind(_ suite: TestSuite) {
        suite.clipNoteCase("PROPFIND parsing") { _ in
            let xml = """
                <?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">
                <d:response><d:href>/dav/ClipNote/sync/devices/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
                <d:response><d:href>/dav/ClipNote/sync/devices/ABC-1/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
                <d:response><d:href>/dav/ClipNote/sync/devices/%E4%B8%AD%E6%96%87/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
                <d:response><d:href>/dav/ClipNote/sync/devices/note.txt</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
                </d:multistatus>
                """
            let entries = try PropfindParser.parse(Data(xml.utf8))
            suite.expectEqual(entries.map(\.name), ["devices", "ABC-1", "中文", "note.txt"], "names are decoded")
            suite.expectEqual(entries.map(\.isCollection), [true, true, true, false], "folders are told from files")
        }
    }

    private static func liveWebDAV(_ suite: TestSuite) {
        let env = environment
        if let url = env["CLIPNOTE_WEBDAV_URL"].flatMap(URL.init(string:)), let user = env["CLIPNOTE_WEBDAV_USER"],
           let password = env["CLIPNOTE_WEBDAV_PASSWORD"] {
            webDAVServer(suite, url: url, user: user, password: password)
        }
        if let url = env["CLIPNOTE_WEBDAV_TLS_URL"].flatMap(URL.init(string:)) {
            selfSignedServer(suite, url: url)
        }
    }

    private static func webDAVServer(_ suite: TestSuite, url: URL, user: String, password: String) {
        func remote(root: String, password override: String? = nil) -> WebDAVRemote {
            WebDAVRemote(baseURL: url, username: user, password: override ?? password, rootPath: root,
                         requestInterval: 0.01)
        }

        suite.clipNoteAsyncCase("WebDAV operations") { _ in
            let server = remote(root: "ClipNoteTest-\(UUID().uuidString.prefix(8))/同步")
            try await server.testConnection()
            let missing = try await server.read("missing.json")
            suite.expect(missing == nil, "a missing file reads as nothing")
            try await server.write("devices/设备一/head.json", data: Data("{}".utf8))
            try await server.makeDirectory("devices/设备二")
            try await server.makeDirectory("devices/设备二")
            let head = try await server.read("devices/设备一/head.json")
            suite.expectEqual(head, Data("{}".utf8), "writing creates the missing parent folders")
            let devices = try await server.listDirectories("devices")
            suite.expectEqual(Set(devices), ["设备一", "设备二"], "making a folder twice is harmless")
            try await server.delete("devices/设备一/head.json")
            try await server.delete("devices/设备一/head.json")
            let deleted = try await server.read("devices/设备一/head.json")
            suite.expect(deleted == nil, "deleting twice is harmless")
        }

        suite.clipNoteAsyncCase("WebDAV wrong password") { _ in
            do {
                try await remote(root: "x", password: "wrong").testConnection()
                suite.expect(false, "a wrong password is refused")
            } catch {
                suite.expectEqual(error as? WebDAVError, .unauthorized, "a wrong password reads as unauthorized")
            }
        }

        suite.clipNoteAsyncCase("two devices over WebDAV") { scratch in
            let root = "ClipNoteTest-\(UUID().uuidString.prefix(8))/sync"
            func device(_ name: String) throws -> (ClipStore, SyncEngine) {
                let store = try scratch.store(name)
                store.isSyncRecording = true
                let config = SyncConfiguration(deviceName: name, passphrase: "pass", includeImages: true, target: root)
                return (store, SyncEngine(store: store, remote: remote(root: root), configuration: config))
            }
            let (a, engineA) = try device("A")
            let (b, engineB) = try device("B")
            let path = "Images/x.png"
            try Data([0x89, 0x50, 0x4E, 0x47, 7]).write(to: a.url(forRelativePath: path))
            try a.insert(NewClip(type: .image, content: path, searchText: "", hash: "i:x"))
            try a.insert(NewClip(type: .text, content: "通过 WebDAV 同步", searchText: "通过 WebDAV 同步", hash: "t1"))
            _ = try await engineA.syncOnce()
            let report = try await engineB.syncOnce()
            suite.expectEqual(report.applied.inserted, 2, "both items arrive")
            suite.expectEqual(b.fetch(ClipQuery(text: "WebDAV")).count, 1, "the text arrives indexed")
            let image = try clipNoteUnwrap(b.fetch(ClipQuery(type: .image)).first, "the synced image")
            suite.expectEqual(try Data(contentsOf: b.url(forRelativePath: image.content)),
                              Data([0x89, 0x50, 0x4E, 0x47, 7]), "the image's file arrives")
        }
    }

    private static func selfSignedServer(_ suite: TestSuite, url: URL) {
        suite.clipNoteAsyncCase("self-signed WebDAV") { _ in
            let strict = WebDAVRemote(baseURL: url, username: "test@example.com", password: "app-password",
                                      rootPath: "tls", requestInterval: 0.01)
            do {
                try await strict.testConnection()
                suite.expect(false, "a self-signed certificate is refused by default")
            } catch {
                if case .network? = error as? WebDAVError {
                    suite.expect(true, "a self-signed certificate fails as a network error")
                } else {
                    suite.expect(false, "a self-signed certificate fails as a network error, got \(error)")
                }
            }
            let trusting = WebDAVRemote(baseURL: url, username: "test@example.com", password: "app-password",
                                        rootPath: "tls", requestInterval: 0.01, allowSelfSignedCertificates: true)
            try await trusting.testConnection()
            try await trusting.write("a/b.txt", data: Data("ok".utf8))
            let data = try await trusting.read("a/b.txt")
            suite.expectEqual(data, Data("ok".utf8), "a trusted self-signed server reads back")
            let folders = try await trusting.listDirectories("")
            suite.expectEqual(folders, ["a"], "a trusted self-signed server lists folders")
        }
    }
}
