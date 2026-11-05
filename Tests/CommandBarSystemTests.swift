// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarSystemTests {
    static let tableData = Data(#"{"date":"2026-11-05","usd":{"usd":1,"cny":7.2,"jpy":150,"eur":0.9,"btc":0.00001}}"#.utf8)

    static func run(_ suite: TestSuite) {
        typealias Query = CommandBarSystemQuery
        suite.expect(Query.request("kill :3000") == .init(verb: .kill, target: .port(3000), force: false), "colon means port, never PID")
        suite.expect(Query.request("kill 3000") == .init(verb: .kill, target: .pid(3000), force: false), "bare numeric kill targets exact PID")
        suite.expect(Query.request("kill -9 :8080") == .init(verb: .kill, target: .port(8080), force: true), "force by port remains explicit")
        for flag in ["-KILL", "-sigkill", "-9"] {
            suite.expect(Query.request("kill " + flag + " 4242") == .init(verb: .kill, target: .pid(4242), force: true), "legacy force flag remains supported")
        }
        for flag in ["-TERM", "-sigterm", "-15"] {
            suite.expect(Query.request("kill " + flag + " 4242") == .init(verb: .kill, target: .pid(4242), force: false), "legacy graceful flag remains supported")
        }
        suite.expect(Query.request("kill pid 4242")?.target == .pid(4242), "legacy labeled PID supported")
        suite.expect(Query.request("kill -9")?.target == .invalid, "incomplete signal cannot list arbitrary targets")
        suite.expect(Query.request("port 3000") == .init(verb: .port, target: .port(3000), force: false), "explicit port query")
        suite.expect(Query.request("PORT node") == .init(verb: .port, target: .name("node"), force: false), "port by process name")
        suite.expect(Query.request("quit Google Chrome")?.target == .name("Google Chrome"), "application names retain spaces")
        suite.expect(Query.request(" forcequit Safari \n")?.force == true, "forcequit is explicit")
        for verb in Query.Verb.allCases {
            suite.expect(Query.request(verb.rawValue)?.target == .all, "a bare verb lists targets without executing")
        }
        for value in ["", "0", "65536", "9999999999999999", "-1", "1.2", "3 000", "１２３"] {
            suite.expect(Query.portNumber(value) == nil, "reject malformed port \(value)")
        }
        for value in ["0", "65536", "abc", ":3000", "-1"] {
            suite.expect(Query.request("kill :" + value)?.target == .invalid, "malformed colon cannot become PID")
        }
        suite.expect(Query.request("kill 99999999999999999999")?.target == .invalid, "PID overflow rejected")
        suite.expect(Query.request("kill 0")?.target == .invalid, "process group zero rejected")
        suite.expect(Query.request("kill -1")?.target == .invalid, "negative process group rejected")
        for query in ["hostname", "killall node", "kill; rm -rf", "quitSafari", "port3000"] {
            suite.expect(Query.request(query) == nil, "only exact built-in verbs are interpreted")
        }
        suite.expect(Query.matches("Google Chrome", target: .name("CHROME")), "target matching ignores case")
        suite.expect(!Query.matches("node", target: .pid(3000)), "name does not imply numeric target")
        for (alias, id) in Query.fixed { suite.expect(Query.fixedID(alias.uppercased()) == id, "fixed alias \(alias)") }

        for query in ["ip", "IP", "本机 ip", "内网ip", "公网ip", "publicip"] {
            suite.expect(CommandBarIPQuery.matches(query), "recognize IP query \(query)")
        }
        suite.expect(!CommandBarIPQuery.requestsPublic("ip"), "local query is offline")
        suite.expect(CommandBarIPQuery.requestsPublic("公网IP"), "public query is explicit consent")
        for address in ["127.0.0.1", "169.254.1.2", "198.18.0.1", "198.19.255.255", "0.0.0.0", "224.0.0.1", "256.1.2.3", "::1", "1.2.3", "1.2.3.4 text"] {
            suite.expect(!CommandBarIPQuery.usableLocal(address), "non-address/link-local/fake-IP filtered: \(address)")
        }
        for address in ["192.168.1.2", "10.0.0.1", "172.16.0.1", "198.20.0.1", "100.64.0.2"] {
            suite.expect(CommandBarIPQuery.usableLocal(address), "usable IPv4 \(address)")
        }
        suite.expect(CommandBarIPQuery.ipv4("8.8.8.8\n") == "8.8.8.8", "public response whitespace trimmed")
        suite.expect(CommandBarIPQuery.ipv4("<html>8.8.8.8</html>") == nil, "HTML response never displayed as IP")

        let conversions: [(String, Double, String, String)] = [
            ("100 USD to CNY", 100, "USD", "CNY"), ("USD 100 in EUR", 100, "USD", "EUR"),
            ("100美元转人民币", 100, "USD", "CNY"), ("100万日元是多少人民币？", 1_000_000, "JPY", "CNY"),
            ("1k usd = cny", 1000, "USD", "CNY"), ("2w港币兑美元", 20000, "HKD", "USD"),
            ("USD CNY", 1, "USD", "CNY"), ("美元/人民币", 1, "USD", "CNY"),
            ("0 usd to cny", 0, "USD", "CNY"), ("-2 eur to usd", -2, "EUR", "USD"),
            ("€20 to USD", 20, "EUR", "USD"), ("100USD", 100, "USD", "CNY"),
        ]
        for (query, amount, from, to) in conversions {
            suite.expect(CommandBarCurrency.request(query, home: "CNY") == .init(amount: amount, from: from, to: to), "currency syntax: \(query)")
        }
        for query in ["USD", "Safari", "100", "100 m", "100 ms", "NaN USD", "inf USD", "100 USD to", "100XYZ", "100 USD to BTC", "1e999 USD"] {
            suite.expect(CommandBarCurrency.request(query) == nil, "incomplete/ordinary/crypto query does not trigger network: \(query)")
        }
        let now = Date(timeIntervalSince1970: 100000)
        guard let table = CommandBarCurrency.decode(tableData, now: now) else { suite.expect(false, "valid rates decode"); return }
        suite.expectClose(table.convert(.init(amount: 100, from: "USD", to: "CNY")) ?? .nan, 720, "USD conversion")
        suite.expectClose(table.convert(.init(amount: 150, from: "JPY", to: "EUR")) ?? .nan, 0.9, "cross-rate via USD")
        suite.expect(table.rates["BTC"] == nil, "fiat table excludes crypto")
        suite.expect(table.convert(.init(amount: 1, from: "XYZ", to: "CNY")) == nil, "missing currency not invented")
        suite.expect(table.convert(.init(amount: .infinity, from: "USD", to: "CNY")) == nil, "nonfinite result rejected")
        suite.expect(!table.isStale(now: now.addingTimeInterval(21599)), "cache before six-hour boundary")
        suite.expect(table.isStale(now: now.addingTimeInterval(21600)), "six-hour cache expiry")
        suite.expect(table.isStale(now: now.addingTimeInterval(-301)), "future cache rejected after clock skew")
        for raw in ["{}", #"{"date":"bad","usd":{"usd":1,"cny":7}}"#,
                    #"{"date":"2026-02-30","usd":{"usd":1,"cny":7}}"#,
                    #"{"date":"2026-11-05","usd":{"usd":true,"cny":7}}"#,
                    #"{"date":"2026-11-05","usd":{"usd":1,"cny":0}}"#,
                    #"{"date":"2026-11-05","usd":{"usd":2,"cny":7}}"#] {
            suite.expect(CommandBarCurrency.decode(Data(raw.utf8)) == nil, "reject malformed rates")
        }
        suite.expect(CommandBarCurrency.formatted(720, code: "CNY") == "720 CNY", "copyable value has unambiguous currency code")
    }

    @MainActor static func runAsync(_ suite: TestSuite) async {
        actor Fetches {
            var urls: [URL] = []
            func record(_ url: URL) { urls.append(url) }
            var count: Int { urls.count }
        }
        func settle(_ predicate: () -> Bool) async {
            for _ in 0..<200 {
                if predicate() { return }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        let local = CommandBarNetworkAddress(interface: "en0", name: "Wi-Fi", address: "192.168.1.2", isPrimary: true)
        let fetched = Fetches()
        let service = CommandBarInstantAnswers(cacheURL: nil, delay: 0, readLocal: { [local] }, fetch: { url in
            await fetched.record(url)
            return Data("8.8.8.8\n".utf8)
        })
        service.update(query: "ip", allowsIP: true, allowsCurrency: true)
        await settle { service.local != nil }
        suite.expect(service.local == [local], "local snapshot arrives asynchronously")
        suite.expect(await fetched.count == 0, "ip alone never sends network request")
        service.loadPublic()
        await settle { service.publicState == .ready }
        suite.expect(service.publicAddresses.count == 2 && service.publicState == .ready, "public sources return separate observed addresses")
        service.update(query: "ip", allowsIP: true, allowsCurrency: true)
        suite.expect(await fetched.count == 2, "presentation cache prevents repeated IP lookup")
        service.reset()
        suite.expect(service.local == nil && service.publicAddresses.isEmpty, "closing clears local/public data")

        let failed = Fetches()
        let bad = CommandBarInstantAnswers(cacheURL: nil, delay: 0, fetch: { url in
            await failed.record(url); throw URLError(.notConnectedToInternet)
        })
        bad.update(query: "publicip", allowsIP: true, allowsCurrency: true)
        await settle { bad.publicState == .failed }
        for _ in 0..<5 { bad.update(query: "publicip", allowsIP: true, allowsCurrency: true) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        suite.expect(await failed.count == 2, "failed lookup never loops on result refresh")
        bad.loadPublic()
        await settle { bad.publicState == .failed }
        suite.expect(await failed.count == 4, "retry is explicit")
        bad.reset()

        let partialFetches = Fetches()
        let partial = CommandBarInstantAnswers(cacheURL: nil, delay: 0, fetch: { url in
            await partialFetches.record(url)
            if url.host == "myip.ipip.net" { throw URLError(.timedOut) }
            return Data("1.1.1.1".utf8)
        })
        partial.update(query: "publicip", allowsIP: true, allowsCurrency: true)
        await settle { partial.publicState == .ready }
        suite.expect(partial.publicAddresses == ["ipify": "1.1.1.1"], "one failed source does not discard the other public address")
        partial.update(query: "publicip", allowsIP: true, allowsCurrency: true)
        suite.expect(await partialFetches.count == 2, "partial success never retries automatically")
        partial.loadPublic()
        await settle { partial.publicState == .ready }
        suite.expect(await partialFetches.count == 4, "partial failure can be retried explicitly")
        partial.reset()

        let late = CommandBarInstantAnswers(cacheURL: nil, delay: 0, readLocal: { [local] }, fetch: { _ in
            // A provider that ignores cancellation must still not publish into a new presentation.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return Data("8.8.4.4".utf8)
        })
        late.update(query: "publicip", allowsIP: true, allowsCurrency: true)
        try? await Task.sleep(nanoseconds: 5_000_000)
        late.reset()
        late.update(query: "ip", allowsIP: true, allowsCurrency: true)
        try? await Task.sleep(nanoseconds: 60_000_000)
        suite.expect(late.publicState == .idle && late.publicAddresses.isEmpty && late.local == [local],
                     "late results from a closed presentation are ignored")
        late.reset()

        let debounce = Fetches()
        let cancelled = CommandBarInstantAnswers(cacheURL: nil, delay: 60_000_000, fetch: { url in
            await debounce.record(url); return tableData
        })
        cancelled.update(query: "100 usd", allowsIP: true, allowsCurrency: true)
        cancelled.update(query: "Safari", allowsIP: true, allowsCurrency: true)
        try? await Task.sleep(nanoseconds: 80_000_000)
        suite.expect(await debounce.count == 0 && cancelled.rates == nil, "leaving query cancels debounced request")
        cancelled.update(query: "publicip", allowsIP: false, allowsCurrency: false)
        cancelled.update(query: "100 usd", allowsIP: false, allowsCurrency: false)
        try? await Task.sleep(nanoseconds: 80_000_000)
        suite.expect(await debounce.count == 0, "disabled sources never fetch")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("command-rates-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("rates.json")
        let rateFetches = Fetches()
        let rates = CommandBarInstantAnswers(cacheURL: cache, delay: 0, fetch: { url in
            await rateFetches.record(url)
            if url == CommandBarInstantAnswers.rateSources[0] { throw URLError(.badServerResponse) }
            return tableData
        })
        rates.update(query: "100 usd to cny", allowsIP: true, allowsCurrency: true)
        await settle { rates.ratesState == .ready }
        suite.expect(await rateFetches.count == 2 && rates.rates?.rates["CNY"] == 7.2, "rate provider fallback")
        suite.expect(FileManager.default.fileExists(atPath: cache.path), "successful table cached atomically")
        let cached = CommandBarInstantAnswers(cacheURL: cache, delay: 0, fetch: { _ in
            suite.expect(false, "fresh disk cache must not contact network"); throw URLError(.cancelled)
        })
        cached.update(query: "200 eur to cny", allowsIP: true, allowsCurrency: true)
        suite.expect(cached.rates == rates.rates && cached.ratesState != .loading, "fresh cache reused across service instances")
        let staleTable = CommandBarCurrency.Table(date: "2026-11-04", fetchedAt: Date(timeIntervalSinceNow: -25000), rates: ["USD": 1, "CNY": 7])
        try? JSONEncoder().encode(staleTable).write(to: cache)
        let stale = CommandBarInstantAnswers(cacheURL: cache, delay: 0, fetch: { _ in throw URLError(.notConnectedToInternet) })
        stale.update(query: "100 usd to cny", allowsIP: true, allowsCurrency: true)
        await settle { stale.ratesState == .failed }
        suite.expect(stale.rates == staleTable && stale.rates?.isStale() == true, "offline retains explicitly stale reference table")
        let unavailableFetches = Fetches()
        let unavailable = CommandBarInstantAnswers(cacheURL: nil, delay: 0, fetch: { url in
            await unavailableFetches.record(url); throw URLError(.notConnectedToInternet)
        })
        unavailable.update(query: "100 usd to cny", allowsIP: true, allowsCurrency: true)
        await settle { unavailable.ratesState == .failed }
        for _ in 0..<5 { unavailable.update(query: "100 usd to cny", allowsIP: true, allowsCurrency: true) }
        suite.expect(await unavailableFetches.count == 2, "rate failure never loops on refresh")
        unavailable.retryRates()
        await settle { unavailable.ratesState == .failed }
        suite.expect(await unavailableFetches.count == 4, "rate retry explicitly retries primary and fallback")
        unavailable.reset()
        rates.reset(); cached.reset(); stale.reset(); cancelled.reset()
    }
}
