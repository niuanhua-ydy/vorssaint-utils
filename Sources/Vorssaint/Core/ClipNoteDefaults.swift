// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import ClipNoteCore
import Foundation

/// ClipNote's preferences. Before ClipNote moved into Vorssaint they lived in
/// its own domain, `com.clipnote.app`; `ClipNoteDefaults` copies them over
/// once under these names. Kept out of Defaults.swift so the keys added here
/// never collide with the ones upstream adds there.
extension DefaultsKey {
    static let clipNoteEnabled = "clipNoteEnabled"
    static let clipNoteShortcut = "clipNoteShortcut"
    static let clipNoteStackShortcut = "clipNoteStackShortcut"
    static let clipNoteStackShortcutEnabled = "clipNoteStackShortcutEnabled"
    static let clipNotePaused = "clipNotePaused"
    /// Paste into the app in front after picking an item; off only copies.
    static let clipNoteAutoPaste = "clipNoteAutoPaste"
    /// Skip content password managers mark as concealed or transient.
    static let clipNoteSkipConcealed = "clipNoteSkipConcealed"
    static let clipNoteOCR = "clipNoteOCR"
    /// Recognize text in images saved before recognition was on, one at a time.
    static let clipNoteOCRBackfill = "clipNoteOCRBackfill"
    static let clipNoteRetentionDays = "clipNoteRetentionDays"   // 0 keeps items forever
    static let clipNoteMaxItems = "clipNoteMaxItems"             // 0 keeps any number
    static let clipNoteMaxCaptureMB = "clipNoteMaxCaptureMB"     // 0 records any size
    static let clipNoteIgnoredApps = "clipNoteIgnoredApps"       // Data: [ClipNoteIgnoredApp] JSON
    /// Paste Stack order: false pastes the first copy first.
    static let clipNoteStackLIFO = "clipNoteStackLIFO"
    static let clipNoteStackSeparator = "clipNoteStackSeparator"
    static let clipNoteStackWindowTopLeft = "clipNoteStackWindowTopLeft" // [x, y]
    static let clipNoteAutoBackup = "clipNoteAutoBackup"         // daily, to iCloud Drive
    static let clipNoteLastAutoBackup = "clipNoteLastAutoBackup"
    static let clipNoteSyncEnabled = "clipNoteSyncEnabled"
    static let clipNoteWebDAVURL = "clipNoteWebDAVURL"
    static let clipNoteWebDAVUser = "clipNoteWebDAVUser"
    static let clipNoteWebDAVFolder = "clipNoteWebDAVFolder"
    static let clipNoteWebDAVTrustSelfSigned = "clipNoteWebDAVTrustSelfSigned"
    static let clipNoteSyncImages = "clipNoteSyncImages"
    static let clipNoteMaxSyncItemMB = "clipNoteMaxSyncItemMB"
    static let clipNoteAIProvider = "clipNoteAIProvider"
    static let clipNoteAIEffort = "clipNoteAIEffort"
    /// Where a Paste import stopped: the library it read and its last cursors.
    static let clipNotePasteImportStoreID = "clipNotePasteImportStoreID"
    static let clipNotePasteImportCursors = "clipNotePasteImportCursors"
    static let clipNoteMigratedFromApp = "clipNoteMigratedFromApp"

    /// Each model service keeps its own address and model.
    static func clipNoteAIBaseURL(_ provider: String) -> String { "clipNoteAI.\(provider).baseURL" }
    static func clipNoteAIModel(_ provider: String) -> String { "clipNoteAI.\(provider).model" }
}

extension GlobalShortcut {
    /// ⇧⌘V, the panel's key in ClipNote and in Paste.
    static let clipNoteDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.shift, .command])
    /// ⇧⌘C, Paste Stack's key in ClipNote and in Paste.
    static let clipNoteStackDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_C), modifiers: [.shift, .command])
}

/// What ClipNote's preferences start as, and the one-time move of the
/// standalone app's choices. Apart from `ClipNotePreferences` so launch can
/// run both before anything of ClipNote exists.
enum ClipNoteDefaults {
    /// Registered with the rest of the app's defaults at launch, so the
    /// shortcut roles and Settings read the same values before ClipNote runs.
    static var registered: [String: Any] {
        [
            DefaultsKey.clipNoteEnabled: false,
            DefaultsKey.clipNoteShortcut: GlobalShortcut.clipNoteDefault.storageValue,
            DefaultsKey.clipNoteStackShortcut: GlobalShortcut.clipNoteStackDefault.storageValue,
            DefaultsKey.clipNoteStackShortcutEnabled: true,
            DefaultsKey.clipNotePaused: false,
            DefaultsKey.clipNoteAutoPaste: true,
            DefaultsKey.clipNoteSkipConcealed: true,
            DefaultsKey.clipNoteOCR: true,
            DefaultsKey.clipNoteOCRBackfill: false,
            DefaultsKey.clipNoteRetentionDays: 90,
            DefaultsKey.clipNoteMaxItems: 5000,
            DefaultsKey.clipNoteAutoBackup: false,
            DefaultsKey.clipNoteSyncEnabled: false,
            DefaultsKey.clipNoteWebDAVURL: "",
            DefaultsKey.clipNoteWebDAVUser: "",
            DefaultsKey.clipNoteWebDAVFolder: "ClipNote",
            DefaultsKey.clipNoteSyncImages: true,
            DefaultsKey.clipNoteMaxCaptureMB: 100,
            DefaultsKey.clipNoteWebDAVTrustSelfSigned: false,
            DefaultsKey.clipNoteMaxSyncItemMB: 5,
            // Most clipboard work is simple, so think little and answer fast.
            DefaultsKey.clipNoteAIEffort: AIEffort.low.rawValue,
        ]
    }

    static let standaloneDomain = "com.clipnote.app"

    /// The standalone app's choices, copied once into Vorssaint's domain. Its
    /// own domain is only read, never changed, so the app keeps working if
    /// someone opens it again. Runs at launch before defaults are registered.
    static func migrateFromStandaloneApp(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.clipNoteMigratedFromApp) else { return }
        defaults.set(true, forKey: DefaultsKey.clipNoteMigratedFromApp)
        guard let old = UserDefaults(suiteName: standaloneDomain),
              let saved = old.persistentDomain(forName: standaloneDomain), !saved.isEmpty else { return }
        migrate(saved, into: defaults)
    }

    /// `saved` is the standalone domain as a dictionary, so the mapping is
    /// testable without the real one.
    static func migrate(_ saved: [String: Any], into defaults: UserDefaults) {
        let renamed: [(String, String)] = [
            ("isPaused", DefaultsKey.clipNotePaused),
            ("autoPaste", DefaultsKey.clipNoteAutoPaste),
            ("skipConcealed", DefaultsKey.clipNoteSkipConcealed),
            ("ocrEnabled", DefaultsKey.clipNoteOCR),
            ("ocrBackfillEnabled", DefaultsKey.clipNoteOCRBackfill),
            ("retentionDays", DefaultsKey.clipNoteRetentionDays),
            ("maxItems", DefaultsKey.clipNoteMaxItems),
            ("ignoredApps", DefaultsKey.clipNoteIgnoredApps),
            ("stackLIFO", DefaultsKey.clipNoteStackLIFO),
            ("stackSeparator", DefaultsKey.clipNoteStackSeparator),
            ("stackWindowTopLeft", DefaultsKey.clipNoteStackWindowTopLeft),
            ("autoBackupToICloud", DefaultsKey.clipNoteAutoBackup),
            ("lastAutoBackup", DefaultsKey.clipNoteLastAutoBackup),
            ("syncEnabled", DefaultsKey.clipNoteSyncEnabled),
            ("webdavURL", DefaultsKey.clipNoteWebDAVURL),
            ("webdavUser", DefaultsKey.clipNoteWebDAVUser),
            ("webdavFolder", DefaultsKey.clipNoteWebDAVFolder),
            ("webdavTrustSelfSigned", DefaultsKey.clipNoteWebDAVTrustSelfSigned),
            ("syncImages", DefaultsKey.clipNoteSyncImages),
            ("maxCaptureMB", DefaultsKey.clipNoteMaxCaptureMB),
            ("maxSyncItemMB", DefaultsKey.clipNoteMaxSyncItemMB),
            ("aiProvider", DefaultsKey.clipNoteAIProvider),
            ("aiEffort", DefaultsKey.clipNoteAIEffort),
            ("pasteImport.storeID", DefaultsKey.clipNotePasteImportStoreID),
            ("pasteImport.cursors", DefaultsKey.clipNotePasteImportCursors),
        ]
        for (oldKey, newKey) in renamed {
            if let value = saved[oldKey] { defaults.set(value, forKey: newKey) }
        }
        for provider in AIProvider.allCases {
            if let url = saved["ai.\(provider.rawValue).baseURL"] {
                defaults.set(url, forKey: DefaultsKey.clipNoteAIBaseURL(provider.rawValue))
            }
            if let model = saved["ai.\(provider.rawValue).model"] {
                defaults.set(model, forKey: DefaultsKey.clipNoteAIModel(provider.rawValue))
            }
        }
        // The oldest versions synced only to Jianguoyun, without saving its
        // address; that sync keeps its target as the same WebDAV address.
        let legacy = saved["syncProvider"] as? String
        let storedURL = saved["webdavURL"] as? String ?? ""
        let configured = !(saved["webdavUser"] as? String ?? "").isEmpty
        if legacy == "jianguoyun"
            || (legacy == nil && configured && (storedURL.isEmpty || storedURL.contains("jianguoyun"))) {
            defaults.set("https://dav.jianguoyun.com/dav/", forKey: DefaultsKey.clipNoteWebDAVURL)
        }
        if let shortcut = standaloneShortcut(saved["hotKey"]) {
            defaults.set(shortcut.storageValue, forKey: DefaultsKey.clipNoteShortcut)
        }
        if saved["stackHotKeyDisabled"] as? Bool == true {
            defaults.set(false, forKey: DefaultsKey.clipNoteStackShortcutEnabled)
        } else if let shortcut = standaloneShortcut(saved["stackHotKey"]) {
            defaults.set(shortcut.storageValue, forKey: DefaultsKey.clipNoteStackShortcut)
        }
    }

    /// The standalone app saved a Carbon key code and modifier mask as JSON.
    static func standaloneShortcut(_ value: Any?) -> GlobalShortcut? {
        struct Saved: Decodable {
            var keyCode: UInt32
            var modifiers: UInt32
        }
        guard let data = value as? Data, let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var modifiers: GlobalShortcutModifiers = []
        if saved.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if saved.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if saved.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if saved.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        let shortcut = GlobalShortcut(keyCode: Int64(saved.keyCode), modifiers: modifiers)
        return shortcut.isValid ? shortcut : nil
    }
}
