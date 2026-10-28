// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The things counted as using Vorssaint. Raw values are stored on disk.
enum AppUsageKind: String, CaseIterable, Identifiable, Codable {
    case commandBar, screenshot, recording, ocr, colorPicker, screenshotTranslate
    case translate, clipNotePaste, plainPaste
    case clean, uninstall, killProcess, freePort

    var id: String { rawValue }

    var group: AppUsageGroup {
        switch self {
        case .commandBar: return .commandBar
        case .screenshot, .recording, .ocr, .colorPicker, .screenshotTranslate: return .capture
        case .translate, .clipNotePaste, .plainPaste: return .text
        case .clean, .uninstall, .killProcess, .freePort: return .maintenance
        }
    }

    var symbol: String {
        switch self {
        case .commandBar: return "command"
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .ocr: return "text.viewfinder"
        case .colorPicker: return "eyedropper"
        case .screenshotTranslate: return "character.textbox"
        case .translate: return "character.bubble"
        case .clipNotePaste: return "list.clipboard"
        case .plainPaste: return "doc.plaintext"
        case .clean: return "sparkles"
        case .uninstall: return "trash"
        case .killProcess: return "xmark.octagon"
        case .freePort: return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum AppUsageGroup: String, CaseIterable, Identifiable {
    case commandBar, capture, text, maintenance
    var id: String { rawValue }
    var kinds: [AppUsageKind] { AppUsageKind.allCases.filter { $0.group == self } }
}

/// A Command Bar row run, by its stable id, with the title it last showed.
struct AppUsageCommand: Codable, Equatable {
    var title: String
    var count: Int
    var last: Date
}

/// How often Vorssaint was used: counts per day per kind, kept for good on
/// this Mac. Only counts and Command Bar row titles, never what was captured,
/// pasted or translated.
struct AppUsageHistory: Codable, Equatable {
    /// Local calendar days as "yyyy-MM-dd", then kinds by raw value.
    var days: [String: [String: Int]] = [:]
    /// Bytes the cleaner and the uninstaller removed, by day.
    var freedBytes: [String: Int64] = [:]
    /// Command Bar rows run, by stable id.
    var commands: [String: AppUsageCommand] = [:]

    var isEmpty: Bool { days.isEmpty }

    mutating func note(_ kind: AppUsageKind, on date: Date, bytes: Int64 = 0,
                       calendar: Calendar = .autoupdatingCurrent) {
        let key = UsageDayKey.key(date, calendar: calendar)
        days[key, default: [:]][kind.rawValue, default: 0] += 1
        if bytes > 0 { freedBytes[key, default: 0] += bytes }
    }

    mutating func noteCommand(id: String, title: String, on date: Date, calendar: Calendar = .autoupdatingCurrent) {
        note(.commandBar, on: date, calendar: calendar)
        var command = commands[id] ?? AppUsageCommand(title: title, count: 0, last: date)
        command.count += 1
        command.last = date
        if !title.isEmpty { command.title = title }
        commands[id] = command
    }

    /// One day's count over `kinds`, every kind when nil.
    func count(on key: String, kinds: Set<AppUsageKind>?) -> Int {
        guard let day = days[key] else { return 0 }
        return day.reduce(0) { sum, entry in
            guard let kind = AppUsageKind(rawValue: entry.key), kinds?.contains(kind) ?? true else { return sum }
            return sum + entry.value
        }
    }

    /// Every day's counts by kind, added up.
    func totals(kinds: Set<AppUsageKind>?) -> [AppUsageKind: Int] {
        var totals: [AppUsageKind: Int] = [:]
        for day in days.values {
            for (raw, count) in day {
                guard let kind = AppUsageKind(rawValue: raw), kinds?.contains(kind) ?? true else { continue }
                totals[kind, default: 0] += count
            }
        }
        return totals
    }

    func topCommands(_ limit: Int) -> [(id: String, command: AppUsageCommand)] {
        commands.map { (id: $0.key, command: $0.value) }
            .sorted { $0.command.count != $1.command.count ? $0.command.count > $1.command.count : $0.command.last > $1.command.last }
            .prefix(limit).map { $0 }
    }
}

enum UsageRecordSupport {
    /// The feature is installed: uses are counted and the window offered.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.usageRecord.isAvailable(in: defaults)
    }
}

/// Local calendar days as "yyyy-MM-dd", the way the record keys them.
enum UsageDayKey {
    static func key(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Days in a row with any use, for both tabs.
enum UsageStreaks {
    /// The longest run ever, and the run up to today, or up to yesterday
    /// while today has none yet.
    static func compute(_ active: [Date], now: Date, calendar: Calendar) -> (longest: Int, current: Int) {
        let sorted = Set(active.map { calendar.startOfDay(for: $0) }).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in sorted {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        let days = Set(sorted)
        var current = 0
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        while days.contains(cursor), let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) {
            current += 1
            cursor = earlier
        }
        return (longest, current)
    }
}

/// Figures over the whole Vorssaint record.
struct AppUsageStats: Equatable {
    var total = 0
    var peak: (key: String, count: Int)?
    var favorite: AppUsageKind?
    var activeDays = 0
    var longestStreak = 0
    var currentStreak = 0
    var freedBytes: Int64 = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.total == rhs.total && lhs.peak?.key == rhs.peak?.key && lhs.peak?.count == rhs.peak?.count
            && lhs.favorite == rhs.favorite && lhs.activeDays == rhs.activeDays
            && lhs.longestStreak == rhs.longestStreak && lhs.currentStreak == rhs.currentStreak
            && lhs.freedBytes == rhs.freedBytes
    }

    init() {}

    init(_ history: AppUsageHistory, kinds: Set<AppUsageKind>?, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        var active: [Date] = []
        for key in history.days.keys {
            let count = history.count(on: key, kinds: kinds)
            guard count > 0 else { continue }
            total += count
            if let date = UsageDayKey.date(key, calendar: calendar) { active.append(date) }
            if peak.map({ count > $0.count || (count == $0.count && key > $0.key) }) ?? true { peak = (key, count) }
        }
        activeDays = active.count
        (longestStreak, currentStreak) = UsageStreaks.compute(active, now: now, calendar: calendar)
        favorite = history.totals(kinds: kinds).max {
            $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue
        }?.key
        if kinds?.contains(where: { $0 == .clean || $0 == .uninstall }) ?? true {
            freedBytes = history.freedBytes.values.reduce(0, +)
        }
    }
}

/// Counts uses of Vorssaint and keeps them on disk. Callable from any
/// thread; the record itself lives on the main thread.
final class AppUsageRecorder: ObservableObject {
    static let shared = AppUsageRecorder()

    @Published private(set) var history: AppUsageHistory

    private static let saveDelay: TimeInterval = 10
    private var saveScheduled = false
    private let url: URL?

    init(url: URL? = AppUsageRecorder.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(AppUsageHistory.self, from: data) {
            history = saved
        } else {
            history = AppUsageHistory()
        }
    }

    static var defaultURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("UsageRecord", isDirectory: true)
            .appendingPathComponent("vorssaint.json", isDirectory: false)
    }


    /// Notes one use. `bytes` is what a cleanup or an uninstall removed.
    static func note(_ kind: AppUsageKind, bytes: Int64 = 0) {
        let date = Date()
        onMain { shared.update { $0.note(kind, on: date, bytes: bytes) } }
    }

    static func noteCommand(id: String, title: String) {
        let date = Date()
        onMain { shared.update { $0.noteCommand(id: id, title: title, on: date) } }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func update(_ change: (inout AppUsageHistory) -> Void) {
        guard UsageRecordSupport.isEnabled() else { return }
        change(&history)
        scheduleSave()
    }

    func clear() {
        history = AppUsageHistory()
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
