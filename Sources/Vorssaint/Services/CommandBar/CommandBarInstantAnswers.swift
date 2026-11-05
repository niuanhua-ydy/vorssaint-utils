// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CommandBarNetworkAddress: Equatable {
    let interface: String
    let name: String
    let address: String
    let isPrimary: Bool
}

/// Owned by one command bar. No timers or polling; all in-flight work is
/// cancelled when the query leaves its tool, the bar closes or it uninstalls.
final class CommandBarInstantAnswers {
    enum State: Equatable { case idle, loading, failed, ready }
    static let publicSources: [(name: String, url: URL)] = [
        ("ipify", URL(string: "https://api.ipify.org")!),
        ("IPIP", URL(string: "https://myip.ipip.net/s")!),
    ]
    static let rateSources = [
        URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")!,
        URL(string: "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json")!,
    ]

    var onResult: (() -> Void)?
    private(set) var local: [CommandBarNetworkAddress]?
    private(set) var publicAddresses: [String: String] = [:]
    private(set) var publicState = State.idle
    private(set) var rates: CommandBarCurrency.Table?
    private(set) var ratesState = State.idle
    private var localTask: Task<Void, Never>?
    private var publicTask: Task<Void, Never>?
    private var rateTask: Task<Void, Never>?
    private var session = UUID()
    private var query = ""
    private var rateAttempted = false
    private let readLocal: () async -> [CommandBarNetworkAddress]
    private let fetch: (URL) async throws -> Data
    private let cacheURL: URL?
    private let delay: UInt64
    private var loadedCache = false

    init(cacheURL: URL? = CommandBarInstantAnswers.defaultCacheURL,
         delay: UInt64 = 300_000_000,
         readLocal: @escaping () async -> [CommandBarNetworkAddress] = { [] },
         fetch: @escaping (URL) async throws -> Data = CommandBarInstantAnswers.download) {
        self.cacheURL = cacheURL
        self.delay = delay
        self.readLocal = readLocal
        self.fetch = fetch
    }

    static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils", isDirectory: true)
            .appendingPathComponent("command-bar-rates.json")
    }

    func update(query: String, allowsIP: Bool, allowsCurrency: Bool) {
        self.query = query
        if allowsIP, CommandBarIPQuery.matches(query) {
            loadLocal()
            if CommandBarIPQuery.requestsPublic(query), publicState == .idle { loadPublic() }
        } else {
            localTask?.cancel(); localTask = nil
            publicTask?.cancel(); publicTask = nil
            if publicState == .loading { publicState = .idle }
        }
        if allowsCurrency, CommandBarCurrency.request(query) != nil {
            if !loadedCache {
                loadedCache = true
                if let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count <= 1_048_576,
                   let cached = try? JSONDecoder().decode(CommandBarCurrency.Table.self, from: data),
                   cached.isValid { rates = cached }
            }
            if rates?.isStale() != false, !rateAttempted { loadRates() }
        } else {
            rateTask?.cancel(); rateTask = nil
            if ratesState == .loading { ratesState = .idle; rateAttempted = false }
        }
    }

    private func loadLocal() {
        guard local == nil, localTask == nil else { return }
        let id = session, reader = readLocal
        localTask = Task { @MainActor [weak self] in
            let values = await reader()
            guard !Task.isCancelled, let self, self.session == id,
                  CommandBarIPQuery.matches(self.query) else { return }
            self.local = values
            self.localTask = nil
            self.onResult?()
        }
    }

    func loadPublic() {
        guard CommandBarIPQuery.matches(query), publicState != .loading,
              publicAddresses.count < Self.publicSources.count else { return }
        publicState = .loading
        let id = session, fetch = fetch, delay = delay
        publicTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            var values: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for source in Self.publicSources {
                    group.addTask {
                        let data = try? await fetch(source.url)
                        let address = data.flatMap { $0.count <= 1024 ? CommandBarIPQuery.ipv4(String(decoding: $0, as: UTF8.self)) : nil }
                        return (source.name, address)
                    }
                }
                for await (name, address) in group { if let address { values[name] = address } }
            }
            guard !Task.isCancelled, let self, self.session == id,
                  CommandBarIPQuery.matches(self.query) else { return }
            self.publicAddresses = values
            self.publicState = values.isEmpty ? .failed : .ready
            self.publicTask = nil
            self.onResult?()
        }
    }

    func retryRates() {
        guard ratesState != .loading else { return }
        rateAttempted = false
        loadRates()
    }

    private func loadRates() {
        guard CommandBarCurrency.request(query) != nil, rateTask == nil else { return }
        rateAttempted = true
        ratesState = .loading
        let id = session, fetch = fetch, delay = delay
        rateTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            var table: CommandBarCurrency.Table?
            for source in Self.rateSources {
                guard !Task.isCancelled else { return }
                if let data = try? await fetch(source), let decoded = CommandBarCurrency.decode(data) {
                    table = decoded; break
                }
            }
            guard !Task.isCancelled, let self, self.session == id,
                  CommandBarCurrency.request(self.query) != nil else { return }
            if let table {
                self.rates = table
                if let url = self.cacheURL, let data = try? JSONEncoder().encode(table) {
                    do {
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: url, options: .atomic)
                    } catch { /* A cache failure must not discard a valid answer. */ }
                }
            }
            self.ratesState = table == nil ? .failed : .ready
            self.rateTask = nil
            self.onResult?()
        }
    }

    func reset() {
        session = UUID()
        query = ""
        localTask?.cancel(); localTask = nil
        publicTask?.cancel(); publicTask = nil
        rateTask?.cancel(); rateTask = nil
        local = nil
        publicAddresses = [:]
        publicState = .idle
        ratesState = .idle
        rateAttempted = false
    }

    var isAwaiting: Bool { localTask != nil || publicState == .loading || ratesState == .loading }

    private static let transport: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 6
        return URLSession(configuration: configuration)
    }()

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        let (data, response) = try await transport.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
