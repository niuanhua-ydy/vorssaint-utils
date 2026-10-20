import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebDAVError: LocalizedError, Equatable {
    case unauthorized
    /// 服务器拒绝访问（403）：账号对目录没有读写权限，部分服务也用它表示访问过于频繁
    case forbidden
    /// 访问过于频繁或服务暂不可用（429 / 503）；retryAfter 为服务器建议的等待秒数
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int, String)
    case network(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "账号或密码不正确（坚果云等服务需使用第三方应用密码，而不是登录密码）"
        case .forbidden: return "服务器拒绝访问：请检查账号对同步目录是否有读写权限；也可能是访问过于频繁，稍后会自动重试"
        case .rateLimited: return "服务器暂时拒绝访问（访问过于频繁或服务暂不可用），稍后会自动重试"
        case .http(let code, let path): return "服务器返回错误 \(code)（\(path)）"
        case .network(let message): return "网络错误：\(message)"
        case .badResponse: return "服务器响应无法识别"
        }
    }
}

/// 令牌桶限速：保证长期请求频率不超过服务端限制
actor RequestRateLimiter {
    private let capacity: Double
    private let interval: TimeInterval
    private var tokens: Double
    private var last = Date()

    /// interval：恢复一个请求额度所需的秒数
    init(capacity: Double, interval: TimeInterval) {
        self.capacity = capacity
        self.interval = interval
        tokens = capacity
    }

    func acquire() async {
        while true {
            let now = Date()
            tokens = min(capacity, tokens + now.timeIntervalSince(last) / interval)
            last = now
            if tokens >= 1 {
                tokens -= 1
                return
            }
            try? await Task.sleep(nanoseconds: UInt64((1 - tokens) * interval * 1_000_000_000))
        }
    }
}

/// 通用 WebDAV 同步存储：坚果云（https://dav.jianguoyun.com/dav/，用户名为账号邮箱，密码为应用密码）、
/// 群晖 / 威联通等 NAS 的 WebDAV 服务、Nextcloud、Alist 等。
public final class WebDAVRemote: SyncRemote, @unchecked Sendable {

    private let baseURL: URL
    private let rootComponents: [String]
    private let authorization: String
    private let session: URLSession
    private let limiter: RequestRateLimiter
    private let knownDirectories = NSLockedSet()
    /// 坚果云用 403 / 503 表示访问过于频繁；其他服务器上它们分别是无权限、服务不可用

    /// rootPath：同步根目录（相对于 baseURL），如 "ClipNote/sync"
    /// requestInterval：平均每次请求的最小间隔（坚果云免费版限制每 30 分钟 600 次，取 3 秒；自建服务可设很小）
    /// allowSelfSignedCertificates：信任该服务器的自签名 HTTPS 证书（NAS 常见）
    public init(baseURL: URL, username: String, password: String, rootPath: String,
                requestInterval: TimeInterval = 3.0, allowSelfSignedCertificates: Bool = false) {
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        rootComponents = rootPath.split(separator: "/").map(String.init)
        authorization = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let host = baseURL.host
        session = URLSession(configuration: configuration,
                             delegate: allowSelfSignedCertificates ? SelfSignedTrustDelegate(host: host) : nil,
                             delegateQueue: nil)
        limiter = RequestRateLimiter(capacity: 20, interval: requestInterval)
    }

    /// 检查服务器地址与账号是否可用
    public func testConnection() async throws {
        let (_, response) = try await request("PROPFIND", components: [], collection: true, headers: ["Depth": "0"],
                                              body: Self.propfindBody)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw WebDAVError.http(response.statusCode, "/")
        }
    }

    // MARK: - SyncRemote

    public func read(_ path: String) async throws -> Data? {
        let (data, response) = try await request("GET", components: components(path))
        switch response.statusCode {
        case 200: return data
        // 坚果云在上级目录不存在时返回 409 而不是 404
        case 404, 409: return nil
        default: throw WebDAVError.http(response.statusCode, "GET " + path)
        }
    }

    public func write(_ path: String, data: Data) async throws {
        var (_, response) = try await request("PUT", components: components(path), body: data)
        if response.statusCode == 409 {
            // 上级目录不存在：创建后重试
            let parent = components(path).dropLast()
            try await makeDirectory(components: Array(parent))
            (_, response) = try await request("PUT", components: components(path), body: data)
        }
        guard (200..<300).contains(response.statusCode) else { throw WebDAVError.http(response.statusCode, "PUT " + path) }
    }

    public func delete(_ path: String) async throws {
        let (_, response) = try await request("DELETE", components: components(path))
        guard (200..<300).contains(response.statusCode) || response.statusCode == 404 || response.statusCode == 409 else {
            throw WebDAVError.http(response.statusCode, "DELETE " + path)
        }
    }

    public func makeDirectory(_ path: String) async throws {
        try await makeDirectory(components: components(path))
    }

    public func listDirectories(_ path: String) async throws -> [String] {
        let target = components(path)
        let (data, response) = try await request("PROPFIND", components: target, collection: true, headers: ["Depth": "1"],
                                                 body: Self.propfindBody)
        if response.statusCode == 404 || response.statusCode == 409 { return [] }
        guard response.statusCode == 207 else { throw WebDAVError.http(response.statusCode, "PROPFIND " + path) }
        // 响应中包含目录自身：解码后的路径以目标路径结尾的就是它
        let selfPath = target.joined(separator: "/")
        return try PropfindParser.parse(data).filter { entry in
            let decoded = (entry.href.removingPercentEncoding ?? entry.href).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return entry.isCollection && !decoded.hasSuffix(selfPath)
        }.map(\.name)
    }

    // MARK: - 内部

    private func components(_ path: String) -> [String] {
        rootComponents + path.split(separator: "/").map(String.init)
    }

    private func makeDirectory(components: [String]) async throws {
        var current: [String] = []
        for component in components {
            current.append(component)
            let key = current.joined(separator: "/")
            if knownDirectories.contains(key) { continue }
            let (_, response) = try await request("MKCOL", components: current, collection: true)
            // 201 已创建；405 / 301 已存在（部分服务器对已存在的目录重定向）；409 上级不存在（按顺序创建时不会出现）
            guard [200, 201, 204, 301, 405].contains(response.statusCode) else {
                throw WebDAVError.http(response.statusCode, "MKCOL " + key)
            }
            knownDirectories.insert(key)
        }
    }

    static func encodedPath(_ components: [String]) -> String {
        components.map { $0.addingPercentEncoding(withAllowedCharacters: .webDAVPathAllowed) ?? $0 }.joined(separator: "/")
    }

    /// collection：目录地址以 "/" 结尾（部分服务器对不带斜杠的目录请求返回重定向）
    private func url(_ components: [String], collection: Bool = false) -> URL {
        guard !components.isEmpty,
              let url = URL(string: Self.encodedPath(components) + (collection ? "/" : ""), relativeTo: baseURL) else { return baseURL }
        return url.absoluteURL
    }

    private func request(_ method: String, components: [String], collection: Bool = false, headers: [String: String] = [:],
                         body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        await limiter.acquire()
        var request = URLRequest(url: url(components, collection: collection))
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpBody = body
            if method == "PROPFIND" { request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebDAVError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.badResponse }
        switch http.statusCode {
        case 401: throw WebDAVError.unauthorized
        case 403: throw WebDAVError.forbidden
        case 429, 503:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            throw WebDAVError.rateLimited(retryAfter: retryAfter)
        default: return (data, http)
        }
    }

    static let propfindBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>
        """.utf8)
}

/// 只信任指定主机的服务器证书（用于 NAS 的自签名 HTTPS 证书）
final class SelfSignedTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String?

    init(host: String?) {
        self.host = host
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

extension CharacterSet {
    /// 路径单段允许的字符（不含 "/"）
    static let webDAVPathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;?#")
        return set
    }()
}

/// 线程安全的字符串集合
final class NSLockedSet: @unchecked Sendable {
    private var set = Set<String>()
    private let lock = NSLock()

    func contains(_ value: String) -> Bool { lock.withLock { set.contains(value) } }
    func insert(_ value: String) { lock.withLock { _ = set.insert(value) } }
}

/// 解析 PROPFIND 的 multistatus 响应
enum PropfindParser {
    struct Entry {
        var href: String
        var isCollection: Bool

        /// 解码后的最后一段名称
        var name: String {
            let trimmed = href.hasSuffix("/") ? String(href.dropLast()) : href
            let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            return last.removingPercentEncoding ?? last
        }
    }

    static func parse(_ data: Data) throws -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { throw WebDAVError.badResponse }
        return delegate.entries
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        private var current: Entry?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "response": current = Entry(href: "", isCollection: false)
            case "collection": current?.isCollection = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "href": current?.href = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "response":
                if let current { entries.append(current) }
                current = nil
            default: break
            }
        }
    }
}
