// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The bar's own commands in one table, the counterpart of the app table:
/// a search name, a shortcut, and whether each one asks before it runs.
struct CommandBarCommandsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.commandBarRowShortcuts) private var shortcutsRaw = ""
    @AppStorage(DefaultsKey.commandBarAliases) private var aliasesRaw = ""
    @State private var commands: [CommandBarEntry] = []
    @State private var query = ""
    @State private var message: String?

    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }
    private var strings: CommandBarCommandStrings { FeatureStrings.commandBarCommands(l10n.language) }

    var body: some View {
        let shortcuts = CommandBarRowShortcuts.decode(shortcutsRaw)
        let aliases = CommandBarPreferences.decodeAliases(aliasesRaw)
        let rows = visible(aliases: aliases)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(strings.title)
                    .font(.title2.weight(.semibold))
                Text(strings.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(l10n.s.uninstallerPickerSearch, text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(l10n.s.uninstallerPickerSearch)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.removeButton)
                }
            }
            .padding(7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

            Table(rows) {
                TableColumn(strings.commandColumn) { entry in
                    HStack(spacing: 8) {
                        icon(entry)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(entry.title)
                            .lineLimit(1)
                            .help(entry.title)
                    }
                    .padding(.vertical, 4)
                }
                .width(min: 170, ideal: 240)

                TableColumn(text.appAliasLabel) { entry in
                    CommandBarAppAliasField(entry: entry, savedAlias: aliases[entry.stableKey] ?? "",
                                            text: text) { report($0, for: entry) }
                }
                .width(min: 110, ideal: 150)

                TableColumn(text.appShortcutLabel) { entry in
                    shortcutField(for: entry, shortcut: shortcuts[entry.stableKey])
                }
                .width(180)

                TableColumn(strings.confirmColumn) { entry in
                    Toggle(strings.confirmColumn, isOn: confirmBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(entry.title): \(strings.confirmColumn)")
                }
                .width(min: 60, ideal: 80)
            }
            .tableStyle(.inset)

            HStack(alignment: .center, spacing: 16) {
                Text(message ?? text.shortcutCaptureHint)
                    .font(.caption)
                    .foregroundStyle(message == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(l10n.s.supportIntroDoneButton) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 780, height: 560)
        .onAppear { commands = service.commandRows() }
        .onChange(of: features.revision) { _, _ in
            if !AppFeature.commandBar.isAvailable { dismiss() }
        }
        .onChange(of: l10n.language) { _, _ in
            message = nil
            commands = service.commandRows()
        }
    }

    private func visible(aliases: [String: String]) -> [CommandBarEntry] {
        let query = CommandBarSearch.normalized(query)
        guard !query.isEmpty else { return commands }
        return commands.filter {
            CommandBarSearch.normalized("\($0.title) \($0.keywords) \(aliases[$0.stableKey] ?? "")")
                .contains(query)
        }
    }

    private func confirmBinding(_ entry: CommandBarEntry) -> Binding<Bool> {
        Binding(
            get: { commands.first { $0.stableKey == entry.stableKey }?.confirmationPrompt != nil },
            set: { asks in
                service.setConfirms(asks, for: entry)
                commands = service.commandRows()
            })
    }

    @ViewBuilder
    private func icon(_ entry: CommandBarEntry) -> some View {
        switch entry.icon {
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(.secondary)
        case .appIcon(let path), .filePath(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
        case .clipboardImage, .imageFile, .color:
            EmptyView()
        }
    }

    private func shortcutField(for entry: CommandBarEntry, shortcut: GlobalShortcut?) -> some View {
        HStack(spacing: 4) {
            ShortcutRecorderButton(
                shortcut: shortcut ?? .commandBarDefault,
                isEnabled: AppFeature.commandBar.isAvailable,
                waitingTitle: l10n.s.shortcutPressKeys,
                emptyTitle: shortcut == nil ? text.appShortcutRecord : nil,
                clearAction: { report(service.setRowShortcut(nil, for: entry), for: entry) },
                notCapturedAction: { report(l10n.s.shortcutNotCaptured, for: entry) },
                recordingChanged: { if $0 { message = nil } },
                invalidAction: { report(l10n.s.shortcutInvalid, for: entry) },
                captureAction: { report(service.setRowShortcut($0, for: entry), for: entry) })
                .frame(width: 140)
                .accessibilityLabel("\(entry.title): \(text.appShortcutLabel)")
            if service.refusedRowShortcutKeys.contains(entry.stableKey) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(l10n.s.shortcutUnavailable)
                    .accessibilityLabel(l10n.s.shortcutUnavailable)
            }
            if shortcut != nil {
                Button { report(service.setRowShortcut(nil, for: entry), for: entry) } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help(text.actionShortcutRemove)
                .accessibilityLabel("\(entry.title): \(text.actionShortcutRemove)")
            }
        }
    }

    private func report(_ error: String?, for entry: CommandBarEntry) {
        message = error.map { "\(entry.title): \($0)" }
    }
}
