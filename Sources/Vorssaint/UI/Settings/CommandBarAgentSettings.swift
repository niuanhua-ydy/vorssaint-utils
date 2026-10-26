// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The terminal agents open in, and each agent's switch and command line.
/// Agents whose program was not found sit folded away, still editable, since
/// a command pointing somewhere else is how one becomes found.
struct CommandBarAgentSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.commandBarAgentTerminal) private var terminal = ""
    @AppStorage(DefaultsKey.commandBarAgentCommands) private var commandsRaw = ""
    @AppStorage(DefaultsKey.commandBarAgentDisabled) private var disabledRaw = ""
    /// Bumped when a look for the agents' programs found something new.
    @State private var detection = 0
    @State private var showsMissing = false

    private var text: CommandBarAgentStrings { .strings(l10n.language) }

    var body: some View {
        let installed = CommandBarAgents.installedTerminals()
        let _ = detection
        let found = CommandBarAgentsSupport.presets.filter { CommandBarAgents.installedPath(for: $0) != nil }
        let missing = CommandBarAgentsSupport.presets.filter { CommandBarAgents.installedPath(for: $0) == nil }
        Section {
            Picker(text.terminal, selection: $terminal) {
                let automatic = CommandBarAgentsSupport.terminal(preference: "", installed: Set(installed))
                Text(automatic.map { "\(text.automatic) (\($0.name))" } ?? text.automatic).tag("")
                ForEach(installed) { Text($0.name).tag($0.rawValue) }
            }
            if installed.isEmpty {
                Text(text.noTerminal).font(.caption).foregroundStyle(.orange)
            }
            ForEach(found) { agent in agentRow(agent, found: true) }
            if !missing.isEmpty {
                DisclosureGroup("\(text.notFound) · \(missing.count)", isExpanded: $showsMissing) {
                    ForEach(missing) { agent in agentRow(agent, found: false) }
                }
            }
            Text(text.caption).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(text.sourceTitle)
        }
        .onAppear { look(force: true) }
        .onChange(of: terminal) { _, _ in CommandBarService.shared.syncWithPreferences() }
    }

    private func agentRow(_ agent: CommandBarAgent, found: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding {
                !CommandBarAgentsSupport.disabledAgents(from: disabledRaw).contains(agent.id)
            } set: { enabled in
                disabledRaw = CommandBarAgentsSupport.settingAgent(agent.id, enabled: enabled, disabledRaw: disabledRaw)
                CommandBarService.shared.syncWithPreferences()
            }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                    Text(CommandBarAgents.installedPath(for: agent) ?? text.notFound)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .disabled(!found)
            Spacer()
            TextField("", text: Binding {
                CommandBarAgentsSupport.command(for: agent, in: CommandBarAgentsSupport.decodeCommands(commandsRaw))
            } set: { value in
                commandsRaw = CommandBarAgentsSupport.encodeCommands(CommandBarAgentsSupport.settingCommand(
                    value, for: agent, in: CommandBarAgentsSupport.decodeCommands(commandsRaw)))
            }, prompt: Text(agent.command))
            .font(.system(.body, design: .monospaced))
            .frame(width: 220)
            .onSubmit { look(force: true) }
        }
    }

    private func look(force: Bool) {
        CommandBarAgents.refresh(force: force) {
            detection += 1
            CommandBarService.shared.syncWithPreferences()
        }
    }
}
