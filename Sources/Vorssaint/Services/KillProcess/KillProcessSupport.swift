// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One row of the live process list: either a single process, or - when
/// grouping is on - a responsible app with every helper process it owns
/// folded into it (`groupedCount > 1`).
struct KillProcessEntry: Identifiable, Equatable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let path: String
    let cpuPercent: Double
    let memoryBytes: Double
    let isRegularApp: Bool
    let bundleURL: URL?
    let groupedCount: Int
    let isProtected: Bool
    /// Kernel start time in microseconds. A PID alone is reusable and is not a
    /// safe identity for a destructive action confirmed from an old row.
    let startedAt: UInt64?

    var id: pid_t { pid }
}

/// Pure helpers for the Kill Process feature: protected system processes,
/// PID query parsing, Command Bar search words, and safety boundaries.
enum KillProcessSupport {
    static func numberComesBefore(_ lhs: Double,
                                  _ rhs: Double,
                                  lhsPID: pid_t,
                                  rhsPID: pid_t,
                                  ascending: Bool) -> Bool {
        if lhs == rhs { return lhsPID < rhsPID }
        return ascending ? lhs < rhs : lhs > rhs
    }

    static func nameComesBefore(_ lhs: String,
                                _ rhs: String,
                                lhsPID: pid_t,
                                rhsPID: pid_t,
                                ascending: Bool) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        if comparison == .orderedSame { return lhsPID < rhsPID }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    /// Every descendant of `root` from a flat parent table, breadth first so
    /// the caller can reverse it and kill deepest first. A pid is visited
    /// once, so a self-parenting or circular row cannot loop, and the total
    /// is capped well above any real process tree.
    static func descendants(of root: pid_t, parents: [(pid: pid_t, ppid: pid_t)]) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for row in parents {
            children[row.ppid, default: []].append(row.pid)
        }
        var result: [pid_t] = []
        var seen: Set<pid_t> = [root]
        var frontier = [root]
        while !frontier.isEmpty, result.count < 4096 {
            var next: [pid_t] = []
            for parent in frontier {
                for child in children[parent] ?? [] where seen.insert(child).inserted {
                    next.append(child)
                }
            }
            result.append(contentsOf: next)
            frontier = next
        }
        return result
    }

    static func normalizedStartDescription(_ value: String) -> String? {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty,
              normalized.range(of: "^[A-Za-z0-9: ]+$", options: .regularExpression) != nil
        else { return nil }
        return normalized
    }

    /// Protects kernel, launchd, vital window/session infrastructure, and the
    /// app's own process from being terminated.
    static func isProtected(pid: pid_t, name: String = "", path: String = "") -> Bool {
        if pid <= 1 || pid == ProcessInfo.processInfo.processIdentifier { return true }
        let lowerName = name.trimmingCharacters(in: .whitespaces).lowercased()
        let lowerPath = path.trimmingCharacters(in: .whitespaces).lowercased()
        let protectedNames: Set<String> = [
            "kernel_task", "launchd", "windowserver", "loginwindow",
            "vorssaint", "vorssaint (developer)", "vorssaintdeveloper"
        ]
        if protectedNames.contains(lowerName) { return true }
        if lowerPath.hasSuffix("/windowserver") || lowerPath.hasSuffix("/loginwindow") || lowerPath.hasSuffix("/launchd") {
            return true
        }
        return false
    }

    // MARK: - PID Queries & Command Bar

    /// Search words for a process row in the Command Bar: its bare PID,
    /// `pid <pid>` and `kill <pid>` phrases, and its executable path.
    static func commandBarKeywords(for entry: KillProcessEntry) -> String {
        commandBarKeywords(pid: entry.pid, path: entry.path)
    }

    static func commandBarKeywords(pid: pid_t, path: String) -> String {
        var words = ["\(pid)", "pid \(pid)", "kill \(pid)"]
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
        if !trimmedPath.isEmpty {
            words.append(trimmedPath)
        }
        return words.joined(separator: " ")
    }

    /// Words that find the "Kill Process" browse row in any language: the
    /// active language's own labels, plus English and Simplified Chinese terms.
    static func browseKeywords(_ language: AppLanguage) -> String {
        var words: [String] = []
        for strings in [FeatureStrings.killProcess(language), .enUS, .zhHans] {
            for word in [strings.pageTitle, strings.killButton, strings.forceKillButton]
            where !words.contains(word) {
                words.append(word)
            }
        }
        for extra in ["kill", "pid", "process", "force quit", "ps", "pkill", "killall", "杀进程", "杀死进程", "结束进程"]
        where !words.contains(extra) {
            words.append(extra)
        }
        return words.joined(separator: " ")
    }

    /// Extracts the PID digits from a query such as `"kill 1234"`, `"pid 1234"`,
    /// `"kill -9 1234"`, `"结束 1234"`, or `"杀 1234"`. Bare numbers such as
    /// `"1234"` are accepted only when `allowBareDigits` is true (inside the
    /// Kill Process category or Settings page), so an ordinary number on the
    /// Command Bar home search still belongs to the calculator and Port Manager.
    static func pidQuery(from query: String,
                         allowBareDigits: Bool = false,
                         language: AppLanguage = .enUS) -> String? {
        parsePIDQuery(from: query, allowBareDigits: allowBareDigits, language: language)?.digits
    }

    /// True when the query explicitly asks for a force-kill (`SIGKILL`), such
    /// as `"kill -9 1234"`, `"kill -KILL 1234"`, `"force kill 1234"`, or
    /// `"强制结束 1234"`.
    static func isForceKillQuery(_ query: String,
                                 language: AppLanguage = .enUS) -> Bool {
        parsePIDQuery(from: query, allowBareDigits: true, language: language)?.force == true
    }

    /// Processes whose PID starts with `pidQuery`, exact PID match first and
    /// longer PIDs that begin with the same digits after, preserving the
    /// caller's sort order within each group.
    static func matchingPIDEntries(in entries: [KillProcessEntry],
                                   pidQuery: String) -> [KillProcessEntry] {
        guard !pidQuery.isEmpty else { return [] }
        var exact: [KillProcessEntry] = []
        var prefix: [KillProcessEntry] = []
        for entry in entries {
            let text = String(entry.pid)
            if text == pidQuery {
                exact.append(entry)
            } else if text.hasPrefix(pidQuery) {
                prefix.append(entry)
            }
        }
        return exact + prefix
    }

    private static func isValidPIDDigits(_ text: Substring) -> Bool {
        guard !text.isEmpty, text.first != "0",
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int32(text), value > 0, value <= 99_999 else { return false }
        return true
    }

    private static let forceSignalFlags: Set<String> = ["-9", "-kill", "-sigkill"]
    private static let gracefulSignalFlags: Set<String> = ["-15", "-term", "-sigterm"]

    private static func parsePIDQuery(from query: String,
                                      allowBareDigits: Bool,
                                      language: AppLanguage) -> (digits: String, force: Bool)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var splitIndex = trimmed.endIndex
        while splitIndex > trimmed.startIndex {
            let prev = trimmed.index(before: splitIndex)
            guard trimmed[prev].isASCII, trimmed[prev].isNumber else { break }
            splitIndex = prev
        }
        let digits = trimmed[splitIndex...]
        guard isValidPIDDigits(digits) else { return nil }

        let rawPrefix = trimmed[..<splitIndex]
        // A port query must never reach PID termination, even inside the
        // process category where bare numbers are otherwise allowed.
        if rawPrefix.contains(":"),
           !rawPrefix.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("pid:") {
            return nil
        }
        if rawPrefix.isEmpty {
            return allowBareDigits ? (String(digits), false) : nil
        }

        // Strip trailing separators (spaces, ':', '=', '#') between the prefix and digits.
        var prefix = String(rawPrefix)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":=#")))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if prefix.isEmpty {
            return allowBareDigits ? (String(digits), false) : nil
        }

        var forceSignal = false
        if prefix.count >= 2, let last = prefix.last {
            if forceSignalFlags.contains(last) {
                forceSignal = true
                prefix.removeLast()
            } else if gracefulSignalFlags.contains(last) {
                prefix.removeLast()
            }
        }

        let verb = prefix.joined(separator: " ")
        let strings = FeatureStrings.killProcess(language)
        let forceVerbs: Set<String> = [
            "force kill", "kill -9", "强制结束", "強制結束", "强制杀死", "强制杀进程",
            strings.forceKillButton.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ]
        if forceVerbs.contains(verb) {
            return (String(digits), true)
        }

        let gracefulVerbs: Set<String> = [
            "kill", "pid", "kill pid", "kill process", "pkill",
            "结束", "结束进程", "杀", "杀死", "杀进程", "杀死进程",
            "結束", "結束處理程序", "終止", "终止", "终止进程",
            strings.killButton.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            strings.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ]
        if gracefulVerbs.contains(verb) {
            return (String(digits), forceSignal)
        }
        return nil
    }
}
