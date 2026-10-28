// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the logs before the island's window once, for the usage record's
/// daily totals. A store of its own reads them exactly as the island's does,
/// so a response logged twice still counts once and is priced alike; only
/// the totals per day leave it, and it is let go agent by agent.
enum AgentUsageBackfill {
    /// How far back the record's year reaches past the island's window.
    static let days = 366

    static func read(providers: Set<AgentProvider>, since start: Date, before end: Date,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     calendar: Calendar = .autoupdatingCurrent)
        -> (buckets: [AgentBucket], turns: [AgentProvider: [Date: TimeInterval]]) {
        var buckets: [Date: AgentBucket] = [:]
        var turns: [AgentProvider: [Date: TimeInterval]] = [:]
        let roots = AgentLogRoot.all(home: home).filter { $0.exists }
        for provider in AgentProvider.allCases where providers.contains(provider) {
            autoreleasepool {
                let store = AgentUsageStore()
                var cursors: [String: AgentLogCursor] = [:]
                let now = Date()
                for file in AgentLogReader.discover(roots.filter { $0.provider == provider }, since: start) {
                    let cursor = AgentLogCursor(path: file.path, provider: provider)
                    cursors[file.path] = cursor
                    feed(cursor, into: store, cursors: cursors, since: start, now: now)
                }
                for record in store.records where record.date >= start && record.date < end {
                    let day = calendar.startOfDay(for: record.date)
                    buckets[day, default: AgentBucket(start: day)].byProvider[provider, default: AgentTotals()].add(record)
                }
                turns[provider] = store.longestTurns[provider]?.filter { $0.key >= start && $0.key < end }
            }
        }
        return (buckets.values.sorted { $0.start < $1.start }, turns)
    }

    /// The island's way of reading one log, without its live bookkeeping.
    private static func feed(_ cursor: AgentLogCursor, into store: AgentUsageStore,
                             cursors: [String: AgentLogCursor], since start: Date, now: Date) {
        let path = cursor.path
        let provider = cursor.provider
        let consume: (Data) -> Void = { line in
            let entries = provider.reader.parse(line, state: &cursor.state, now: now)
            guard !entries.isEmpty else { return }
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)"
                : cursor.parent ?? cursor.codexParent(among: cursors)
            store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                        parent: parent, modified: cursor.modified, now: now)
        }
        if provider.reader.readsFullHistoryFirst {
            AgentLogReader.readCopilotHistory(cursor, line: consume)
        } else {
            AgentLogReader.readAppended(cursor, since: start, line: consume)
        }
    }
}
