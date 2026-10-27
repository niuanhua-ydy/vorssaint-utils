// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import Combine

/// ClipNote inside Vorssaint: clipboard history with pinboards, full-text
/// search (Chinese included), Paste Stack, AI actions, WebDAV sync and
/// backups. Vorssaint's services are plain main-thread classes while
/// ClipNote's parts are main-actor isolated, so this front door is a plain
/// class too and steps onto the main actor once per call. Main thread only.
final class ClipNoteService: ObservableObject {
    static let shared = ClipNoteService()

    @Published private(set) var isRunning = false
    /// Why the history could not be opened, shown on the Settings page.
    @Published private(set) var storeError: String?
    @Published private(set) var panelShortcutFailed = false
    @Published private(set) var stackShortcutFailed = false
    /// The tab Settings opens on; the panel's settings actions set it.
    @Published var settingsTab: ClipNoteSettingsTab = .general
    /// Each copy the history records, new or already known, for the island's
    /// copy notice. It outlives a restart, so a subscriber keeps hearing.
    let captured = PassthroughSubject<Void, Never>()

    private(set) var store: ClipStore?
    private var runtime: ClipNoteRuntime?
    private let panelHotkey = QuickToolHotkey(id: 90)
    private let stackHotkey = QuickToolHotkey(id: 91)

    private init() {
        panelHotkey.onPress = { [weak self] in self?.togglePanel() }
        stackHotkey.onPress = { [weak self] in self?.toggleStack() }
    }

    var isWanted: Bool {
        AppFeature.clipNote.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.clipNoteEnabled)
    }

    func syncWithPreferences() {
        if isWanted {
            start()
        } else {
            stop()
        }
        syncHotkeys()
    }

    func syncHotkeys() {
        let defaults = UserDefaults.standard
        let panelOK = panelHotkey.sync(enabled: isRunning,
                                       shortcut: GlobalShortcutRole.clipNote.savedShortcut,
                                       storageKey: GlobalShortcutRole.clipNote.storageKey)
        let stackOK = stackHotkey.sync(
            enabled: isRunning && defaults.bool(forKey: DefaultsKey.clipNoteStackShortcutEnabled),
            shortcut: GlobalShortcutRole.clipNoteStack.savedShortcut,
            storageKey: GlobalShortcutRole.clipNoteStack.storageKey)
        if panelShortcutFailed == panelOK { panelShortcutFailed = !panelOK }
        if stackShortcutFailed == stackOK { stackShortcutFailed = !stackOK }
    }

    private func start() {
        guard runtime == nil else { return }
        do {
            let store: ClipStore
            if let opened = self.store {
                store = opened
            } else {
                guard let directory = ClipNoteStorage.directory,
                      PrivateFileStore.createDirectory(at: directory, container: ClipNoteStorage.container) else {
                    storeError = "no Application Support folder"
                    return
                }
                store = try ClipStore(directory: directory)
            }
            self.store = store
            runtime = MainActor.assumeIsolated { ClipNoteRuntime(store: store, service: self) }
            storeError = nil
            isRunning = true
        } catch {
            storeError = String(describing: error)
            NSLog("[ClipNote] could not open the history: \(error)")
        }
    }

    private func stop() {
        guard let runtime else { return }
        MainActor.assumeIsolated { runtime.tearDown() }
        self.runtime = nil
        isRunning = false
    }

    // MARK: - Entry points

    func togglePanel() {
        MainActor.assumeIsolated { runtime?.panel.toggle() }
    }

    func showPanel() {
        MainActor.assumeIsolated { runtime?.panel.show() }
    }

    func toggleStack() {
        MainActor.assumeIsolated { runtime?.stack.toggle() }
    }

    var isStackVisible: Bool {
        MainActor.assumeIsolated { runtime?.stack.isVisible ?? false }
    }

    /// Another part of Vorssaint rewrote the clipboard for a moment (paste
    /// as plain text, say); changes up to this count are not history.
    func ignoreChanges(upTo changeCount: Int) {
        MainActor.assumeIsolated { runtime?.monitor.ignoreChanges(upTo: changeCount) }
    }

    // MARK: - For the Command Bar

    /// Items matching what was typed, best first, from ClipNote's own index
    /// (so Chinese words and text read out of images match too). Empty while
    /// ClipNote is off. Its read connection answers in milliseconds, so the
    /// bar asks on every keystroke.
    func search(_ query: String, limit: Int) -> [ClipItem] {
        guard isRunning, let store else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return store.fetch(ClipQuery(text: text, limit: limit))
    }

    /// The latest items, newest first.
    func recent(limit: Int) -> [ClipItem] {
        guard isRunning, let store else { return [] }
        return store.fetch(ClipQuery(limit: limit))
    }

    func imageURL(of item: ClipItem) -> URL? {
        guard item.type == .image else { return nil }
        return store?.url(forRelativePath: item.content)
    }

    /// Puts the item on the clipboard and pastes it into the app in front,
    /// for a surface that has already handed focus back (the Command Bar).
    func paste(itemID: Int64, plainText: Bool = false) {
        guard let runtime, let store, let item = store.item(id: itemID) else { return }
        MainActor.assumeIsolated {
            ClipNotePasteboard.write(item, mode: plainText ? .plainText : .original, store: store,
                                     monitor: runtime.monitor) {
                store.markUsed(id: itemID)
                ClipNotePasteboard.pasteIntoFrontApp()
            }
        }
    }

    func openSettings(_ tab: ClipNoteSettingsTab? = nil) {
        if let tab { settingsTab = tab }
        SettingsRouter.shared.request(FeatureSettingsDestination(.clipNote))
        appDelegate()?.openSettingsWindow()
    }

    /// The parts the Settings page works with, while ClipNote runs.
    @MainActor var parts: ClipNoteRuntime? { runtime }
}

/// Every running part of ClipNote, made together on start and torn down
/// together on stop.
@MainActor
final class ClipNoteRuntime {
    let store: ClipStore
    let preferences = ClipNotePreferences.shared
    let monitor: ClipNoteMonitor
    let panel: ClipNotePanelController
    let stack: ClipNoteStackController
    let sync: ClipNoteSyncController
    let backup: ClipNoteBackupController
    let pasteImport: ClipNotePasteImportController
    let ocrBackfill: ClipNoteOCRBackfill
    private var retentionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(store: ClipStore, service: ClipNoteService) {
        self.store = store
        monitor = ClipNoteMonitor(store: store, preferences: preferences)
        sync = ClipNoteSyncController(store: store, preferences: preferences)
        backup = ClipNoteBackupController(store: store, preferences: preferences)
        pasteImport = ClipNotePasteImportController(store: store, preferences: preferences)
        ocrBackfill = ClipNoteOCRBackfill(store: store, preferences: preferences)
        panel = ClipNotePanelController(store: store, preferences: preferences, monitor: monitor)
        stack = ClipNoteStackController(store: store, preferences: preferences, monitor: monitor)

        monitor.onCapture = { [weak self, weak service] id in
            self?.stack.captured(itemID: id)
            service?.captured.send()
        }
        monitor.start()
        backup.startAutoBackup()
        ocrBackfill.activate()
        sync.reconfigure()

        panel.onOpenSettings = { [weak service] tab in service?.openSettings(tab) }
        panel.onShow = { [weak self] in self?.sync.pullIfStale() }
        panel.model.onSyncNow = { [weak self] in self?.sync.syncNow(userInitiated: true) }
        // The top bar's sync button shows the sync state.
        sync.$status.combineLatest(sync.$lastSync)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status, lastSync in
                MainActor.assumeIsolated {
                    guard let model = self?.panel.model else { return }
                    let indicator: ClipNotePanelModel.SyncIndicator = switch status {
                    case .off: .hidden
                    case .idle: .idle
                    case .syncing: .syncing
                    case .error(let message): .error(message)
                    }
                    if model.syncIndicator != indicator { model.syncIndicator = indicator }
                    if model.lastSync != lastSync { model.lastSync = lastSync }
                }
            }
            .store(in: &cancellables)

        applyRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyRetention() }
        }
    }

    func applyRetention() {
        let store = self.store
        let days = preferences.retentionDays, max = preferences.maxItems
        DispatchQueue.global(qos: .utility).async {
            store.applyRetention(maxAgeDays: days, maxItems: max)
        }
    }

    func tearDown() {
        retentionTimer?.invalidate()
        retentionTimer = nil
        cancellables.removeAll()
        monitor.onCapture = nil
        monitor.stop()
        stack.tearDown()
        panel.tearDown()
        sync.shutDown()
        store.isSyncRecording = false
        backup.stopAutoBackup()
        ocrBackfill.shutDown()
    }
}
