import Foundation

/// 模型服务的接口格式
public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    /// Anthropic Messages API（Claude 官方及兼容的代理）
    case anthropic
    /// OpenAI Responses API（Codex 使用的接口）
    case openAIResponses
    /// OpenAI 兼容的 Chat Completions（DeepSeek、通义千问、Kimi、Ollama 等大多数服务）
    case openAIChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anthropic: return "Claude"
        case .openAIResponses: return "OpenAI / Codex"
        case .openAIChat: return "OpenAI 兼容"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAIResponses: return "https://api.openai.com"
        case .openAIChat: return ""
        }
    }

    public var defaultModel: String {
        self == .anthropic ? "claude-opus-5-5" : ""
    }

    /// 接口路径（地址中没有写到这一级时自动补上）
    var path: String {
        switch self {
        case .anthropic: return "/v1/messages"
        case .openAIResponses: return "/v1/responses"
        case .openAIChat: return "/v1/chat/completions"
        }
    }
}

/// 思考深度：Claude 对应 output_config.effort，OpenAI 对应 reasoning.effort
public enum AIEffort: String, CaseIterable, Identifiable, Sendable {
    /// 不指定，使用模型默认值
    case auto, low, medium, high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "模型默认"
        case .low: return "低（更快）"
        case .medium: return "中"
        case .high: return "高（更慢）"
        }
    }
}

public struct AIConfig: Sendable {
    public var provider: AIProvider
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var effort: AIEffort
    public var maxOutputTokens: Int

    public init(provider: AIProvider, baseURL: String, apiKey: String, model: String,
                effort: AIEffort = .auto, maxOutputTokens: Int = 16000) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.maxOutputTokens = maxOutputTokens
    }
}

public enum AIStreamEvent: Sendable, Equatable {
    case text(String)
    /// 之前输出的内容作废（服务端拒绝后换用备用模型重新生成）
    case reset
    /// 正常结束；truncated 表示达到输出长度上限被截断
    case finished(truncated: Bool)
}

public enum AIError: LocalizedError, Equatable {
    case notConfigured(String)
    case invalidURL
    case http(status: Int, message: String)
    /// 模型拒绝处理
    case refused
    /// 流式返回过程中服务端报错
    case server(String)
    case network(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "还没有设置\(what)，请在「设置 → AI」中填写"
        case .invalidURL: return "服务地址无效"
        case .http(let status, let message):
            let hint: String
            switch status {
            case 401: hint = "API Key 无效"
            case 403: hint = "没有权限"
            case 404: hint = "接口地址或模型不存在"
            case 413: hint = "内容太长"
            case 429: hint = "请求过于频繁或额度不足，请稍后再试"
            case 500...599: hint = "服务暂时不可用，请稍后再试"
            default: hint = "请求失败"
            }
            return message.isEmpty ? "\(hint)（HTTP \(status)）" : "\(hint)（HTTP \(status)）：\(message)"
        case .refused: return "模型拒绝处理这段内容"
        case .server(let message): return "服务端出错：\(message)"
        case .network(let message): return "网络错误：\(message)"
        case .emptyResponse: return "模型没有返回内容"
        }
    }
}

/// 调用模型服务，以流式方式返回生成的文字
public struct AIClient: Sendable {
    public let config: AIConfig
    private let session: URLSession

    public init(config: AIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// 地址可以只写到域名（或 /v1），也可以写完整的接口地址
    public static func endpoint(provider: AIProvider, baseURL: String) -> URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        let last = provider.path.split(separator: "/").last.map(String.init) ?? ""
        let lower = text.lowercased()
        if lower.hasSuffix(provider.path) || lower.hasSuffix("/" + last) { return url }
        if lower.hasSuffix("/v1") { return URL(string: text + provider.path.dropFirst(3)) }
        return URL(string: text + provider.path)
    }

    /// extras：思考深度、备用模型等可选参数。部分代理或旧模型不认识这些参数，被拒绝（400）时去掉重试
    public func makeRequest(system: String, prompt: String, extras: Bool = true) throws -> URLRequest {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.notConfigured(" API Key") }
        guard !model.isEmpty else { throw AIError.notConfigured("模型") }
        guard let url = Self.endpoint(provider: config.provider, baseURL: config.baseURL) else { throw AIError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["model": model, "stream": true]

        switch config.provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["max_tokens"] = config.maxOutputTokens
            body["system"] = system
            body["messages"] = [["role": "user", "content": prompt]]
            if extras {
                if config.effort != .auto { body["output_config"] = ["effort": config.effort.rawValue] }
                if sendsFallbacks {
                    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                    body["fallbacks"] = "default"
                }
            }
        case .openAIResponses:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body["instructions"] = system
            body["input"] = [["role": "user", "content": prompt]]
            body["max_output_tokens"] = config.maxOutputTokens
            // 不在服务端保存对话
            body["store"] = false
            if extras, config.effort != .auto { body["reasoning"] = ["effort": config.effort.rawValue] }
        case .openAIChat:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body["messages"] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
            if extras, config.effort != .auto { body["reasoning_effort"] = config.effort.rawValue }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func stream(system: String, prompt: String) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, prompt: prompt, extras: true) { continuation.yield($0) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(system: String, prompt: String, extras: Bool,
                     yield: @escaping @Sendable (AIStreamEvent) -> Void) async throws {
        let request = try makeRequest(system: system, prompt: prompt, extras: extras)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 64 * 1024 { break }
            }
            if status == 400 && extras && hasExtras {
                try await run(system: system, prompt: prompt, extras: false, yield: yield)
                return
            }
            throw AIError.http(status: status, message: Self.errorMessage(in: body))
        }

        // 少数代理忽略 stream 参数，直接返回完整的 JSON
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json") {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let text = try AIStreamParser.completeText(provider: config.provider, body: body)
            yield(.text(text))
            yield(.finished(truncated: false))
            return
        }

        var parser = AIStreamParser(provider: config.provider)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            for event in try parser.consume(line: line) { yield(event) }
            if parser.isFinished { return }
        }
        for event in try parser.finish() { yield(event) }
    }

    private var hasExtras: Bool { config.effort != .auto || sendsFallbacks }

    /// 被安全策略拒绝时由服务端换用推荐的备用模型重试（Claude 5 系列；Haiku 没有备用模型）
    private var sendsFallbacks: Bool {
        let model = config.model.lowercased()
        return config.provider == .anthropic && model.hasPrefix("claude-") && model.contains("-5") && !model.contains("haiku")
    }

    /// 从错误响应中取出说明文字（兼容 Anthropic、OpenAI 以及常见代理的格式）
    static func errorMessage(in body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        if let message = json["message"] as? String { return message }
        if let detail = json["detail"] as? String { return detail }
        return ""
    }
}

/// 解析流式返回（Server-Sent Events）。只看 data 行：三种格式的每条 data 都自带类型信息
public struct AIStreamParser {
    public let provider: AIProvider
    public private(set) var isFinished = false
    private var receivedText = false
    private var truncated = false
    private var finishReason: String?

    public init(provider: AIProvider) {
        self.provider = provider
    }

    public mutating func consume(line: String) throws -> [AIStreamEvent] {
        guard !isFinished, line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return try finish()
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch provider {
        case .anthropic: return try consumeAnthropic(json)
        case .openAIResponses: return try consumeResponses(json)
        case .openAIChat: return try consumeChat(json)
        }
    }

    /// 连接结束时调用：没有收到结束事件但已有内容时按正常结束处理
    public mutating func finish() throws -> [AIStreamEvent] {
        guard !isFinished else { return [] }
        isFinished = true
        if finishReason == "content_filter" || finishReason == "refusal" { throw AIError.refused }
        guard receivedText else { throw AIError.emptyResponse }
        return [.finished(truncated: truncated)]
    }

    private mutating func text(_ value: String?) -> [AIStreamEvent] {
        guard let value, !value.isEmpty else { return [] }
        receivedText = true
        return [.text(value)]
    }

    private static func message(_ json: [String: Any]) -> String {
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["type"] as? String) ?? "未知错误"
        }
        return (json["message"] as? String) ?? "未知错误"
    }

    // MARK: Anthropic Messages

    private mutating func consumeAnthropic(_ json: [String: Any]) throws -> [AIStreamEvent] {
        switch json["type"] as? String {
        case "content_block_start":
            // 服务端换用备用模型：前面的输出作废
            if (json["content_block"] as? [String: Any])?["type"] as? String == "fallback" {
                receivedText = false
                return [.reset]
            }
        case "content_block_delta":
            let delta = json["delta"] as? [String: Any]
            if delta?["type"] as? String == "text_delta" { return text(delta?["text"] as? String) }
        case "message_delta":
            if let reason = (json["delta"] as? [String: Any])?["stop_reason"] as? String {
                finishReason = reason
                if reason == "refusal" { throw AIError.refused }
                if reason == "max_tokens" { truncated = true }
            }
        case "message_stop":
            return try finish()
        case "error":
            throw AIError.server(Self.message(json))
        default:
            break
        }
        return []
    }

    // MARK: OpenAI Responses

    private mutating func consumeResponses(_ json: [String: Any]) throws -> [AIStreamEvent] {
        switch json["type"] as? String {
        case "response.output_text.delta", "response.refusal.delta":
            return text(json["delta"] as? String)
        case "response.completed":
            return try finish()
        case "response.incomplete":
            let response = json["response"] as? [String: Any]
            let reason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String
            if reason == "content_filter" { finishReason = reason } else { truncated = true }
            return try finish()
        case "response.failed":
            let response = json["response"] as? [String: Any] ?? [:]
            throw AIError.server(Self.message(response))
        case "error":
            throw AIError.server(Self.message(json))
        default:
            return []
        }
    }

    // MARK: Chat Completions

    private mutating func consumeChat(_ json: [String: Any]) throws -> [AIStreamEvent] {
        if json["error"] != nil { throw AIError.server(Self.message(json)) }
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
        var events = text((choice["delta"] as? [String: Any])?["content"] as? String)
        if let reason = choice["finish_reason"] as? String {
            finishReason = reason
            if reason == "length" { truncated = true }
            events += try finish()
        }
        return events
    }

    // MARK: 非流式响应

    static func completeText(provider: AIProvider, body: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw AIError.emptyResponse }
        var text = ""
        switch provider {
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" { throw AIError.refused }
            for block in json["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                text += block["text"] as? String ?? ""
            }
        case .openAIResponses:
            for item in json["output"] as? [[String: Any]] ?? [] {
                for part in item["content"] as? [[String: Any]] ?? [] {
                    text += (part["text"] as? String) ?? (part["refusal"] as? String) ?? ""
                }
            }
        case .openAIChat:
            let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = message?["content"] as? String ?? ""
        }
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }
}
