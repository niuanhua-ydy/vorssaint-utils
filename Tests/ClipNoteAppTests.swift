// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation
@testable import ClipNoteCore

/// ClipNote's side of Vorssaint: its words in every offered language, the
/// one-time move of the standalone app's preferences, the errors its core
/// raises told in the interface language, and its default shortcuts.
enum ClipNoteAppTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        migration(suite)
        errors(suite)
        shortcuts(suite)
        panelDelete(suite)
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.offered where language != .enUS {
            LocalizationTests.check(FeatureStrings.clipNote(language), against: ClipNoteStrings.enUS,
                                    name: "ClipNoteStrings.\(language.rawValue)", suite: suite)
            LocalizationTests.check(FeatureStrings.clipNoteSettings(language), against: ClipNoteSettingsStrings.enUS,
                                    name: "ClipNoteSettingsStrings.\(language.rawValue)", suite: suite)
        }
        suite.expectEqual(FeatureStrings.clipNote(.zhTW).id, "en-US",
                          "a language without its own ClipNote words reads English")
        let english = ClipNoteStrings.enUS
        suite.expectEqual(Set(ClipType.allCases.map(english.typeName)).count, ClipType.allCases.count,
                          "every item type has its own name")
        suite.clipNoteCase("display titles") { scratch in
            let store = try scratch.store()
            let id = try store.insert(NewClip(type: .image, content: "Images/a.png", searchText: "", hash: "i"))
            let item = try clipNoteUnwrap(store.item(id: id), "the image item")
            suite.expectEqual(english.displayTitle(of: item), "Image", "an untitled item shows its type")
            store.setTitle(itemID: id, title: "Receipt")
            let titled = try clipNoteUnwrap(store.item(id: id), "the titled item")
            suite.expectEqual(english.displayTitle(of: titled), "Receipt", "a titled item shows its title")
        }
        suite.expectEqual(Set(ClipNoteSettingsTab.allCases.map(ClipNoteSettingsStrings.enUS.tabTitle)).count,
                          ClipNoteSettingsTab.allCases.count, "every Settings tab has its own title")
    }

    private static func migration(_ suite: TestSuite) {
        let name = "vorss.tests.clipnote-migration"
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "the migration test suite opens")
            return
        }
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let hotKey = Data(#"{"keyCode":9,"modifiers":\#(cmdKey | optionKey),"keyName":"V"}"#.utf8)
        let saved: [String: Any] = [
            "isPaused": true,
            "retentionDays": 30,
            "stackSeparator": "comma",
            "webdavUser": "me@example.com",
            "webdavURL": "",
            "ai.anthropic.model": "claude-sonnet-5-5",
            "hotKey": hotKey,
            "stackHotKeyDisabled": true,
            "unrelatedKey": "ignored",
        ]
        ClipNoteDefaults.migrate(saved, into: defaults)
        suite.expect(defaults.bool(forKey: DefaultsKey.clipNotePaused), "a paused recorder stays paused")
        suite.expectEqual(defaults.integer(forKey: DefaultsKey.clipNoteRetentionDays), 30, "retention carries over")
        suite.expectEqual(defaults.string(forKey: DefaultsKey.clipNoteStackSeparator), "comma",
                          "the merge separator carries over")
        suite.expectEqual(defaults.string(forKey: DefaultsKey.clipNoteAIModel("anthropic")), "claude-sonnet-5-5",
                          "a model service's settings carry over")
        suite.expectEqual(defaults.string(forKey: DefaultsKey.clipNoteWebDAVURL), "https://dav.jianguoyun.com/dav/",
                          "an old Jianguoyun sync keeps its address")
        suite.expectEqual(defaults.string(forKey: DefaultsKey.clipNoteShortcut),
                          GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.option, .command]).storageValue,
                          "the panel shortcut carries over from Carbon codes")
        suite.expect(defaults.object(forKey: DefaultsKey.clipNoteStackShortcutEnabled) as? Bool == false,
                     "a switched-off Paste Stack shortcut stays off")
        suite.expect(defaults.object(forKey: "unrelatedKey") == nil, "keys ClipNote never had are not copied")

        defaults.removePersistentDomain(forName: name)
        suite.expect(!ClipNoteDefaults.adoptOtherVariant(["appLanguage": "en-US"], into: defaults),
                     "another build that never ran ClipNote gives nothing")
        suite.expect(ClipNoteDefaults.adoptOtherVariant([DefaultsKey.clipNoteEnabled: true,
                                                         DefaultsKey.clipNoteRetentionDays: 90,
                                                         "appLanguage": "en-US"], into: defaults),
                     "another build's ClipNote choices are taken")
        suite.expect(defaults.bool(forKey: DefaultsKey.clipNoteEnabled)
                        && defaults.integer(forKey: DefaultsKey.clipNoteRetentionDays) == 90,
                     "ClipNote's own keys come over as they are")
        suite.expect(defaults.object(forKey: "appLanguage") == nil, "the rest of that build's settings stay there")
        suite.expectEqual(AppInfo.otherVariantBundleID(of: "com.vorssaint.utils.dev"), "com.vorssaint.utils",
                          "the Developer build's other build is the official app")
        suite.expectEqual(AppInfo.otherVariantBundleID(of: "com.vorssaint.utils"), "com.vorssaint.utils.dev",
                          "the official app's other build is the Developer build")

        let bare = Data(#"{"keyCode":9,"modifiers":0,"keyName":"V"}"#.utf8)
        suite.expect(ClipNoteDefaults.standaloneShortcut(bare) == nil, "a shortcut without a modifier is dropped")
        suite.expect(ClipNoteDefaults.standaloneShortcut("not data") == nil, "an unreadable shortcut is dropped")

        defaults.removePersistentDomain(forName: name)
        ClipNoteDefaults.takeOverClipboardHistory(in: defaults)
        suite.expect(defaults.object(forKey: DefaultsKey.clipNoteEnabled) == nil,
                     "without a kept history, ClipNote waits for its own switch")
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        ClipNoteDefaults.takeOverClipboardHistory(in: defaults)
        suite.expect(defaults.bool(forKey: DefaultsKey.clipNoteEnabled), "a kept history becomes ClipNote switched on")
        defaults.set(false, forKey: DefaultsKey.clipNoteEnabled)
        ClipNoteDefaults.takeOverClipboardHistory(in: defaults)
        suite.expect(!defaults.bool(forKey: DefaultsKey.clipNoteEnabled), "ClipNote switched off stays off")

        let registered = ClipNoteDefaults.registered
        suite.expect(registered[DefaultsKey.clipNoteEnabled] as? Bool == false,
                     "recording waits for its own switch")
        suite.expect(registered[DefaultsKey.clipNoteStackShortcutEnabled] as? Bool == true,
                     "the Paste Stack shortcut starts on")
    }

    private static func errors(_ suite: TestSuite) {
        let english = ClipNoteStrings.enUS
        let chinese = ClipNoteStrings.zhHans
        suite.expectEqual(english.describe(WebDAVError.unauthorized), english.errorWebDAVUnauthorized,
                          "a WebDAV refusal reads in the interface language")
        suite.expectEqual(chinese.describe(SyncError.wrongPassphrase), chinese.errorWrongPassphrase,
                          "a sync error reads in Chinese too")
        suite.expectEqual(english.describe(AIError.http(status: 401, message: "")), "The API key isn’t valid (HTTP 401)",
                          "an HTTP status names its cause")
        suite.expectEqual(english.describe(AIError.http(status: 503, message: "busy")),
                          "The service is unavailable for now; try again later (HTTP 503): busy",
                          "a server error keeps the service's message")
        suite.expectEqual(english.describe(AIError.notConfigured(" API Key")), english.errorAIKeyMissing,
                          "a missing key asks for the key")
        suite.expectEqual(english.describe(AIError.notConfigured("模型")), english.errorAIModelMissing,
                          "a missing model asks for the model")
        let unknown = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "plain"])
        suite.expectEqual(english.describe(unknown), "plain", "an error from elsewhere keeps its own words")

        var report = SyncReport()
        report.otherDevices = 2
        suite.expectEqual(english.syncSummary(report), "Up to date (2 other devices)", "an empty sync reads up to date")
        report.uploadedOps = 3
        report.applied.inserted = 1
        suite.expectEqual(english.syncSummary(report), "3 uploaded, 1 new (2 other devices)",
                          "a sync lists what moved")
    }

    private static func shortcuts(_ suite: TestSuite) {
        for role in [GlobalShortcutRole.clipNote, .clipNoteStack] {
            suite.expect(role.feature == .clipNote, "\(role) belongs to ClipNote")
            suite.expect(role.defaultShortcut.isValid, "\(role) has a usable default")
            let clashes = GlobalShortcutRole.allCases.filter { $0 != role && $0.defaultShortcut == role.defaultShortcut }
            suite.expect(clashes.isEmpty, "\(role)'s default is no other role's default: \(clashes)")
        }
        suite.expect(GlobalShortcutRole.clipNoteStack.requiredEnableKeys.contains(DefaultsKey.clipNoteStackShortcutEnabled),
                     "the Paste Stack shortcut follows its own switch")
    }

    private static func panelDelete(_ suite: TestSuite) {
        func deletes(_ keyCode: Int = kVK_Delete, command: Bool = false, other: Bool = false, repeating: Bool = false,
                     queryIsEmpty: Bool = true, needsCommand: Bool = false) -> Bool {
            ClipNotePanelKeys.deletesItem(keyCode: keyCode, command: command, otherModifiers: other,
                                          isRepeat: repeating, queryIsEmpty: queryIsEmpty, needsCommand: needsCommand)
        }
        suite.expectEqual(ClipNoteDefaults.registered[DefaultsKey.clipNoteDeleteNeedsCommand] as? Bool, false,
                          "Delete alone removes an item by default, as in Paste")
        suite.expect(deletes(), "Delete alone removes the item")
        suite.expect(deletes(kVK_ForwardDelete), "forward Delete removes the item")
        suite.expect(!deletes(needsCommand: true), "with ⌘ required, Delete alone does nothing")
        suite.expect(deletes(command: true, needsCommand: true), "⌘Delete removes the item when ⌘ is required")
        suite.expect(deletes(command: true, queryIsEmpty: false), "⌘Delete removes the item while searching")
        suite.expect(!deletes(queryIsEmpty: false), "Delete alone edits the search while it has text")
        suite.expect(!deletes(repeating: true), "holding Delete to clear the search stops at the empty field")
        suite.expect(deletes(command: true, repeating: true), "a held ⌘Delete keeps removing items")
        suite.expect(!deletes(other: true), "Delete with ⌥, ⌃ or ⇧ is not the panel's")
        suite.expect(!deletes(kVK_ANSI_D), "other keys never delete")
        let keys = ClipNoteSettingsStrings.enUS
        suite.expect(keys.panelKeys(deleteNeedsCommand: false).contains { $0.keys == "⌘C / ⌫" },
                     "the panel keys list shows Delete alone")
        suite.expect(keys.panelKeys(deleteNeedsCommand: true).contains { $0.keys == "⌘C / ⌘⌫" },
                     "the panel keys list shows ⌘Delete when it is required")
    }
}
