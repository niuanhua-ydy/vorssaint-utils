// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import ClipNoteCore

struct CommandBarTranslationSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var provider: AIProvider = .openAIChat
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var keyLoaded = false
    @State private var expanded = false
    @State private var message: String?
    private var text: CommandBarTranslationStrings { .strings(l10n.language) }
    private var labels: ClipNoteSettingsStrings { FeatureStrings.clipNoteSettings(l10n.language) }
    private var common: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        Section {
            Text(text.privacy).font(.caption).foregroundStyle(.secondary)
            if #unavailable(macOS 15) {
                Text(text.systemRequirement).font(.caption).foregroundStyle(.orange)
            }
            DisclosureGroup("AI · " + text.title, isExpanded: $expanded) {
                Picker(labels.aiProvider, selection: $provider) {
                    ForEach(AIProvider.allCases) { Text(common.providerTitle($0)).tag($0) }
                }
                TextField(labels.aiBaseURL, text: $baseURL, prompt: Text("https://…/v1"))
                TextField(labels.aiModel, text: $model)
                SecureField(labels.aiAPIKey, text: $apiKey)
                    .disabled(!keyLoaded)
                Text(text.configure).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(common.save) { save() }
                        .disabled(!keyLoaded)
                }
            }
        } header: {
            Text(text.title)
        }
        .onAppear {
            provider = CommandBarTranslationSettings.provider
            baseURL = UserDefaults.standard.string(forKey: DefaultsKey.translationAIBaseURL) ?? ""
            model = UserDefaults.standard.string(forKey: DefaultsKey.translationAIModel) ?? ""
        }
        .onChange(of: expanded) { _, value in
            guard value, !keyLoaded else { return }
            do {
                apiKey = try CommandBarTranslationSettings.key() ?? ""
                keyLoaded = true
            } catch { message = error.localizedDescription }
        }
        .onChange(of: provider) { _, _ in message = nil }
        .onChange(of: baseURL) { _, _ in message = nil }
        .onChange(of: model) { _, _ in message = nil }
        .onChange(of: apiKey) { _, _ in message = nil }
    }

    private func save() {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty values deliberately clear the configuration and key.
        guard url.isEmpty || CommandBarTranslationSettings.validEndpoint(url) else {
            message = text.configure
            return
        }
        do {
            try CommandBarTranslationSettings.saveKey(apiKey)
            UserDefaults.standard.set(provider.rawValue, forKey: DefaultsKey.translationAIProvider)
            UserDefaults.standard.set(url, forKey: DefaultsKey.translationAIBaseURL)
            UserDefaults.standard.set(name, forKey: DefaultsKey.translationAIModel)
            message = common.ok
        } catch { message = common.saveFailed + " · " + error.localizedDescription }
    }
}
