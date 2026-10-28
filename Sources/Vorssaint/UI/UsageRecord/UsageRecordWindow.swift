// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Charts
import SwiftUI

enum UsageRecordTab: String, CaseIterable, Identifiable {
    case app, ai
    var id: String { rawValue }
}

/// The usage record in a window of its own: one is enough, and opening it
/// again brings it forward on the tab asked for.
final class UsageRecordWindow: NSObject, NSWindowDelegate {
    static let shared = UsageRecordWindow()
    private var window: NSWindow?

    func show(tab: UsageRecordTab? = nil) {
        guard UsageRecordSupport.isEnabled() else { return }
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: UsageRecordView.tabKey) }
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: UsageRecordView.width, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = UsageRecordStrings.strings(L10n.shared.language).title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: UsageRecordView())
        window.contentMinSize = NSSize(width: UsageRecordView.width, height: 600)
        window.setFrameAutosaveName("UsageRecordWindow")
        if window.frame.origin == .zero { window.center() }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct UsageRecordView: View {
    /// Wide enough for a year of weeks at the map's cell size.
    static let width: CGFloat = 940
    static let tabKey = "usageRecordTab"

    @AppStorage(UsageRecordView.tabKey) private var tab = UsageRecordTab.app.rawValue
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let chosen = Binding(get: { UsageRecordTab(rawValue: tab) ?? .app }, set: { tab = $0.rawValue })
        Group {
            switch chosen.wrappedValue {
            case .app: AppUsageRecordView(tab: chosen)
            case .ai: AgentUsageRecordView(tab: chosen)
            }
        }
        .frame(minWidth: Self.width, minHeight: 600, alignment: .topLeading)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

// MARK: - Shared parts

/// The tabs on the left, a tab's own filters on the right.
struct UsageRecordHeader<Filters: View>: View {
    @Binding var tab: UsageRecordTab
    let text: UsageRecordStrings
    @ViewBuilder var filters: Filters

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 18) {
                ForEach(UsageRecordTab.allCases) { option in
                    Button { tab = option } label: {
                        Text(option == .app ? text.appTab : text.aiTab)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(option == tab ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == tab ? .isSelected : [])
                }
            }
            Spacer()
            filters
        }
    }
}

/// The row of headline figures, divided like Codex's profile.
struct UsageStatsRow: View {
    let tiles: [(value: String, label: String, help: String?)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                if index > 0 { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 40) }
                VStack(spacing: 6) {
                    Text(tile.value)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(tile.label).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .help(tile.help ?? "")
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

enum UsageRecordMode: String, CaseIterable, Identifiable {
    case daily, weekly, cumulative
    var id: String { rawValue }
}

struct UsagePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum UsageRecordDays {
    /// From the first day of the week a year ago through today.
    static func year(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let yearAgo = calendar.date(byAdding: .weekOfYear, value: -52, to: today),
              let first = calendar.dateInterval(of: .weekOfYear, for: yearAgo)?.start else { return [today] }
        var days: [Date] = []
        var day = first
        while day <= today {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// "4.6万" in Chinese and Japanese, "46K" in English, as the reader counts.
    static func compact(_ number: Int, locale: Locale) -> String {
        number.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)).locale(locale))
    }
}

/// A year as a heatmap, weekly bars or a running total, with a line under it
/// for the pointed day or week, or the whole year.
struct UsageActivitySection: View {
    let title: String
    let days: [Date]
    let values: [Date: Double]
    /// Everything recorded before `days`, so the running total ends on the
    /// all-time figure.
    let before: Double
    let calendar: Calendar
    let locale: Locale
    let text: UsageRecordStrings
    @Binding var mode: String
    let format: (Double) -> String
    /// The line for a day, a span of days, or the whole year when nil.
    let describe: (_ day: Date?, _ span: [Date]) -> String
    @State private var hovered: Date?

    private var chosen: UsageRecordMode { UsageRecordMode(rawValue: mode) ?? .daily }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 16) {
                    ForEach(UsageRecordMode.allCases) { option in
                        Button(name(option)) { mode = option.rawValue; hovered = nil }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: option == chosen ? .semibold : .regular))
                            .foregroundStyle(option == chosen ? .primary : .secondary)
                    }
                }
            }
            Group {
                switch chosen {
                case .daily:
                    UsageHeatmap(days: days, values: values, calendar: calendar, locale: locale, hovered: $hovered)
                case .weekly:
                    chart(weekly, unit: .weekOfYear, cumulative: false)
                case .cumulative:
                    chart(cumulative, unit: .day, cumulative: true)
                }
            }
            .frame(height: UsageHeatmap.height(cell: UsageHeatmap.defaultCell) + 22)
            HStack {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer()
                if chosen == .daily { legend }
            }
        }
    }

    private func name(_ mode: UsageRecordMode) -> String {
        switch mode {
        case .daily: return text.daily
        case .weekly: return text.weekly
        case .cumulative: return text.cumulative
        }
    }

    private var detail: String {
        let fullDate = Date.FormatStyle.dateTime.year().month().day().locale(locale)
        switch chosen {
        case .daily:
            return describe(hovered, hovered.map { [$0] } ?? days)
        case .weekly:
            guard let hovered, let week = calendar.dateInterval(of: .weekOfYear, for: hovered) else {
                return describe(nil, days)
            }
            return String(format: text.weekFormat, week.start.formatted(fullDate)) + " · "
                + describe(nil, days.filter { week.contains($0) })
        case .cumulative:
            let points = cumulative
            guard let point = hovered.flatMap({ date in points.last { $0.date <= date } }) ?? points.last else {
                return text.none
            }
            return String(format: text.throughFormat, point.date.formatted(fullDate)) + " · " + format(point.value)
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(text.less)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(UsageHeatmap.fill(level: level))
                    .frame(width: 11, height: 11)
            }
            Text(text.more)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var weekly: [UsagePoint] {
        var sums: [Date: Double] = [:]
        for day in days {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
            sums[week, default: 0] += values[day] ?? 0
        }
        return sums.map { UsagePoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    private var cumulative: [UsagePoint] {
        var running = before
        return days.map { day in
            running += values[day] ?? 0
            return UsagePoint(date: day, value: running)
        }
    }

    private func chart(_ points: [UsagePoint], unit: Calendar.Component, cumulative: Bool) -> some View {
        Chart {
            ForEach(points) { point in
                if cumulative {
                    AreaMark(x: .value("Date", point.date, unit: unit), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [UsageHeatmap.tint.opacity(0.35), UsageHeatmap.tint.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date, unit: unit), y: .value("Value", point.value))
                        .foregroundStyle(UsageHeatmap.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                } else {
                    BarMark(x: .value("Date", point.date, unit: unit), y: .value("Value", point.value))
                        .foregroundStyle(UsageHeatmap.tint.opacity(
                            hovered.map { calendar.isDate($0, equalTo: point.date, toGranularity: .weekOfYear) } ?? true ? 1 : 0.45))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
                }
            }
            if cumulative, let hovered, let point = points.last(where: { $0.date <= hovered }) {
                RuleMark(x: .value("Date", point.date, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", point.date, unit: unit), y: .value("Value", point.value))
                    .foregroundStyle(UsageHeatmap.tint)
                    .symbolSize(60)
            }
        }
        .chartXSelection(value: $hovered)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { mark in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.1))
                AxisValueLabel { if let number = mark.as(Double.self) { Text(format(number)) } }
            }
        }
    }
}

/// A year of days as weeks across and weekdays down, the way GitHub and
/// Codex draw it, with the months underneath.
struct UsageHeatmap: View {
    let days: [Date]
    let values: [Date: Double]
    let calendar: Calendar
    let locale: Locale
    @Binding var hovered: Date?
    var cell: CGFloat = UsageHeatmap.defaultCell

    static let defaultCell: CGFloat = 13
    static let spacing: CGFloat = 3.5
    static func height(cell: CGFloat) -> CGFloat { cell * 7 + spacing * 6 }
    static let tint = Color.accentColor

    static func fill(level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.08) : tint.opacity([0, 0.3, 0.5, 0.75, 1][min(4, level)])
    }

    var body: some View {
        let weeks = columns
        let levels = thresholds
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: Self.spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            if let day = week[row] { square(day, levels: levels) } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            months(weeks)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func square(_ day: Date, levels: [Double]) -> some View {
        let value = values[day] ?? 0
        let isToday = calendar.isDateInToday(day)
        return RoundedRectangle(cornerRadius: cell * 0.23, style: .continuous)
            .fill(Self.fill(level: level(value, levels: levels)))
            .overlay {
                if hovered == day || isToday {
                    RoundedRectangle(cornerRadius: cell * 0.23, style: .continuous)
                        .strokeBorder(Color.primary.opacity(hovered == day ? 0.8 : 0.35), lineWidth: 1)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hovered = day } else if hovered == day { hovered = nil }
            }
    }

    /// A month's name under the week its first day falls in.
    private func months(_ weeks: [[Date?]]) -> some View {
        let step = cell + Self.spacing
        let width = CGFloat(weeks.count) * step - Self.spacing
        return ZStack(alignment: .topLeading) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                if let first = week.compactMap({ $0 }).first(where: { calendar.component(.day, from: $0) == 1 }),
                   CGFloat(index) * step + 30 <= width {
                    Text(first.formatted(.dateTime.month(.abbreviated).locale(locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: CGFloat(index) * step)
                }
            }
        }
        .frame(width: width, height: 14, alignment: .topLeading)
    }

    private var columns: [[Date?]] {
        var weeks: [[Date?]] = []
        var current = [Date?](repeating: nil, count: 7)
        for day in days {
            let weekday = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
            if weekday == 0, current.contains(where: { $0 != nil }) {
                weeks.append(current)
                current = [Date?](repeating: nil, count: 7)
            }
            current[weekday] = day
        }
        if current.contains(where: { $0 != nil }) { weeks.append(current) }
        return weeks
    }

    /// Quartiles of the active days, so one heavy day does not wash out the rest.
    private var thresholds: [Double] {
        let active = values.values.filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { active[min(active.count - 1, Int(Double(active.count) * $0))] }
    }

    private func level(_ value: Double, levels: [Double]) -> Int {
        guard value > 0 else { return 0 }
        guard levels.count == 3 else { return 4 }
        if value <= levels[0] { return 1 }
        if value <= levels[1] { return 2 }
        if value <= levels[2] { return 3 }
        return 4
    }
}
