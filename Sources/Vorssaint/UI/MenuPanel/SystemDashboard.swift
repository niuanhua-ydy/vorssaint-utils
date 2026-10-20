// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The System tab as a dashboard: the Mac's identity in a row of chips, one
/// card per resource in two columns, and the heaviest apps underneath. Every
/// card opens that resource's detail page, which keeps the history, the
/// breakdown and the per-app list the cards leave out. The list-style
/// `SystemSection` stays in the source for upstream merges.
struct SystemDashboard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    var collapsible = true
    let showMetric: (MetricDetailKind) -> Void
    @State private var memoryRows: [ProcessUsage] = []
    @State private var cpuRows: [ProcessUsage] = []
    @State private var processSort: BreakdownKind = .memory
    @State private var processRefreshInFlight = false
    @State private var lastProcessRefresh = Date.distantPast
    private let processLimit = 5
    /// Wide enough that the other column still finds most of the apps the
    /// sorted one lists.
    private let processSampleLimit = 40

    var body: some View {
        PanelSection(.system, title: l10n.s.systemSection, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 8) {
                identityChips
                cardGrid
                if showsDevicesRow { devicesRow }
                processCard
            }
        }
        .onAppear {
            memoryRows = ProcessUsageService.shared.cachedTop(.memory, limit: processSampleLimit) ?? []
            cpuRows = ProcessUsageService.shared.cachedTop(.cpu, limit: processSampleLimit) ?? []
            refreshProcesses(force: true)
        }
        .onReceive(monitor.$snapshot) { _ in refreshProcesses(force: false) }
        .onDisappear {
            memoryRows = []
            cpuRows = []
        }
    }

    private var text: SystemDashboardStrings { FeatureStrings.systemDashboard(l10n.language) }

    // MARK: Identity

    private var identityChips: some View {
        HStack(spacing: 5) {
            ForEach([Self.chipName, Self.installedMemory, Self.systemVersion], id: \.self) { value in
                chip(value).fixedSize()
            }
            chip("\(l10n.s.systemUptime) \(SystemSection.uptimeString())")
                .layoutPriority(-1)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PanelSurface.controlFill(for: colorScheme)))
    }

    /// "M4 Pro" out of "Apple M4 Pro"; an Intel brand string is kept whole.
    private static let chipName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        let brand = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        if brand.hasPrefix("Apple ") { return String(brand.dropFirst("Apple ".count)) }
        return brand.isEmpty ? "Mac" : brand
    }()

    private static let installedMemory: String = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory))
    }()

    private static let systemVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = version.patchVersion > 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            : "\(version.majorVersion).\(version.minorVersion)"
        return "macOS \(number)"
    }()

    // MARK: Cards

    private enum Card: Hashable { case cpu, gpu, memory, disk, network, battery, devices }

    /// A Mac without a battery spends that card on its USB devices, so the
    /// grid stays even on a desktop.
    private var cards: [Card] {
        var cards: [Card] = []
        if AppFeature.monitorCPU.isAvailable { cards.append(.cpu) }
        if AppFeature.monitorGPU.isAvailable { cards.append(.gpu) }
        if AppFeature.monitorMemory.isAvailable { cards.append(.memory) }
        if AppFeature.monitorDisk.isAvailable { cards.append(.disk) }
        if AppFeature.monitorNetwork.isAvailable { cards.append(.network) }
        if showsBatteryCard {
            cards.append(.battery)
        } else if AppFeature.connectedDevices.isAvailable {
            cards.append(.devices)
        }
        return cards
    }

    private var showsBatteryCard: Bool {
        AppFeature.monitorPower.isAvailable && PowerSampler.hasInternalBattery
    }

    private var showsDevicesRow: Bool {
        showsBatteryCard && AppFeature.connectedDevices.isAvailable
    }

    private var cardGrid: some View {
        let cards = cards
        let rows = stride(from: 0, to: cards.count, by: 2).map { Array(cards[$0..<min($0 + 2, cards.count)]) }
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { pair in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(pair, id: \.self) { card in
                        cardView(card)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        let snapshot = monitor.snapshot
        switch card {
        case .cpu:
            let tint = PanelMetricColor.green(for: colorScheme)
            DashboardCard(title: l10n.s.cpuLabel, symbol: "cpu", tint: tint,
                          badge: snapshot.cpuTemperature.map(temperature),
                          value: percentNumber(snapshot.cpuUsage), unit: "%",
                          footer: Self.loadAverage.map {
                              "\(text.loadAverage) \(String(format: "%.2f", locale: MetricFormat.locale, $0))"
                          } ?? " ",
                          action: { showMetric(.cpu) }) {
                Sparkline(values: snapshot.cpuHistory, color: tint, maxValue: 1, showsZeroBaseline: true)
            }
        case .gpu:
            let tint = PanelMetricColor.orange(for: colorScheme)
            DashboardCard(title: l10n.s.gpuLabel, symbol: MetricDetailKind.gpu.symbolName, tint: tint,
                          badge: snapshot.gpuTemperature.map(temperature),
                          value: percentNumber(snapshot.gpuUsage), unit: "%",
                          footer: gpuLoad(snapshot.gpuUsage),
                          action: { showMetric(.gpu) }) {
                Sparkline(values: snapshot.gpuHistory, color: tint, maxValue: 1, showsZeroBaseline: true)
            }
        case .memory:
            let tint = PanelMetricColor.yellow(for: colorScheme)
            let metric = MonitorMemoryMetric.current
            let used = metric.value(in: snapshot)
            let total = snapshot.memoryTotal
            let fraction = used.flatMap { used in total.map { $0 > 0 ? Double(used) / Double($0) : 0 } }
            DashboardCard(title: l10n.s.memorySection, symbol: "memorychip", tint: tint,
                          badge: pressureLabel(snapshot.memoryPressure),
                          badgeTint: pressureColor(snapshot.memoryPressure),
                          value: percentNumber(fraction), unit: "%",
                          footer: used.flatMap { used in
                              total.map { "\(formatMemory(used)) / \(formatMemory($0))" }
                          } ?? " ",
                          action: { showMetric(.memory) }) {
                Sparkline(values: metric.history(in: snapshot), color: tint, maxValue: 1, showsZeroBaseline: true)
            }
        case .disk:
            let disk = primaryDisk
            let (value, unit) = Self.split(disk.map { MetricFormat.diskBytes($0.freeBytes) } ?? "-")
            DashboardCard(title: text.freeSpace, symbol: "internaldrive", tint: .accentColor,
                          badge: disk.map { MetricFormat.diskBytes($0.totalBytes) },
                          value: value, unit: unit,
                          footer: disk.map {
                              "\(l10n.s.diskUsed) \(MetricFormat.diskBytes($0.usedBytes)) · \(MetricFormat.percent($0.usedFraction))"
                          } ?? l10n.s.diskNoDisks,
                          action: { showMetric(.disk) }) {
                CapacityBar(fraction: disk?.usedFraction ?? 0, tint: .accentColor)
            }
        case .network:
            let tint = PanelMetricColor.cyan(for: colorScheme)
            let (value, unit) = Self.split(snapshot.netDownBytesPerSec.map { MetricFormat.networkRate($0) } ?? "-")
            DashboardCard(title: l10n.s.networkSection, symbol: "network", tint: tint,
                          value: value, unit: unit,
                          footer: "\(l10n.s.networkUpload) \(snapshot.netUpBytesPerSec.map { MetricFormat.networkRate($0) } ?? "-")",
                          action: { showMetric(.network) }) {
                Sparkline(values: snapshot.netDownHistory, color: tint, showsZeroBaseline: true)
            }
        case .battery:
            let power = snapshot.power
            let charge = power?.chargePercent
            let tint = chargeTint(charge)
            DashboardCard(title: l10n.s.batteryLabel, symbol: batterySymbol(power), tint: tint,
                          badge: power?.healthPercent.map { "\(text.health) \(Int($0.rounded()))%" },
                          value: charge.map(String.init) ?? "-", unit: "%",
                          footer: batteryStatus(power),
                          action: { showMetric(.battery) }) {
                CapacityBar(fraction: Double(charge ?? 0) / 100, tint: tint)
            }
        case .devices:
            let strings = FeatureStrings.connectedDevices(l10n.language)
            let devices = snapshot.connectedDevices
            DashboardCard(title: strings.title, symbol: "cable.connector", tint: .accentColor,
                          value: "\(devices.count)",
                          footer: devices.isEmpty ? strings.noDevices
                              : devices.map(\.name).joined(separator: ", "),
                          action: { showMetric(.connectedDevices) }) {
                Color.clear
            }
        }
    }

    private var devicesRow: some View {
        let strings = FeatureStrings.connectedDevices(l10n.language)
        let count = monitor.snapshot.connectedDevices.count
        return Button { showMetric(.connectedDevices) } label: {
            HStack(spacing: 8) {
                Label(strings.title, systemImage: "cable.connector")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .panelCard(padded: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.title)
        .accessibilityValue(strings.formattedCount(count))
    }

    // MARK: Top processes

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(text.topProcesses)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                sortButton(.memory, title: l10n.s.memorySection)
                    .frame(width: DashboardProcessRow.memoryWidth, alignment: .trailing)
                sortButton(.cpu, title: l10n.s.cpuLabel)
                    .frame(width: DashboardProcessRow.cpuWidth, alignment: .trailing)
                ActivityMonitorButton()
                    .frame(width: DashboardProcessRow.actionWidth)
            }
            let rows = processRows
            if rows.isEmpty {
                Text(l10n.s.breakdownMeasuring)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(rows, id: \.row.id) { entry in
                    DashboardProcessRow(row: entry.row,
                                        memory: entry.memory.map { formatMemory(UInt64($0)) } ?? "-",
                                        cpu: entry.cpu.map {
                                            String(format: "%.1f", locale: MetricFormat.locale, $0)
                                        } ?? "-")
                }
            }
        }
        .panelCard()
    }

    private func sortButton(_ kind: BreakdownKind, title: String) -> some View {
        let active = processSort == kind
        return Button {
            processSort = kind
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The sorted column decides which apps are listed; the other column is
    /// looked up by app, so an app outside its top rows shows a dash.
    private var processRows: [(row: ProcessUsage, memory: Double?, cpu: Double?)] {
        let memory = Dictionary(memoryRows.map { ($0.pid, $0.value) }, uniquingKeysWith: { first, _ in first })
        let cpu = Dictionary(cpuRows.map { ($0.pid, $0.value) }, uniquingKeysWith: { first, _ in first })
        let leading = processSort == .cpu ? cpuRows : memoryRows
        return leading.prefix(processLimit).map { row in
            (row: row, memory: memory[row.pid], cpu: cpu[row.pid] ?? (processSort == .memory && !cpuRows.isEmpty ? 0 : nil))
        }
    }

    private func refreshProcesses(force: Bool) {
        let interval = TimeInterval(Defaults.sanitizedMonitorInterval(monitorInterval))
        guard !processRefreshInFlight,
              force || Date().timeIntervalSince(lastProcessRefresh) >= interval * 0.8 else { return }
        lastProcessRefresh = Date()
        processRefreshInFlight = true
        let cpuPercentage = monitor.snapshot.cpuUsage.map { $0 * 100 }
        let limit = processSampleLimit
        DispatchQueue.global(qos: .utility).async {
            let memory = ProcessUsageService.shared.top(.memory, limit: limit)
            let cpu = ProcessUsageService.shared.top(.cpu, limit: limit,
                                                     sampleInterval: interval,
                                                     cpuPercentage: cpuPercentage)
            DispatchQueue.main.async {
                processRefreshInFlight = false
                if !memory.isEmpty || memoryRows.isEmpty { memoryRows = memory }
                if !cpu.isEmpty || cpuRows.isEmpty { cpuRows = cpu }
            }
        }
    }

    // MARK: Values

    private var primaryDisk: DiskDeviceReading? {
        let disks = monitor.snapshot.disk?.devices ?? []
        return disks.first { $0.mountPath == "/" }
            ?? disks.first { $0.isInternal }
            ?? disks.first
    }

    private static var loadAverage: Double? {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) >= 1 ? loads[0] : nil
    }

    private func percentNumber(_ fraction: Double?) -> String {
        fraction.map { String(format: "%.0f", locale: MetricFormat.locale, min(1, max(0, $0)) * 100) } ?? "-"
    }

    private func temperature(_ celsius: Double) -> String {
        MetricFormat.temperature(celsius, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius)
    }

    private func gpuLoad(_ fraction: Double?) -> String {
        guard let fraction else { return " " }
        switch fraction {
        case ..<0.05: return text.gpuIdle
        case ..<0.3: return text.gpuLight
        case ..<0.7: return text.gpuModerate
        default: return text.gpuHeavy
        }
    }

    private func pressureLabel(_ pressure: MemoryPressure) -> String? {
        switch pressure {
        case .normal: return l10n.s.pressureNormal
        case .warning: return l10n.s.pressureWarning
        case .critical: return l10n.s.pressureCritical
        case .unknown: return nil
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color? {
        switch pressure {
        case .normal: return PanelMetricColor.green(for: colorScheme)
        case .warning: return PanelMetricColor.yellow(for: colorScheme)
        case .critical: return PanelMetricColor.red(for: colorScheme)
        case .unknown: return nil
        }
    }

    private func chargeTint(_ charge: Int?) -> Color {
        guard let charge else { return .secondary }
        if charge < 20 { return PanelMetricColor.red(for: colorScheme) }
        if charge < 40 { return PanelMetricColor.yellow(for: colorScheme) }
        return PanelMetricColor.green(for: colorScheme)
    }

    private func batteryState(_ power: PowerReading?) -> BatteryPowerSupport.State {
        BatteryPowerSupport.state(isCharging: power?.isCharging ?? false,
                                  externalConnected: power?.externalConnected ?? false,
                                  hasBattery: power?.hasBattery ?? true)
    }

    private func batterySymbol(_ power: PowerReading?) -> String {
        switch batteryState(power) {
        case .charging, .externalPower: return "battery.100.bolt"
        case .onBattery, .unavailable: return "battery.75"
        }
    }

    private func batteryStatus(_ power: PowerReading?) -> String {
        switch batteryState(power) {
        case .charging: return l10n.s.powerCharging
        case .externalPower: return l10n.s.powerPluggedIn
        case .onBattery:
            if let remaining = power?.timeRemainingSeconds.flatMap(BatteryTimeSupport.formatted) {
                return "\(l10n.s.powerOnBattery) · \(remaining)"
            }
            return l10n.s.powerOnBattery
        case .unavailable: return " "
        }
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    private func formatMemory(_ bytes: UInt64) -> String {
        Self.memoryFormatter.string(fromByteCount: Int64(bytes))
    }

    /// "552 GB" into the number the card enlarges and the unit beside it.
    private static func split(_ text: String) -> (String, String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}

/// One resource: its name and a status tag, the reading large, a graph or a
/// fill, and one line of context. Every card has the same rows, so two side
/// by side come out the same height.
private struct DashboardCard<Graph: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var badge: String? = nil
    var badgeTint: Color? = nil
    let value: String
    var unit = ""
    let footer: String
    let action: () -> Void
    @ViewBuilder let graph: () -> Graph
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var inNotch
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(badgeTint ?? .secondary)
                            .padding(.horizontal, 5)
                            .frame(height: 17)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill((badgeTint ?? .primary).opacity(badgeTint == nil ? 0.07 : 0.14)))
                    }
                }
                .frame(height: 18)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                graph()
                    .frame(height: 24)
                Text(footer)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .panelCard()
            .overlay {
                if !inNotch {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.035 : 0))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(title)
        .accessibilityValue(unit.isEmpty ? value : "\(value) \(unit)")
        .accessibilityHint(footer)
    }
}

/// A capacity reading as a thick bar centred in the graph's place.
private struct CapacityBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(6, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
        .frame(maxHeight: .infinity)
    }
}

/// An app with its memory and CPU columns. Clicking it brings the app
/// forward; the trailing menu (or a right click) force quits it when Kill
/// Process is installed.
private struct DashboardProcessRow: View {
    static let memoryWidth: CGFloat = 64
    static let cpuWidth: CGFloat = 36
    static let actionWidth: CGFloat = 18

    let row: ProcessUsage
    let memory: String
    let cpu: String
    @Environment(\.notchPresentation) private var inNotch
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if ProcessUsageService.shared.canActivate(row) {
                    Button { ProcessUsageService.shared.activate(row) } label: { name }
                        .buttonStyle(.plain)
                } else {
                    name
                }
            }
            Text(memory)
                .frame(width: Self.memoryWidth, alignment: .trailing)
            Text(cpu)
                .frame(width: Self.cpuWidth, alignment: .trailing)
            actions
                .frame(width: Self.actionWidth)
        }
        .font(.system(size: 10.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .contextMenu {
            if canKill { forceQuitButton }
        }
        .help(row.name)
    }

    private var name: some View {
        HStack(spacing: 7) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: 15, height: 15)
            Text(row.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var canKill: Bool { AppFeature.killProcess.isAvailable }

    @ViewBuilder
    private var actions: some View {
        // The island hosts no AppKit pull-down; it keeps the right click.
        if canKill, !inNotch {
            Menu {
                forceQuitButton
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var forceQuitButton: some View {
        Button(FeatureStrings.killProcess(l10n.language).forceKillButton, role: .destructive) {
            ProcessUsageService.shared.confirmForceQuit(row, inNotch: inNotch)
        }
        .disabled(!ProcessUsageService.shared.canForceQuit(row))
    }
}
