// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore

/// How merged Paste Stack items are joined.
enum ClipNoteStackSeparator: String, CaseIterable, Identifiable {
    case newline, blankLine, space, comma, none

    var id: String { rawValue }

    func title(_ strings: ClipNoteStrings) -> String {
        switch self {
        case .newline: return strings.separatorNewline
        case .blankLine: return strings.separatorBlankLine
        case .space: return strings.separatorSpace
        case .comma: return strings.separatorComma
        case .none: return strings.separatorNone
        }
    }

    var string: String {
        switch self {
        case .newline: return "\n"
        case .blankLine: return "\n\n"
        case .space: return " "
        case .comma: return "，"
        case .none: return ""
        }
    }
}

struct ClipNoteIgnoredApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// ClipNote's settings, read and written through UserDefaults. The panel and
/// Paste Stack shortcuts are not here: they are shortcut roles, so the
/// Shortcuts page, conflict checks and recording all treat them like every
/// other Vorssaint shortcut.
@MainActor
final class ClipNotePreferences: ObservableObject {
    static let shared = ClipNotePreferences()

    private let defaults = UserDefaults.standard

    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: DefaultsKey.clipNotePaused) } }
    @Published var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: DefaultsKey.clipNoteAutoPaste) } }
    @Published var deleteNeedsCommand: Bool {
        didSet { defaults.set(deleteNeedsCommand, forKey: DefaultsKey.clipNoteDeleteNeedsCommand) }
    }
    @Published var skipConcealed: Bool {
        didSet { defaults.set(skipConcealed, forKey: DefaultsKey.clipNoteSkipConcealed) }
    }
    @Published var ocrEnabled: Bool { didSet { defaults.set(ocrEnabled, forKey: DefaultsKey.clipNoteOCR) } }
    @Published var ocrBackfillEnabled: Bool {
        didSet { defaults.set(ocrBackfillEnabled, forKey: DefaultsKey.clipNoteOCRBackfill) }
    }
    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: DefaultsKey.clipNoteRetentionDays) }
    }
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: DefaultsKey.clipNoteMaxItems) } }
    @Published var ignoredApps: [ClipNoteIgnoredApp] {
        didSet { save(ignoredApps, forKey: DefaultsKey.clipNoteIgnoredApps) }
    }
    @Published var stackLIFO: Bool { didSet { defaults.set(stackLIFO, forKey: DefaultsKey.clipNoteStackLIFO) } }
    @Published var stackSeparator: ClipNoteStackSeparator {
        didSet { defaults.set(stackSeparator.rawValue, forKey: DefaultsKey.clipNoteStackSeparator) }
    }
    @Published var autoBackupToICloud: Bool {
        didSet { defaults.set(autoBackupToICloud, forKey: DefaultsKey.clipNoteAutoBackup) }
    }
    @Published var syncEnabled: Bool { didSet { defaults.set(syncEnabled, forKey: DefaultsKey.clipNoteSyncEnabled) } }
    @Published var webdavTrustSelfSigned: Bool {
        didSet { defaults.set(webdavTrustSelfSigned, forKey: DefaultsKey.clipNoteWebDAVTrustSelfSigned) }
    }
    @Published var webdavURL: String { didSet { defaults.set(webdavURL, forKey: DefaultsKey.clipNoteWebDAVURL) } }
    @Published var webdavUser: String { didSet { defaults.set(webdavUser, forKey: DefaultsKey.clipNoteWebDAVUser) } }
    @Published var webdavFolder: String {
        didSet { defaults.set(webdavFolder, forKey: DefaultsKey.clipNoteWebDAVFolder) }
    }
    @Published var syncImages: Bool { didSet { defaults.set(syncImages, forKey: DefaultsKey.clipNoteSyncImages) } }
    @Published var maxCaptureMB: Int { didSet { defaults.set(maxCaptureMB, forKey: DefaultsKey.clipNoteMaxCaptureMB) } }
    @Published var maxSyncItemMB: Int {
        didSet { defaults.set(maxSyncItemMB, forKey: DefaultsKey.clipNoteMaxSyncItemMB) }
    }
    @Published var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: DefaultsKey.clipNoteAIProvider) }
    }
    @Published var aiEffort: AIEffort { didSet { defaults.set(aiEffort.rawValue, forKey: DefaultsKey.clipNoteAIEffort) } }

    var ignoredBundleIDs: Set<String> { Set(ignoredApps.map(\.bundleID)) }

    static let defaultIgnoredApps = [
        ClipNoteIgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        ClipNoteIgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords"),
        ClipNoteIgnoredApp(bundleID: "com.1password.1password", name: "1Password"),
        ClipNoteIgnoredApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        ClipNoteIgnoredApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
    ]

    private init() {
        isPaused = defaults.bool(forKey: DefaultsKey.clipNotePaused)
        autoPaste = defaults.bool(forKey: DefaultsKey.clipNoteAutoPaste)
        deleteNeedsCommand = defaults.bool(forKey: DefaultsKey.clipNoteDeleteNeedsCommand)
        skipConcealed = defaults.bool(forKey: DefaultsKey.clipNoteSkipConcealed)
        ocrEnabled = defaults.bool(forKey: DefaultsKey.clipNoteOCR)
        ocrBackfillEnabled = defaults.bool(forKey: DefaultsKey.clipNoteOCRBackfill)
        retentionDays = defaults.integer(forKey: DefaultsKey.clipNoteRetentionDays)
        maxItems = defaults.integer(forKey: DefaultsKey.clipNoteMaxItems)
        ignoredApps = Self.load([ClipNoteIgnoredApp].self, forKey: DefaultsKey.clipNoteIgnoredApps, defaults: defaults)
            ?? Self.defaultIgnoredApps
        stackLIFO = defaults.bool(forKey: DefaultsKey.clipNoteStackLIFO)
        stackSeparator = defaults.string(forKey: DefaultsKey.clipNoteStackSeparator)
            .flatMap(ClipNoteStackSeparator.init(rawValue:)) ?? .newline
        autoBackupToICloud = defaults.bool(forKey: DefaultsKey.clipNoteAutoBackup)
        syncEnabled = defaults.bool(forKey: DefaultsKey.clipNoteSyncEnabled)
        webdavTrustSelfSigned = defaults.bool(forKey: DefaultsKey.clipNoteWebDAVTrustSelfSigned)
        webdavURL = defaults.string(forKey: DefaultsKey.clipNoteWebDAVURL) ?? ""
        webdavUser = defaults.string(forKey: DefaultsKey.clipNoteWebDAVUser) ?? ""
        webdavFolder = defaults.string(forKey: DefaultsKey.clipNoteWebDAVFolder) ?? "ClipNote"
        syncImages = defaults.bool(forKey: DefaultsKey.clipNoteSyncImages)
        maxCaptureMB = defaults.integer(forKey: DefaultsKey.clipNoteMaxCaptureMB)
        maxSyncItemMB = defaults.integer(forKey: DefaultsKey.clipNoteMaxSyncItemMB)
        aiProvider = defaults.string(forKey: DefaultsKey.clipNoteAIProvider).flatMap(AIProvider.init(rawValue:))
            ?? .anthropic
        aiEffort = defaults.string(forKey: DefaultsKey.clipNoteAIEffort).flatMap(AIEffort.init(rawValue:)) ?? .low
    }

    static func aiKeyAccount(_ provider: AIProvider) -> String { "ai-key-\(provider.rawValue)" }

    func aiBaseURL(_ provider: AIProvider) -> String {
        defaults.string(forKey: DefaultsKey.clipNoteAIBaseURL(provider.rawValue)) ?? provider.defaultBaseURL
    }

    func aiModel(_ provider: AIProvider) -> String {
        defaults.string(forKey: DefaultsKey.clipNoteAIModel(provider.rawValue)) ?? provider.defaultModel
    }

    func setAI(_ provider: AIProvider, baseURL: String, model: String, apiKey: String) {
        objectWillChange.send()
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                     forKey: DefaultsKey.clipNoteAIBaseURL(provider.rawValue))
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines),
                     forKey: DefaultsKey.clipNoteAIModel(provider.rawValue))
        ClipNoteKeychain.set(Self.aiKeyAccount(provider), apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The model service the AI actions use.
    var aiConfig: AIConfig {
        AIConfig(provider: aiProvider, baseURL: aiBaseURL(aiProvider),
                 apiKey: ClipNoteKeychain.get(Self.aiKeyAccount(aiProvider)) ?? "",
                 model: aiModel(aiProvider), effort: aiEffort)
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
