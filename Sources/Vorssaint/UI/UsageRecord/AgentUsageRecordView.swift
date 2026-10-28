// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI tab: a year of tokens or API value the coding agents spent, from
/// the record the island's reader and the one-time backfill keep.
struct AgentUsageRecordView: View {
    @Binding var tab: UsageRecordTab
    @ObservedObject private var store = AgentUsageHistoryStore.shared
    @ObservedObject private var l10n = L10n.shared
    /// Read so turning the AI page on or off redraws the paused banner.
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = false
    @AppStorage("agentUsageRecordMode") private var mode = UsageRecordMode.daily.rawValue
    @AppStorage("agentUsageRecordByCost") private var byCost = false
    @AppStorage("agentUsageRecordProvider") private var providerFilter = ""

    private var text: UsageRecordStrings { UsageRecordStrings.strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }

    private var filter: Set<AgentProvider>? { AgentProvider(rawValue: providerFilter).map { [$0] } }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let stats = AgentUsageStats(store.history, providers: filter, byCost: byCost, now: now, calendar: calendar)
            let days = UsageRecordDays.year(now: now, calendar: calendar)
            // Scrolls once the window is shorter than what it holds.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    UsageRecordHeader(tab: $tab, text: text) { filters }
                    if !(agentsEnabled && NotchAgentSupport.isEnabled()) { pausedBanner }
                    UsageStatsRow(tiles: tiles(stats))
                    UsageActivitySection(
                        title: (byCost ? text.cost : text.tokens) + " " + text.activity,
                        days: days, values: values(days), before: before(days),
                        calendar: calendar, locale: locale, text: text, mode: $mode,
                        format: format, describe: describe)
                    breakdown(days)
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
        HStack(spacing: 12) {
            if !store.backfilling.isEmpty {
                ProgressView().controlSize(.small).help(text.backfilling)
            }
            Picker(text.allAgents, selection: $providerFilter) {
                Text(text.allAgents).tag("")
                ForEach(store.history.providers) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker(text.tokens, selection: $byCost) {
                Text(text.tokens).tag(false)
                Text(text.cost).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            Text(text.paused).font(.callout)
            Spacer()
            Button(text.openSettings) {
                SettingsRouter.shared.page = .notch
                appDelegate()?.openSettingsWindow()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tiles(_ stats: AgentUsageStats) -> [(value: String, label: String, help: String?)] {
        [
            (byCost ? AgentFormat.cost(stats.total.cost, locale: locale) : UsageRecordDays.compact(stats.total.tokens, locale: locale),
             byCost ? text.totalCost : text.totalTokens,
             String(format: text.activeDaysFormat, stats.activeDays.formatted(.number.locale(locale)))),
            (stats.peak.map { value($0.usage) } ?? "—", text.peakDay,
             stats.peak.flatMap { UsageDayKey.date($0.key, calendar: calendar) }
                .map { $0.formatted(.dateTime.year().month().day().locale(locale)) }),
            (stats.longestTurn.map { AgentFormat.duration($0, locale: locale, style: .short) } ?? "—", text.longestTurn, nil),
            (text.days(stats.longestStreak), text.longestStreak, nil),
            (text.days(stats.currentStreak), text.currentStreak, nil),
        ]
    }

    /// One day's figures, or a span's total.
    private func describe(_ day: Date?, _ span: [Date]) -> String {
        let total = span.reduce(into: AgentUsageDay()) { $0 += usage(on: $1) }
        let requests = String(format: text.requestsFormat, total.requests.formatted(.number.locale(locale)))
        guard let day else { return [value(total), requests].joined(separator: " · ") }
        let date = day.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(locale))
        guard total.requests > 0 || total.tokens > 0 else { return date + " · " + text.none }
        var parts = [date, value(total), requests]
        if !byCost, total.cost > 0 { parts.append(AgentFormat.cost(total.cost, locale: locale)) }
        if let turn = store.history.longestTurn(on: key(day), providers: filter) {
            parts.append(text.longestTurn + " " + AgentFormat.duration(turn, locale: locale, style: .short))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Agents

    /// What each agent added over the year shown, as one bar split by agent.
    @ViewBuilder private func breakdown(_ days: [Date]) -> some View {
        let shares: [(provider: AgentProvider, value: Double)] = store.history.providers.compactMap { provider in
            let total = days.reduce(0.0) { $0 + store.history.total(on: key($1), providers: [provider]).value(byCost: byCost) }
            return total > 0 ? (provider, total) : nil
        }
        let sum = shares.reduce(0) { $0 + $1.value }
        if filter == nil, shares.count > 1, sum > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text(text.agents).font(.system(size: 15, weight: .semibold))
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(shares, id: \.provider) { share in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Self.color(share.provider))
                                .frame(width: max(2, (proxy.size.width - CGFloat(shares.count - 1) * 2) * share.value / sum))
                        }
                    }
                }
                .frame(height: 8)
                HStack(spacing: 18) {
                    ForEach(shares, id: \.provider) { share in
                        HStack(spacing: 6) {
                            Circle().fill(Self.color(share.provider)).frame(width: 8, height: 8)
                            Text(share.provider.displayName)
                            Text(format(share.value)).foregroundStyle(.secondary).monospacedDigit()
                            Text(AgentFormat.percent(share.value / sum, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    /// Fixed per agent, so a filter or a missing agent never repaints the rest.
    static func color(_ provider: AgentProvider) -> Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .opencode: return Color(red: 0.55, green: 0.42, blue: 0.86)
        case .copilot: return Color(red: 0.20, green: 0.66, blue: 0.47)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.history.isEmpty ? text.empty : text.note)
            if byCost { Text(text.costNote) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Data

    private func key(_ date: Date) -> String { UsageDayKey.key(date, calendar: calendar) }

    private func usage(on date: Date) -> AgentUsageDay {
        store.history.total(on: key(date), providers: filter)
    }

    private func values(_ days: [Date]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, usage(on: $0).value(byCost: byCost)) })
    }

    private func before(_ days: [Date]) -> Double {
        guard let first = days.first else { return 0 }
        let firstKey = key(first)
        return store.history.days.keys.filter { $0 < firstKey }
            .reduce(0.0) { $0 + store.history.total(on: $1, providers: filter).value(byCost: byCost) }
    }

    private func value(_ usage: AgentUsageDay) -> String {
        byCost ? AgentFormat.cost(usage.cost, locale: locale) : UsageRecordDays.compact(usage.tokens, locale: locale)
    }

    private func format(_ number: Double) -> String {
        byCost ? AgentFormat.cost(number, locale: locale) : UsageRecordDays.compact(Int(number), locale: locale)
    }
}
