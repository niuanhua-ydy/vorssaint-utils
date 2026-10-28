// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One agent's use on one day, as far as its logs told.
struct AgentUsageDay: Codable, Equatable {
    var tokens = 0
    var output = 0
    var cost = 0.0
    var requests = 0
    /// Responses from a model without a known price, left out of `cost`.
    var unpriced = 0

    init() {}

    init(_ totals: AgentTotals) {
        tokens = totals.tokens.total
        output = totals.tokens.output
        cost = totals.cost
        requests = totals.requests
        unpriced = totals.unpriced
    }

    static func += (lhs: inout AgentUsageDay, rhs: AgentUsageDay) {
        lhs.tokens += rhs.tokens
        lhs.output += rhs.output
        lhs.cost += rhs.cost
        lhs.requests += rhs.requests
        lhs.unpriced += rhs.unpriced
    }

    func value(byCost: Bool) -> Double { byCost ? cost : Double(tokens) }
}

/// A total per agent per day, kept so the AI tab can show a year: the
/// island's reader holds thirteen weeks of responses in memory, and holding a
/// year of them would cost four times that. Logs older than the reader's
/// window are read once, in the background, for their daily totals only.
/// Nothing in it says what was asked or answered.
struct AgentUsageHistory: Codable, Equatable {
    /// Local calendar days as "yyyy-MM-dd", then agents by raw value.
    var days: [String: [String: AgentUsageDay]] = [:]
    /// The longest finished turn that started on each day, in seconds, by
    /// day and then agent like `days`.
    var longestTurns: [String: [String: TimeInterval]] = [:]
    /// Agents whose logs older than the reader's window were read once.
    var backfilled: Set<String> = []

    var isEmpty: Bool { days.isEmpty && longestTurns.isEmpty }

    /// Takes in what the logs say now. A day's reading for an agent replaces
    /// the kept one only when it holds at least as many responses: a log the
    /// agent deleted, or an agent switched off, reads as less and must not
    /// erase what was recorded. Returns whether anything changed.
    @discardableResult
    mutating func merge(_ buckets: [AgentBucket], longestTurns turns: [AgentProvider: [Date: TimeInterval]],
                        calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let before = self
        for bucket in buckets where !bucket.byProvider.isEmpty {
            let key = UsageDayKey.key(bucket.start, calendar: calendar)
            var day = days[key] ?? [:]
            for (provider, totals) in bucket.byProvider where totals.requests > 0 || totals.tokens.total > 0 {
                let fresh = AgentUsageDay(totals)
                if let kept = day[provider.rawValue], kept.requests > fresh.requests { continue }
                day[provider.rawValue] = fresh
            }
            if !day.isEmpty { days[key] = day }
        }
        for (provider, lengths) in turns {
            for (start, length) in lengths where length > 0 {
                let key = UsageDayKey.key(start, calendar: calendar)
                longestTurns[key, default: [:]][provider.rawValue] = max(
                    longestTurns[key]?[provider.rawValue] ?? 0, length)
            }
        }
        return self != before
    }

    /// One day's total over the agents in `providers`, all of them when nil.
    func total(on key: String, providers: Set<AgentProvider>?) -> AgentUsageDay {
        guard let day = days[key] else { return AgentUsageDay() }
        let wanted = providers.map { Set($0.map(\.rawValue)) }
        var total = AgentUsageDay()
        for (raw, usage) in day where wanted?.contains(raw) ?? true { total += usage }
        return total
    }

    /// The longest turn of a day over the agents in `providers`.
    func longestTurn(on key: String, providers: Set<AgentProvider>?) -> TimeInterval? {
        let wanted = providers.map { Set($0.map(\.rawValue)) }
        return longestTurns[key]?.filter { wanted?.contains($0.key) ?? true }.values.max()
    }

    /// Agents with anything recorded, in the app's usual order.
    var providers: [AgentProvider] {
        let seen = Set(days.values.flatMap(\.keys))
        return AgentProvider.allCases.filter { seen.contains($0.rawValue) }
    }
}

/// Figures over the whole record, for the row of numbers above the map.
struct AgentUsageStats: Equatable {
    struct Peak: Equatable {
        let key: String
        let usage: AgentUsageDay
    }

    var total = AgentUsageDay()
    var peak: Peak?
    var longestTurn: TimeInterval?
    var activeDays = 0
    var longestStreak = 0
    /// Days in a row up to today, or up to yesterday while today has none yet.
    var currentStreak = 0

    init() {}

    init(_ history: AgentUsageHistory, providers: Set<AgentProvider>?, byCost: Bool, now: Date,
         calendar: Calendar = .autoupdatingCurrent) {
        var active: [Date] = []
        for key in history.days.keys {
            let usage = history.total(on: key, providers: providers)
            guard usage.requests > 0 || usage.tokens > 0 else { continue }
            total += usage
            if let date = UsageDayKey.date(key, calendar: calendar) { active.append(date) }
            if peak.map({ usage.value(byCost: byCost) > $0.usage.value(byCost: byCost) }) ?? true {
                peak = Peak(key: key, usage: usage)
            }
        }
        activeDays = active.count
        longestTurn = history.longestTurns.keys.compactMap { history.longestTurn(on: $0, providers: providers) }.max()
        (longestStreak, currentStreak) = UsageStreaks.compute(active, now: now, calendar: calendar)
    }
}

/// Keeps the record on disk and hands it to the window. Main thread only.
final class AgentUsageHistoryStore: ObservableObject {
    static let shared = AgentUsageHistoryStore()

    @Published private(set) var history: AgentUsageHistory
    /// Agents whose old logs are being read right now.
    @Published private(set) var backfilling: Set<AgentProvider> = []

    private static let saveDelay: TimeInterval = 10
    private var saveScheduled = false
    private let url: URL?
    private let queue = DispatchQueue(label: "com.vorssaint.agent-usage-backfill", qos: .utility,
                                      autoreleaseFrequency: .workItem)

    init(url: URL? = AgentUsageHistoryStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(AgentUsageHistory.self, from: data) {
            history = saved
        } else {
            history = AgentUsageHistory()
        }
    }

    /// Application Support, not Caches: the logs may not rebuild what they
    /// no longer hold.
    static var defaultURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("UsageRecord", isDirectory: true)
            .appendingPathComponent("agents.json", isDirectory: false)
    }

    /// Takes in a fresh reading, and has the logs before the reader's window
    /// read once for each agent `providers` holds that never had them read.
    func record(_ buckets: [AgentBucket], longestTurns: [AgentProvider: [Date: TimeInterval]],
                providers: Set<AgentProvider>, window: TimeInterval) {
        guard UsageRecordSupport.isEnabled() else { return }
        var next = history
        if next.merge(buckets, longestTurns: longestTurns) {
            history = next
            scheduleSave()
        }
        let missing = providers.filter { !history.backfilled.contains($0.rawValue) && !backfilling.contains($0) }
        guard !missing.isEmpty else { return }
        backfill(missing, before: Calendar.autoupdatingCurrent.startOfDay(for: Date().addingTimeInterval(-window)))
    }

    private func backfill(_ providers: Set<AgentProvider>, before end: Date) {
        backfilling.formUnion(providers)
        let since = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -AgentUsageBackfill.days, to: end) ?? end
        queue.async { [weak self] in
            let found = AgentUsageBackfill.read(providers: providers, since: since, before: end)
            DispatchQueue.main.async {
                guard let self else { return }
                self.backfilling.subtract(providers)
                var next = self.history
                next.merge(found.buckets, longestTurns: found.turns)
                next.backfilled.formUnion(providers.map(\.rawValue))
                self.history = next
                self.saveNow()
            }
        }
    }

    func clear() {
        history = AgentUsageHistory()
        saveNow()
    }

    /// Writes a change still waiting for its delay, as on quit.
    func flush() {
        if saveScheduled { saveNow() }
    }

    func saveNow() {
        saveScheduled = false
        guard let url, PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()),
              let data = try? JSONEncoder().encode(history) else { return }
        PrivateFileStore.write(data, to: url)
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay) { [weak self] in
            guard let self, self.saveScheduled else { return }
            self.saveNow()
        }
    }
}
