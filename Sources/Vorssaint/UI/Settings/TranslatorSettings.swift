// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import ClipNoteCore

struct TranslatorSettingsPage: View {
    var body: some View {
        Form { TranslatorSettingsSection() }
            .formStyle(.grouped)
    }
}

struct TranslatorSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var translator = TranslatorService.shared
    @ObservedObject private var capture = ScreenCaptureService.shared
    @AppStorage(DefaultsKey.translatorSelectionShortcutEnabled) private var selectionShortcut = true
    @AppStorage(DefaultsKey.translatorInputShortcutEnabled) private var inputShortcut = true
    @AppStorage(DefaultsKey.translatorScreenshotShortcutEnabled) private var screenshotShortcut = true
    @AppStorage(DefaultsKey.translatorFirstLanguage) private var firstLanguage = TranslatorLanguage.zhHans.rawValue
    @AppStorage(DefaultsKey.translatorSecondLanguage) private var secondLanguage = TranslatorLanguage.en.rawValue
    @AppStorage(DefaultsKey.translatorDisabledEngines) private var disabledEngines = ""
    @State private var provider: AIProvider = .openAIChat
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var keyLoaded = false
    @State private var expanded = false
    @State private var message: String?
    private var text: TranslatorStrings { .strings(l10n.language) }
    private var labels: ClipNoteSettingsStrings { FeatureStrings.clipNoteSettings(l10n.language) }
    private var common: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        Section {
            Text(text.privacy).font(.caption).foregroundStyle(.secondary)
            shortcut(.translatorSelection, isOn: $selectionShortcut,
                     refused: translator.refusedShortcuts.contains(GlobalShortcutRole.translatorSelection.storageKey),
                     sync: TranslatorService.shared.syncWithPreferences)
            shortcut(.translatorInput, isOn: $inputShortcut,
                     refused: translator.refusedShortcuts.contains(GlobalShortcutRole.translatorInput.storageKey),
                     sync: TranslatorService.shared.syncWithPreferences)
            // The translate tool of the capture chooser owns this key.
            shortcut(.translatorScreenshot, isOn: $screenshotShortcut,
                     refused: capture.toolShortcutRegistrationFailures.contains(.translate),
                     sync: ScreenCaptureService.shared.syncWithPreferences)
            Text(text.screenshotCaption).font(.caption).foregroundStyle(.secondary)
            languagePicker(text.firstLanguage, selection: $firstLanguage)
            languagePicker(text.secondLanguage, selection: $secondLanguage)
            Text(text.directionCaption).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(text.title)
        }
        Section {
            engineToggle(.apple, title: text.apple, caption: nil)
            if #unavailable(macOS 15) {
                Text(text.systemRequirement).font(.caption).foregroundStyle(.orange)
            }
            engineToggle(.dictionary, title: text.dictionary, caption: text.dictionaryCaption)
            engineToggle(.ai, title: text.ai, caption: text.aiCaption)
            DisclosureGroup("AI · " + text.settings, isExpanded: $expanded) {
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
            Text(text.services)
        }
        .onAppear {
            provider = TranslatorSettings.provider
            baseURL = UserDefaults.standard.string(forKey: DefaultsKey.translationAIBaseURL) ?? ""
            model = UserDefaults.standard.string(forKey: DefaultsKey.translationAIModel) ?? ""
        }
        .onChange(of: expanded) { _, value in
            guard value, !keyLoaded else { return }
            do {
                apiKey = try TranslatorSettings.key() ?? ""
                keyLoaded = true
            } catch { message = error.localizedDescription }
        }
        .onChange(of: provider) { _, _ in message = nil }
        .onChange(of: baseURL) { _, _ in message = nil }
        .onChange(of: model) { _, _ in message = nil }
        .onChange(of: apiKey) { _, _ in message = nil }
    }

    @ViewBuilder
    private func shortcut(_ role: GlobalShortcutRole, isOn: Binding<Bool>, refused: Bool,
                          sync: @escaping () -> Void) -> some View {
        Toggle(role.title(l10n.s), isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _, _ in sync() }
        ShortcutPreferenceRow(role: role, isEnabled: isOn.wrappedValue, onChange: sync)
        if isOn.wrappedValue, refused {
            Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TranslatorLanguage.allCases.filter { $0 != .auto }, id: \.rawValue) { language in
                Text(language.title(in: locale)).tag(language.rawValue)
            }
        }
    }

    @ViewBuilder
    private func engineToggle(_ engine: TranslatorEngine, title: String, caption: String?) -> some View {
        Toggle(title, isOn: Binding(
            get: { !disabledEngines.split(separator: ",").contains(Substring(engine.rawValue)) },
            set: { TranslatorSettings.setEngine(engine, enabled: $0) }))
        if let caption {
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty values deliberately clear the configuration and key.
        guard url.isEmpty || TranslatorSettings.validEndpoint(url) else {
            message = text.configure
            return
        }
        do {
            try TranslatorSettings.saveKey(apiKey)
            UserDefaults.standard.set(provider.rawValue, forKey: DefaultsKey.translationAIProvider)
            UserDefaults.standard.set(url, forKey: DefaultsKey.translationAIBaseURL)
            UserDefaults.standard.set(name, forKey: DefaultsKey.translationAIModel)
            message = common.ok
        } catch { message = common.saveFailed + " · " + error.localizedDescription }
    }
}
