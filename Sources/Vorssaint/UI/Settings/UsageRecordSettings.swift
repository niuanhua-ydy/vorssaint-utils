// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct UsageRecordSettingsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var app = AppUsageRecorder.shared
    @ObservedObject private var agents = AgentUsageHistoryStore.shared
    @State private var confirmingApp = false
    @State private var confirmingAgents = false

    private var text: UsageRecordStrings { .strings(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(text.hubDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    UsageRecordWindow.shared.show()
                } label: {
                    Label(text.open, systemImage: AppFeature.usageRecord.symbolName)
                }
            }
            Section(text.appTab) {
                Text(text.appNote).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(text.clearApp, role: .destructive) { confirmingApp = true }
                    .disabled(app.history.isEmpty)
            }
            Section(text.aiTab) {
                Text(text.note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(text.clearAgents, role: .destructive) { confirmingAgents = true }
                    .disabled(agents.history.isEmpty)
            }
        }
        .formStyle(.grouped)
        .alert(text.clearAppQuestion, isPresented: $confirmingApp) {
            Button(text.cancel, role: .cancel) {}
            Button(text.clearApp.replacingOccurrences(of: "…", with: ""), role: .destructive) { app.clear() }
        } message: {
            Text(text.clearAppDetail)
        }
        .alert(text.clearAgentsQuestion, isPresented: $confirmingAgents) {
            Button(text.cancel, role: .cancel) {}
            Button(text.clearAgents.replacingOccurrences(of: "…", with: ""), role: .destructive) { agents.clear() }
        } message: {
            Text(text.clearAgentsDetail)
        }
    }
}
