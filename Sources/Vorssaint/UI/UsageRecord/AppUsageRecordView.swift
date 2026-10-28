// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Vorssaint tab: how often the app itself was used, and for what.
struct AppUsageRecordView: View {
    @Binding var tab: UsageRecordTab
    @ObservedObject private var recorder = AppUsageRecorder.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("appUsageRecordMode") private var mode = UsageRecordMode.daily.rawValue
    @AppStorage("appUsageRecordGroup") private var groupFilter = ""

    private var text: UsageRecordStrings { UsageRecordStrings.strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }

    private var group: AppUsageGroup? { AppUsageGroup(rawValue: groupFilter) }
    private var filter: Set<AppUsageKind>? { group.map { Set($0.kinds) } }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let history = recorder.history
            let stats = AppUsageStats(history, kinds: filter, now: now, calendar: calendar)
            let days = UsageRecordDays.year(now: now, calendar: calendar)
            // Scrolls once the window is shorter than what it holds.
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                UsageRecordHeader(tab: $tab, text: text) { filters }
                UsageStatsRow(tiles: tiles(stats))
                UsageActivitySection(
                    title: text.usesActivity,
                    days: days, values: values(days, history), before: before(days, history),
                    calendar: calendar, locale: locale, text: text, mode: $mode,
                    format: { text.times(count(Int($0))) },
                    describe: { describe($0, $1, history) })
                HStack(alignment: .top, spacing: 40) {
                    features(history, stats: stats)
                    if group == nil || group == .commandBar { commands(history) }
                }
                footer
            }
            .padding(.horizontal, 32)
            .padding(.top, 38)
            .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var filters: some View {
        Picker(text.allFeatures, selection: $groupFilter) {
            Text(text.allFeatures).tag("")
            ForEach(AppUsageGroup.allCases) { group in
                Text(text.group(group)).tag(group.rawValue)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func tiles(_ stats: AppUsageStats) -> [(value: String, label: String, help: String?)] {
        [
            (count(stats.total), text.totalUses,
             String(format: text.activeDaysFormat, stats.activeDays.formatted(.number.locale(locale)))),
            (stats.peak.map { text.times(count($0.count)) } ?? "—", text.peakDay,
             stats.peak.flatMap { UsageDayKey.date($0.key, calendar: calendar) }
                .map { $0.formatted(.dateTime.year().month().day().locale(locale)) }),
            (stats.favorite.map { text.kind($0) } ?? "—", text.favorite, nil),
            (text.days(stats.longestStreak), text.longestStreak, nil),
            (text.days(stats.currentStreak), text.currentStreak, nil),
        ]
    }

    /// A day's uses by feature, or a span's total.
    private func describe(_ day: Date?, _ span: [Date], _ history: AppUsageHistory) -> String {
        let total = span.reduce(0) { $0 + history.count(on: key($1), kinds: filter) }
        guard let day else { return text.times(count(total)) }
        let date = day.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(locale))
        guard total > 0 else { return date + " · " + text.none }
        let counts = (history.days[key(day)] ?? [:]).compactMap { raw, value -> (AppUsageKind, Int)? in
            guard let kind = AppUsageKind(rawValue: raw), filter?.contains(kind) ?? true, value > 0 else { return nil }
            return (kind, value)
        }.sorted { $0.1 > $1.1 }
        let parts = counts.prefix(4).map { "\(text.kind($0.0)) \(count($0.1))" }
        return ([date, text.times(count(total))] + parts).joined(separator: " · ")
    }

    // MARK: Breakdown

    @ViewBuilder private func features(_ history: AppUsageHistory, stats: AppUsageStats) -> some View {
        let totals = history.totals(kinds: filter).filter { $0.value > 0 }.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
        }
        let largest = Double(totals.first?.value ?? 1)
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text.byFeature).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if stats.freedBytes > 0 {
                        Text(String(format: text.freedFormat,
                                    ByteCountFormatter.string(fromByteCount: stats.freedBytes, countStyle: .file)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(totals.prefix(6), id: \.key) { kind, value in
                    row(symbol: kind.symbol, title: text.kind(kind), value: value, fraction: Double(value) / largest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func commands(_ history: AppUsageHistory) -> some View {
        let top = history.topCommands(6)
        let largest = Double(top.first?.command.count ?? 1)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(text.topCommands).font(.system(size: 15, weight: .semibold))
                ForEach(top, id: \.id) { entry in
                    row(symbol: AppUsageKind.commandBar.symbol, title: entry.command.title,
                        value: entry.command.count, fraction: Double(entry.command.count) / largest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func row(symbol: String, title: String, value: Int, fraction: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title).lineLimit(1).frame(width: 150, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(UsageHeatmap.tint.opacity(0.75))
                    .frame(width: max(3, proxy.size.width * fraction), height: 6)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            Text(count(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Text(recorder.history.isEmpty ? text.appEmpty : text.appNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Data

    private func key(_ date: Date) -> String { UsageDayKey.key(date, calendar: calendar) }

    private func values(_ days: [Date], _ history: AppUsageHistory) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, Double(history.count(on: key($0), kinds: filter))) })
    }

    private func before(_ days: [Date], _ history: AppUsageHistory) -> Double {
        guard let first = days.first else { return 0 }
        let firstKey = key(first)
        return Double(history.days.keys.filter { $0 < firstKey }.reduce(0) { $0 + history.count(on: $1, kinds: filter) })
    }

    private func count(_ value: Int) -> String {
        value >= 10_000 ? UsageRecordDays.compact(value, locale: locale) : value.formatted(.number.locale(locale))
    }
}
