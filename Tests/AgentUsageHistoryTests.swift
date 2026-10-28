// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentUsageHistoryTests {
    static func run(_ suite: TestSuite) {
        merging(suite)
        backfill(suite)
    }

    private static func merging(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func totals(_ requests: Int, tokens: Int, cost: Double = 0) -> AgentTotals {
            AgentTotals(tokens: AgentTokens(input: tokens), cost: cost, savings: 0, requests: requests, unpriced: 0)
        }
        func bucket(_ date: Date, _ byProvider: [AgentProvider: AgentTotals]) -> AgentBucket {
            AgentBucket(start: date, byProvider: byProvider)
        }

        var history = AgentUsageHistory()
        let changed = history.merge([bucket(day(-1), [.claude: totals(10, tokens: 1_000), .codex: totals(4, tokens: 400)]),
                                     bucket(day(0), [:])],
                                    longestTurns: [.codex: [day(-1): 600]], calendar: calendar)
        suite.expect(changed, "a first reading changes the record")
        suite.expect(history.days["2026-10-27"] == nil, "a day with no use is not recorded")
        suite.expect(history.total(on: "2026-10-26", providers: nil).tokens == 1_400, "a day adds up every agent")
        suite.expect(history.total(on: "2026-10-26", providers: [.codex]).tokens == 400, "a filter keeps one agent")

        // The agent deleted its log: the day now reads as less and must not shrink.
        let shrunk = history.merge([bucket(day(-1), [.claude: totals(3, tokens: 300)])], longestTurns: [:], calendar: calendar)
        suite.expect(!shrunk, "a reading with fewer responses leaves the record alone")
        suite.expect(history.total(on: "2026-10-26", providers: [.claude]).tokens == 1_000, "a deleted log keeps its day")
        suite.expect(history.total(on: "2026-10-26", providers: [.codex]).tokens == 400, "an agent missing from a reading keeps its day")

        history.merge([bucket(day(-1), [.claude: totals(12, tokens: 1_500, cost: 2)])],
                      longestTurns: [.codex: [day(-1): 300], .claude: [day(-1): 900]], calendar: calendar)
        suite.expect(history.total(on: "2026-10-26", providers: [.claude]).tokens == 1_500, "a fuller reading replaces the day")
        suite.expect(history.longestTurn(on: "2026-10-26", providers: [.codex]) == 600, "a shorter turn keeps the longest")
        suite.expect(history.longestTurn(on: "2026-10-26", providers: nil) == 900, "the longest turn spans agents")

        history.merge([bucket(day(-2), [.codex: totals(1, tokens: 50)]),
                       bucket(day(-5), [.codex: totals(1, tokens: 5_000)]),
                       bucket(day(-6), [.codex: totals(1, tokens: 10)])],
                      longestTurns: [:], calendar: calendar)
        let stats = AgentUsageStats(history, providers: nil, byCost: false, now: today, calendar: calendar)
        suite.expect(stats.activeDays == 4, "active days count days with use")
        suite.expect(stats.total.tokens == 1_500 + 400 + 50 + 5_000 + 10, "the total covers the whole record")
        suite.expect(stats.peak?.key == "2026-10-22", "the peak is the heaviest day")
        suite.expect(stats.longestStreak == 2 && stats.currentStreak == 2, "streaks count days in a row")
        let codex = AgentUsageStats(history, providers: [.codex], byCost: false, now: today, calendar: calendar)
        suite.expect(codex.longestTurn == 600, "the longest turn follows the filter")

        history.backfilled = ["codex"]
        let encoded = try? JSONEncoder().encode(history)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AgentUsageHistory.self, from: $0) }
        suite.expect(decoded == history, "the record survives a save")
        suite.expect(history.providers == [.claude, .codex], "agents keep the app's order")
    }

    /// The old logs are read the way the island reads them, down to a day.
    private static func backfill(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-backfill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: ".codex/sessions/2026/09/22", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-09-22T14:44:23.705Z","type":"session_meta","payload":{"id":"s9","cwd":"/Users/me/code/web"}}"#,
            #"{"timestamp":"2026-09-22T14:44:24.000Z","type":"turn_context","payload":{"model":"gpt-6-astra","cwd":"/Users/me/code/web"}}"#,
            #"{"timestamp":"2026-09-22T14:44:25.000Z","type":"event_msg","payload":{"type":"task_started","started_at":1790088265}}"#,
            #"{"timestamp":"2026-09-22T14:44:53.847Z","type":"token_usage_record","payload":{"session_id":"s9","response_id":"resp_1","usage":{"input_tokens":32167,"cached_input_tokens":20224,"cache_write_input_tokens":0,"output_tokens":156,"reasoning_output_tokens":7,"total_tokens":32323}}}"#,
            #"{"timestamp":"2026-09-22T14:44:53.977Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":32167,"cached_input_tokens":20224,"output_tokens":156,"total_tokens":32323},"last_token_usage":{"input_tokens":32167,"cached_input_tokens":20224,"output_tokens":156,"total_tokens":32323}}}}"#,
            #"{"timestamp":"2026-09-22T14:52:00.000Z","type":"event_msg","payload":{"type":"task_complete","completed_at":1790088720,"duration_ms":458431}}"#,
        ]
        try? (lines.joined(separator: "\n") + "\n").write(to: folder.appending(path: "rollout-s9.jsonl"),
                                                           atomically: true, encoding: .utf8)
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let found = AgentUsageBackfill.read(providers: [.codex], since: start, before: end, home: home, calendar: calendar)
        let day = found.buckets.first
        suite.expect(found.buckets.count == 1, "the backfill gives one day for one day of use")
        suite.expect(day?.byProvider[.codex]?.requests == 1, "a response logged twice counts once")
        suite.expect(day?.byProvider[.codex]?.tokens.total == 32_323, "the backfill keeps the response's tokens")
        suite.expect(abs((found.turns[.codex]?.values.first ?? 0) - 458.431) < 0.01, "the backfill keeps the turn's length")
        let later = AgentUsageBackfill.read(providers: [.codex], since: end, before: Date(), home: home, calendar: calendar)
        suite.expect(later.buckets.isEmpty, "use outside the asked span is left to the live reader")
    }
}
