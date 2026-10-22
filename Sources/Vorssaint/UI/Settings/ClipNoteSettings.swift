// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

/// ClipNote's Settings page: the switch, then its areas as tabs. Paste as
/// plain text lives here too, the one other clipboard tool this build keeps.
struct ClipNoteSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ClipNoteService.shared
    @ObservedObject private var preferences = ClipNotePreferences.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @AppStorage(DefaultsKey.clipNoteEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipNoteStackShortcutEnabled) private var stackShortcutEnabled = true
    @AppStorage(DefaultsKey.pastePlainEnabled) private var pastePlainEnabled = false

    private var text: ClipNoteSettingsStrings { FeatureStrings.clipNoteSettings(l10n.language) }
    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        Form {
            if AppFeature.clipNote.isAvailable {
                clipNoteSections
            } else {
                plainPasteSection
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var clipNoteSections: some View {
        Section {
            Toggle(text.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in ClipNoteService.shared.syncWithPreferences() }
            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.localNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let error = service.storeError {
                Text(String(format: text.storeErrorFormat, error))
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if service.isRunning {
                Label(preferences.isPaused ? strings.pausedHelp : text.active,
                      systemImage: preferences.isPaused ? "pause.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(preferences.isPaused ? .orange : .green)
            }
        }

        Section {
            Picker("", selection: $service.settingsTab) {
                ForEach(ClipNoteSettingsTab.allCases) { tab in
                    Label(text.tabTitle(tab), systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        switch service.settingsTab {
        case .general: generalTab
        case .privacy: ClipNotePrivacySettings(preferences: preferences, text: text, strings: strings)
        case .storage:
            if let parts = service.parts {
                ClipNoteStorageSettings(store: parts.store, preferences: preferences, text: text, strings: strings)
            } else {
                turnOnFirst
            }
        case .ai: ClipNoteAISettings(preferences: preferences, text: text)
        case .sync:
            if let parts = service.parts {
                ClipNoteSyncSettings(sync: parts.sync, preferences: preferences, text: text, strings: strings)
            } else {
                turnOnFirst
            }
        case .backup:
            if let parts = service.parts {
                ClipNoteBackupSettings(backup: parts.backup, pasteImport: parts.pasteImport,
                                       preferences: preferences, text: text, strings: strings)
            } else {
                turnOnFirst
            }
        }
    }

    private var turnOnFirst: some View {
        Section {
            Text(text.turnOnFirst)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalTab: some View {
        Section(text.shortcutsHeader) {
            ShortcutPreferenceRow(role: .clipNote, isEnabled: enabled) {
                ClipNoteService.shared.syncHotkeys()
            }
            if enabled, service.panelShortcutFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle(text.stackShortcut, isOn: $stackShortcutEnabled)
                .onChange(of: stackShortcutEnabled) { _, _ in ClipNoteService.shared.syncHotkeys() }
                .disabled(!enabled)
            ShortcutPreferenceRow(role: .clipNoteStack, isEnabled: enabled && stackShortcutEnabled) {
                ClipNoteService.shared.syncHotkeys()
            }
            Text(text.stackCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled, stackShortcutEnabled, service.stackShortcutFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Toggle(strings.autoPaste, isOn: $preferences.autoPaste)
            Text(text.autoPasteCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !permissions.accessibility {
                Text(text.accessibilityCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PermissionRow(kind: .accessibility)
            }
        }

        Section {
            Toggle(isOn: $preferences.ocrEnabled) {
                ClipNoteRowLabel(text.ocr, text.ocrCaption)
            }
            Toggle(isOn: $preferences.ocrBackfillEnabled) {
                ClipNoteRowLabel(text.ocrBackfill, text.ocrBackfillCaption)
            }
            if let parts = service.parts {
                ClipNoteOCRProgressRow(backfill: parts.ocrBackfill, enabled: preferences.ocrBackfillEnabled,
                                       text: text)
            }
        }

        Section(text.panelKeysHeader) {
            ForEach(text.panelKeys, id: \.keys) { row in
                LabeledContent(row.action) {
                    Text(row.keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }

        plainPasteSection
    }

    @ViewBuilder
    private var plainPasteSection: some View {
        if AppFeature.pastePlain.isAvailable {
            Section {
                Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                    .onChange(of: pastePlainEnabled) { _, _ in
                        PastePlainService.shared.syncWithPreferences()
                    }
                Text(l10n.s.pastePlainCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutPreferenceRow(role: .pastePlain, isEnabled: pastePlainEnabled) {
                    PastePlainService.shared.syncWithPreferences()
                }
                if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if pastePlainEnabled, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            } header: {
                Text(l10n.s.pastePlainName)
            }
            .settingsFormSectionAnchor(.pastePlain)
        }
    }
}

/// A title over grey help text, the way ClipNote labels its settings.
private struct ClipNoteRowLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy

private struct ClipNotePrivacySettings: View {
    @ObservedObject var preferences: ClipNotePreferences
    let text: ClipNoteSettingsStrings
    let strings: ClipNoteStrings
    @State private var selection: ClipNoteIgnoredApp.ID?

    var body: some View {
        Section {
            Toggle(isOn: $preferences.isPaused) {
                ClipNoteRowLabel(strings.pauseRecording, text.pauseCaption)
            }
            Toggle(isOn: $preferences.skipConcealed) {
                ClipNoteRowLabel(text.skipConcealed, text.skipConcealedCaption)
            }
        }
        Section {
            ForEach(preferences.ignoredApps) { app in
                HStack(spacing: 12) {
                    if let icon = ClipNoteAppIcons.icon(for: app.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 18)).frame(width: 24, height: 24)
                    }
                    Text(displayName(of: app))
                    Spacer()
                }
                .contentShape(Rectangle())
                .listRowBackground(selection == app.id ? Color.accentColor.opacity(0.18) : Color.clear)
                .onTapGesture { selection = app.id }
            }
            HStack(spacing: 0) {
                Button(action: addApp) {
                    Image(systemName: "plus").frame(width: 26, height: 20).contentShape(Rectangle())
                }
                Divider().frame(height: 14)
                Button {
                    preferences.ignoredApps.removeAll { $0.id == selection }
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 26, height: 20).contentShape(Rectangle())
                }
                .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } header: {
            ClipNoteRowLabel(text.ignoredAppsHeader, text.ignoredAppsCaption)
        }
    }

    /// The installed app's own name in the current language, or the saved one.
    private func displayName(of app: ClipNoteIgnoredApp) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return app.name }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !preferences.ignoredApps.contains(where: { $0.bundleID == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            preferences.ignoredApps.append(ClipNoteIgnoredApp(bundleID: id, name: name))
        }
    }
}

// MARK: - Storage

private struct ClipNoteStorageSettings: View {
    let store: ClipStore
    @ObservedObject var preferences: ClipNotePreferences
    let text: ClipNoteSettingsStrings
    let strings: ClipNoteStrings
    @State private var count = 0

    var body: some View {
        Section {
            Picker(selection: $preferences.retentionDays) {
                Text(text.retentionDay).tag(1)
                Text(text.retentionWeek).tag(7)
                Text(text.retentionMonth).tag(30)
                Text(text.retentionThreeMonths).tag(90)
                Text(text.retentionYear).tag(365)
                Text(text.forever).tag(0)
            } label: {
                ClipNoteRowLabel(text.retention, text.retentionCaption)
            }
            Picker(selection: $preferences.maxItems) {
                ForEach([500, 1000, 5000, 20000], id: \.self) { value in
                    Text(String(format: text.itemsFormat, value)).tag(value)
                }
                Text(strings.unlimited).tag(0)
            } label: {
                ClipNoteRowLabel(text.maxItems, text.maxItemsCaption)
            }
            Picker(selection: $preferences.maxCaptureMB) {
                ForEach([5, 10, 20, 50, 100, 200], id: \.self) { value in
                    Text("\(value) MB").tag(value)
                }
                Text(strings.unlimited).tag(0)
            } label: {
                ClipNoteRowLabel(text.maxCapture, text.maxCaptureCaption)
            }
        }
        Section {
            LabeledContent(text.itemCount) {
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent {
                Button(strings.revealInFinder) { NSWorkspace.shared.open(store.directory) }
            } label: {
                ClipNoteRowLabel(text.dataLocation,
                                 store.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            }
            HStack {
                Button(text.applyRetention) {
                    store.applyRetention(maxAgeDays: preferences.retentionDays, maxItems: preferences.maxItems)
                    count = store.count()
                }
                Spacer()
                Button(strings.clearHistoryEllipsis, role: .destructive) {
                    ClipNoteService.shared.parts?.panel.runClearHistoryAlert()
                    count = store.count()
                }
            }
        }
        .onAppear { count = store.count() }
    }
}

/// How far background recognition has got.
/// The backfill's progress, once there are images to count.
private struct ClipNoteOCRProgressRow: View {
    @ObservedObject var backfill: ClipNoteOCRBackfill
    let enabled: Bool
    let text: ClipNoteSettingsStrings

    var body: some View {
        if backfill.stats.total > 0 {
            LabeledContent {
                ClipNoteOCRProgress(backfill: backfill, enabled: enabled, text: text)
            } label: {
                Text(text.ocrProgress)
            }
        }
    }
}

private struct ClipNoteOCRProgress: View {
    @ObservedObject var backfill: ClipNoteOCRBackfill
    let enabled: Bool
    let text: ClipNoteSettingsStrings

    var body: some View {
        let stats = backfill.stats
        let finished = stats.done + stats.failed
        VStack(alignment: .trailing, spacing: 4) {
            if stats.pending == 0 {
                Label(String(format: text.ocrAllDoneFormat, stats.total), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: Double(finished), total: Double(max(stats.total, 1)))
                    .frame(width: 160)
                Text(String(format: text.ocrProgressFormat, finished, stats.total, stats.pending, statusText))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if stats.failed > 0 {
                Text(String(format: text.ocrFailedFormat, stats.failed))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }

    private var statusText: String {
        if !enabled { return text.ocrPaused }
        if backfill.isWaitingForPower { return text.ocrLowPower }
        return backfill.isRunning ? text.ocrRunning : text.ocrWaiting
    }
}

// MARK: - AI

private struct ClipNoteAISettings: View {
    @ObservedObject var preferences: ClipNotePreferences
    let text: ClipNoteSettingsStrings
    @ObservedObject private var l10n = L10n.shared
    @State private var provider: AIProvider = .anthropic
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var testMessage: (ok: Bool, text: String)?
    @State private var testing = false

    /// Common models; any other can be typed.
    private var presets: [String] {
        switch provider {
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        case .openAIResponses, .openAIChat: return []
        }
    }

    var body: some View {
        Group {
            Section {
                Picker(selection: $provider) {
                    ForEach(AIProvider.allCases) {
                        Text(FeatureStrings.clipNote(l10n.language).providerTitle($0)).tag($0)
                    }
                } label: {
                    ClipNoteRowLabel(text.aiProvider, providerHint)
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { old, new in
                    // Loading the saved format on appear fires this too; nothing to switch then.
                    guard new != preferences.aiProvider else { return }
                    save(old)
                    preferences.aiProvider = new
                    load(new)
                }
            }

            Section {
                TextField(text.aiBaseURL, text: $baseURL, prompt: Text(urlPlaceholder))
                SecureField(text.aiAPIKey, text: $apiKey)
                HStack {
                    TextField(text.aiModel, text: $model, prompt: Text(modelPlaceholder))
                    if !presets.isEmpty {
                        Menu {
                            ForEach(presets, id: \.self) { preset in Button(preset) { model = preset } }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(text.aiModelPresetsHelp)
                    }
                }
                Picker(selection: $preferences.aiEffort) {
                    ForEach(AIEffort.allCases) { Text(text.effortTitle($0)).tag($0) }
                } label: {
                    ClipNoteRowLabel(text.aiEffort, text.aiEffortCaption)
                }
                HStack {
                    Spacer()
                    if let testMessage {
                        Label(testMessage.text, systemImage: testMessage.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testMessage.ok ? .green : .red)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    Button(testing ? text.testing : text.testConnection) { test() }
                        .disabled(testing || apiKey.isEmpty || model.isEmpty || baseURL.isEmpty)
                }
            } header: {
                Text(text.aiServiceHeader)
            } footer: {
                Text(text.aiServiceFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text(text.aiUsage)
                    .font(.caption).foregroundStyle(.secondary)
                Text(text.aiPrivacy)
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(text.aiUsageHeader)
            }
        }
        .onAppear {
            provider = preferences.aiProvider
            load(provider)
        }
        // Every edit saves; switching the format saves the old one before loading the new.
        .onChange(of: baseURL) { _, _ in save(provider) }
        .onChange(of: apiKey) { _, _ in save(provider) }
        .onChange(of: model) { _, _ in save(provider) }
    }

    private var providerHint: String {
        switch provider {
        case .anthropic: return text.aiProviderAnthropicHint
        case .openAIResponses: return text.aiProviderResponsesHint
        case .openAIChat: return text.aiProviderChatHint
        }
    }

    private var urlPlaceholder: String {
        switch provider {
        case .anthropic: return "https://api.anthropic.com"
        case .openAIResponses: return "https://api.openai.com"
        case .openAIChat: return "https://api.deepseek.com"
        }
    }

    private var modelPlaceholder: String {
        switch provider {
        case .anthropic: return "claude-opus-5-5"
        case .openAIResponses: return text.aiModelPlaceholderResponses
        case .openAIChat: return text.aiModelPlaceholderChat
        }
    }

    private func load(_ provider: AIProvider) {
        baseURL = preferences.aiBaseURL(provider)
        model = preferences.aiModel(provider)
        apiKey = ClipNoteKeychain.get(ClipNotePreferences.aiKeyAccount(provider)) ?? ""
        testMessage = nil
    }

    private func save(_ provider: AIProvider) {
        preferences.setAI(provider, baseURL: baseURL, model: model, apiKey: apiKey)
    }

    private func test() {
        save(provider)
        testing = true
        testMessage = nil
        let config = AIConfig(provider: provider, baseURL: baseURL, apiKey: apiKey, model: model,
                              effort: preferences.aiEffort, maxOutputTokens: 2000)
        let strings = FeatureStrings.clipNote(l10n.language)
        let locale = l10n.language.formattingLocale()
        Task {
            let started = Date()
            do {
                var reply = ""
                for try await event in AIClient(config: config).stream(
                    system: "This is a connection test. Reply only with: OK", prompt: "Hello") {
                    switch event {
                    case .text(let delta): reply += delta
                    case .reset: reply = ""
                    case .finished: break
                    }
                }
                let seconds = String(format: "%.1f", locale: locale, Date().timeIntervalSince(started))
                let preview = String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
                testMessage = (true, String(format: text.aiTestSuccessFormat, seconds, preview))
            } catch {
                testMessage = (false, strings.describe(error))
            }
            testing = false
        }
    }
}

// MARK: - Sync

private struct ClipNoteSyncSettings: View {
    @ObservedObject var sync: ClipNoteSyncController
    @ObservedObject var preferences: ClipNotePreferences
    let text: ClipNoteSettingsStrings
    let strings: ClipNoteStrings
    @State private var url = ""
    @State private var user = ""
    @State private var password = ""
    @State private var folder = ""
    @State private var passphrase = ""
    @State private var trustSelfSigned = false
    @State private var testMessage: (ok: Bool, text: String)?
    @State private var testing = false

    private var isPlainHTTP: Bool { url.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") }

    var body: some View {
        Group {
            Section {
                HStack {
                    TextField(text.serverURL, text: $url, prompt: Text("https://dav.jianguoyun.com/dav/"))
                        .onChange(of: url) { _, _ in testMessage = nil }
                    Menu {
                        Button(text.presetJianguoyun) { url = "https://dav.jianguoyun.com/dav/" }
                        Button(text.presetSynology) { url = "https://192.168.1.10:5006/" }
                        Button(text.presetQNAP) { url = "https://192.168.1.10:5001/" }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(text.presetsHelp)
                }
                TextField(text.account, text: $user)
                SecureField(text.password, text: $password)
                TextField(text.syncFolder, text: $folder)
                Toggle(isOn: $trustSelfSigned) {
                    ClipNoteRowLabel(text.trustSelfSigned, text.trustSelfSignedCaption)
                }
                HStack {
                    Spacer()
                    if let testMessage {
                        Label(testMessage.text, systemImage: testMessage.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testMessage.ok ? .green : .red)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    Button(testing ? text.testing : text.testConnection) { test() }
                        .disabled(testing || user.isEmpty || password.isEmpty || url.isEmpty)
                }
            } header: {
                Text(text.webdavHeader)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.webdavFooter)
                    if isPlainHTTP {
                        Text(text.plainHTTPWarning).foregroundStyle(.orange)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SecureField(text.passphrase, text: $passphrase)
                Toggle(text.syncImages, isOn: $preferences.syncImages)
                    .onChange(of: preferences.syncImages) { _, _ in sync.reconfigure() }
                Picker(selection: $preferences.maxSyncItemMB) {
                    ForEach([1, 5, 10, 20], id: \.self) { Text("\($0) MB").tag($0) }
                } label: {
                    ClipNoteRowLabel(text.maxSyncItem, text.maxSyncItemCaption)
                }
                .onChange(of: preferences.maxSyncItemMB) { _, _ in sync.reconfigure() }
            } header: {
                Text(text.syncPrivacyHeader)
            } footer: {
                Text(text.syncPrivacyFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(text.syncToggle, isOn: Binding(
                    get: { preferences.syncEnabled },
                    set: { enabled in
                        save()
                        preferences.syncEnabled = enabled
                        sync.reconfigure()
                    }))
                .disabled(user.isEmpty || url.isEmpty
                          || (password.isEmpty && ClipNoteKeychain.get(ClipNoteSyncController.passwordAccount) == nil))
                LabeledContent(text.status) { statusView }
                LabeledContent(text.lastSync) {
                    Text(sync.lastSync.map { ClipNoteFormatters.absolute.string(from: $0) } ?? text.never)
                        .foregroundStyle(.secondary)
                }
                if !sync.lastSummary.isEmpty {
                    LabeledContent(text.result) { Text(sync.lastSummary).foregroundStyle(.secondary).lineLimit(2) }
                }
                HStack {
                    Button(text.saveSettings) {
                        save()
                        sync.reconfigure()
                    }
                    Button(text.syncNow) { sync.syncNow(userInitiated: true) }
                        .disabled(!preferences.syncEnabled || sync.status == .syncing)
                }
            } footer: {
                Text(text.syncFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            url = preferences.webdavURL
            user = preferences.webdavUser
            folder = preferences.webdavFolder
            trustSelfSigned = preferences.webdavTrustSelfSigned
            password = ClipNoteKeychain.get(ClipNoteSyncController.passwordAccount) ?? ""
            passphrase = ClipNoteKeychain.get(ClipNoteSyncController.passphraseAccount) ?? ""
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch sync.status {
        case .off: Text(text.statusOff).foregroundStyle(.secondary)
        case .idle:
            Label(sync.pendingCount > 0 ? String(format: text.pendingFormat, sync.pendingCount) : text.statusOK,
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .syncing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(strings.syncing) }
        case .error(let message): Text(message).foregroundStyle(.red).lineLimit(3).multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        preferences.webdavURL = url.trimmingCharacters(in: .whitespaces)
        preferences.webdavUser = user.trimmingCharacters(in: .whitespaces)
        preferences.webdavFolder = folder.trimmingCharacters(in: .whitespaces)
        preferences.webdavTrustSelfSigned = trustSelfSigned
        ClipNoteKeychain.set(ClipNoteSyncController.passwordAccount, password)
        ClipNoteKeychain.set(ClipNoteSyncController.passphraseAccount, passphrase)
    }

    private func test() {
        testing = true
        testMessage = nil
        let url = url, user = user, password = password, folder = folder, trust = trustSelfSigned
        let strings = self.strings, text = self.text
        Task {
            do {
                try await ClipNoteSyncController.testConnection(url: url, user: user, password: password,
                                                                folder: folder, trustSelfSigned: trust)
                testMessage = (true, text.syncTestOK)
            } catch {
                testMessage = (false, strings.describe(error))
            }
            testing = false
        }
    }
}

// MARK: - Backup

private struct ClipNoteBackupSettings: View {
    @ObservedObject var backup: ClipNoteBackupController
    @ObservedObject var pasteImport: ClipNotePasteImportController
    @ObservedObject var preferences: ClipNotePreferences
    let text: ClipNoteSettingsStrings
    let strings: ClipNoteStrings

    var body: some View {
        Group {
            Section {
                LabeledContent {
                    Button(pasteImport.phase == .idle ? text.startImportEllipsis : strings.importing) {
                        pasteImport.start()
                    }
                } label: {
                    ClipNoteRowLabel(strings.importFromPaste, text.importFromPasteCaption)
                }
            } header: {
                Text(text.migrateHeader)
            }

            Section {
                HStack {
                    Button(text.exportBackup) { backup.exportInteractive() }
                    Button(text.importBackup) { backup.importInteractive() }
                }
                .disabled(backup.isRunning)
            } header: {
                Text(text.transferHeader)
            } footer: {
                Text(text.transferFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(text.autoBackup, isOn: $preferences.autoBackupToICloud)
                    .disabled(ClipNoteBackupController.iCloudDriveRoot == nil)
                    .onChange(of: preferences.autoBackupToICloud) { _, _ in backup.autoBackupIfNeeded() }
                LabeledContent(text.lastBackup) {
                    Text(backup.lastAutoBackup.map { ClipNoteFormatters.absolute.string(from: $0) } ?? text.never)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(text.backUpNow) { backup.backupToICloudNow(interactive: true) }
                        .disabled(backup.isRunning || ClipNoteBackupController.iCloudDriveRoot == nil)
                    Button(text.openBackupFolder) {
                        if let folder = ClipNoteBackupController.autoBackupFolder {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                    .disabled(ClipNoteBackupController.iCloudDriveRoot == nil)
                }
            } header: {
                Text(text.iCloudHeader)
            } footer: {
                Text(ClipNoteBackupController.iCloudDriveRoot == nil
                     ? text.iCloudMissingFooter
                     : String(format: text.iCloudFooterFormat, ClipNoteBackupController.autoBackupKeep))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
