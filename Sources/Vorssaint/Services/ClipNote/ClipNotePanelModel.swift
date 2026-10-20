// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import Combine
import SwiftUI

/// The panel's state: the tab, search, filters and selection.
@MainActor
final class ClipNotePanelModel: ObservableObject {
    enum Tab: Hashable {
        case history
        case pinboard(Int64)
    }

    /// A pinboard being named in place, new or renamed.
    struct PinboardEditor: Equatable {
        var editingID: Int64?
        var name: String
        var color: String
    }

    /// The sync button in the top bar; hidden while sync is off.
    enum SyncIndicator: Equatable {
        case hidden
        case idle
        case syncing
        case error(String)
    }

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []
    @Published private(set) var sourceApps: [SourceApp] = []
    @Published var tab: Tab = .history { didSet { if tab != oldValue { reload(resetSelection: true, animated: true) } } }
    @Published var query = "" { didSet { if query != oldValue { reloadGeneration += 1; scheduleReload() } } }
    @Published var typeFilter: ClipType? {
        didSet { if typeFilter != oldValue { reload(resetSelection: true, animated: true) } }
    }
    @Published var appFilter: String? { didSet { if appFilter != oldValue { reload(resetSelection: true, animated: true) } } }
    @Published var selectedID: Int64?
    @Published var now = Date()
    @Published var editor: PinboardEditor?
    /// Drives the panel's slide in and out.
    @Published var isPresented = false
    /// Holding ⌘ shows the number shortcuts on the cards.
    @Published var showShortcuts = false
    /// The search field opens on a click of the magnifier or on typing.
    @Published var isSearchExpanded = false
    /// The card whose title is being edited.
    @Published var editingTitleID: Int64?
    @Published var syncIndicator: SyncIndicator = .hidden
    @Published var lastSync: Date?
    /// The app in front before the panel opened, for "Paste to …".
    @Published var pasteTarget: (name: String, bundleID: String?)?

    var isSearchActive: Bool { isSearchExpanded || !query.isEmpty }

    let store: ClipStore
    weak var searchField: NSTextField?

    // Set by the panel controller.
    var onPaste: ((ClipItem, ClipNotePasteMode) -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onPreview: ((ClipItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    var onSyncNow: (() -> Void)?
    var onAIAction: ((ClipItem, ClipNoteAIAction) -> Void)?
    /// Opens the AI window for a custom instruction.
    var onAICustom: ((ClipItem) -> Void)?
    /// Where the visible cards are (SwiftUI coordinates, origin top left), to
    /// tell which card a drag starts on.
    var cardFrames: [Int64: CGRect] = [:]

    func card(at point: CGPoint) -> ClipItem? {
        guard let id = cardFrames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return items.first { $0.id == id }
    }

    var isVisible = false
    static let pageSize = 200
    /// Queries run off the main thread; the generation drops stale results.
    private let queryQueue = DispatchQueue(label: "com.vorssaint.utils.clipnote.panel-query", qos: .userInitiated)
    private var reloadGeneration = 0
    private var hasMore = true
    private var isLoadingMore = false
    private var reloadWork: DispatchWorkItem?
    private var needsReload = true
    private var observer: NSObjectProtocol?
    /// Each card's computed content (highlights, details), so a render never recomputes it.
    private var contentCache: [Int64: ClipNoteCardContent] = [:]
    private var contentCacheQuery = ""

    init(store: ClipStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(forName: ClipStore.didChangeNotification, object: store,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        }
    }

    var searchTerms: [String] { SearchQuery(query).terms }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return items.firstIndex { $0.id == selectedID }
    }

    var selectedItem: ClipItem? {
        selectedIndex.map { items[$0] }
    }

    var hasActiveFilter: Bool { typeFilter != nil || appFilter != nil }

    func pinboard(id: Int64?) -> Pinboard? {
        guard let id else { return nil }
        return pinboards.first { $0.id == id }
    }

    // MARK: - Lifecycle

    /// Before showing. The data is usually ready from while it was hidden.
    func prepareForShow() {
        isVisible = true
        now = Date()
        editor = nil
        editingTitleID = nil
        showShortcuts = false
        isSearchExpanded = false
        reloadWork?.cancel()
        let queryChanged = !query.isEmpty
        if queryChanged {
            query = ""
            reloadWork?.cancel()
        }
        if needsReload || queryChanged || items.count > Self.pageSize {
            // Loaded synchronously so the panel never opens empty (rare: the data is usually prefetched).
            reload(resetSelection: true, synchronous: true)
        } else {
            selectedID = items.first?.id
        }
    }

    func didHide() {
        isVisible = false
    }

    private func storeDidChange() {
        needsReload = true
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.needsReload else { return }
                // Animated while visible; while hidden, ready for the next opening.
                self.reload(resetSelection: false, animated: self.isVisible, keepLoadedCount: self.isVisible)
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isVisible ? 0.02 : 0.3), execute: work)
    }

    // MARK: - Loading

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload(resetSelection: true) }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Reloads the first page, off the main thread unless asked otherwise.
    /// `keepLoadedCount` keeps the pages already scrolled in, so a visible
    /// refresh does not jump.
    func reload(resetSelection: Bool, animated: Bool = false, synchronous: Bool = false, keepLoadedCount: Bool = false) {
        needsReload = false
        reloadGeneration += 1
        let generation = reloadGeneration
        let scope: ClipQuery.Scope = if case .pinboard(let id) = tab { .pinboard(id) } else { .all }
        let limit = keepLoadedCount ? max(Self.pageSize, items.count) : Self.pageSize
        let query = ClipQuery(text: query, scope: scope, type: typeFilter, sourceBundleID: appFilter, limit: limit)
        let store = self.store

        let load = { () -> ([Pinboard], [SourceApp], [ClipItem]) in
            (store.pinboards(), store.sourceApps(), store.fetch(query))
        }
        let apply = { [weak self] (result: ([Pinboard], [SourceApp], [ClipItem])) in
            guard let self, generation == self.reloadGeneration else { return }
            self.apply(result, limit: limit, resetSelection: resetSelection, animated: animated)
        }
        if synchronous {
            apply(load())
        } else {
            queryQueue.async {
                let result = load()
                DispatchQueue.main.async { MainActor.assumeIsolated { apply(result) } }
            }
        }
    }

    private func apply(_ result: ([Pinboard], [SourceApp], [ClipItem]), limit: Int, resetSelection: Bool,
                       animated: Bool) {
        let (boards, apps, fetched) = result
        if boards != pinboards { pinboards = boards }
        if apps != sourceApps { sourceApps = apps }
        if case .pinboard(let id) = tab, !boards.contains(where: { $0.id == id }) {
            tab = .history
            return
        }
        if contentCacheQuery != query {
            contentCache.removeAll()
            contentCacheQuery = query
        }
        hasMore = fetched.count >= limit
        isLoadingMore = false
        withAnimation(animated ? .spring(response: 0.36, dampingFraction: 0.86) : nil) {
            items = fetched
            if resetSelection || selectedIndex == nil {
                selectedID = items.first?.id
            }
        }
    }

    func content(for item: ClipItem, strings: ClipNoteStrings) -> ClipNoteCardContent {
        if let cached = contentCache[item.id], cached.updatedAt == item.updatedAt, cached.strings == strings.id {
            return cached
        }
        let content = ClipNoteCardContent(item: item, terms: searchTerms, strings: strings)
        contentCache[item.id] = content
        return content
    }

    /// Near the end of the strip, fetches the next page in the background.
    /// Search results come from the store's ranked cache, so a page is cheap.
    func loadMoreIfNeeded(currentIndex: Int) {
        guard currentIndex >= items.count - 10, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let generation = reloadGeneration
        let scope: ClipQuery.Scope = if case .pinboard(let id) = tab { .pinboard(id) } else { .all }
        let query = ClipQuery(text: query, scope: scope, type: typeFilter, sourceBundleID: appFilter,
                              limit: Self.pageSize, offset: items.count)
        let store = self.store
        queryQueue.async { [weak self] in
            let page = store.fetch(query)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.reloadGeneration else { return }
                    self.isLoadingMore = false
                    self.hasMore = page.count >= Self.pageSize
                    let existing = Set(self.items.map(\.id))
                    self.items += page.filter { !existing.contains($0.id) }
                }
            }
        }
    }

    // MARK: - Navigation

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = selectedIndex ?? 0
        let next = max(0, min(items.count - 1, current + delta))
        selectedID = items[next].id
        loadMoreIfNeeded(currentIndex: next)
    }

    func select(_ item: ClipItem) {
        selectedID = item.id
    }

    var tabs: [Tab] { [.history] + pinboards.map { .pinboard($0.id) } }

    func switchTab(by delta: Int) {
        let all = tabs
        guard let index = all.firstIndex(of: tab) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            tab = all[(index + delta + all.count) % all.count]
        }
    }

    // MARK: - Actions

    func paste(_ item: ClipItem? = nil, mode: ClipNotePasteMode = .original) {
        guard let item = item ?? selectedItem else { return }
        onPaste?(item, mode)
    }

    func paste(atIndex index: Int, mode: ClipNotePasteMode = .original) {
        guard items.indices.contains(index) else { return }
        paste(items[index], mode: mode)
    }

    func copy(_ item: ClipItem? = nil) {
        guard let item = item ?? selectedItem else { return }
        onCopy?(item)
    }

    func delete(_ item: ClipItem? = nil) {
        guard let item = item ?? selectedItem else { return }
        if item.id == selectedID, let index = selectedIndex {
            let neighbor = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            selectedID = neighbor?.id
        }
        store.delete(ids: [item.id])
    }

    func pin(_ item: ClipItem, to board: Pinboard?) {
        store.setPinboard(itemID: item.id, pinboardID: board?.id)
    }

    func apply(_ action: ClipNoteTextAction, to item: ClipItem) {
        guard let full = store.item(id: item.id), let text = action.transform(full, store) else { return }
        onPaste?(full, .transformed(text))
    }

    // MARK: - Titles

    func beginEditingTitle(_ item: ClipItem) {
        editor = nil
        selectedID = item.id
        editingTitleID = item.id
    }

    /// Saves a title. Clearing it, or typing the type name back, returns to the default.
    func commitTitle(_ item: ClipItem, text: String, strings: ClipNoteStrings) {
        guard editingTitleID == item.id else { return }
        editingTitleID = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefault = trimmed.isEmpty || trimmed == strings.typeName(item.type) || trimmed == item.type.displayName
        let newTitle: String? = isDefault ? nil : trimmed
        if newTitle != item.title {
            store.setTitle(itemID: item.id, title: newTitle)
        }
        onFocusSearch?()
    }

    func cancelEditingTitle() {
        editingTitleID = nil
        onFocusSearch?()
    }

    // MARK: - Pinboards

    func beginNewPinboard(name: String) {
        let color = Pinboard.presetColors[pinboards.count % Pinboard.presetColors.count]
        editor = PinboardEditor(editingID: nil, name: name, color: color)
    }

    func beginRename(_ board: Pinboard) {
        editor = PinboardEditor(editingID: board.id, name: board.name, color: board.color)
    }

    func commitEditor() {
        guard let editor else { return }
        let name = editor.name.trimmingCharacters(in: .whitespaces)
        self.editor = nil
        defer { onFocusSearch?() }
        guard !name.isEmpty else { return }
        if let id = editor.editingID, var board = pinboard(id: id) {
            board.name = name
            board.color = editor.color
            store.updatePinboard(board)
        } else if let board = store.createPinboard(name: name, color: editor.color) {
            tab = .pinboard(board.id)
        }
    }

    func cancelEditor() {
        editor = nil
        onFocusSearch?()
    }

    func deletePinboard(_ board: Pinboard) {
        if tab == .pinboard(board.id) { tab = .history }
        store.deletePinboard(id: board.id)
    }
}

/// The parts of a card worth computing once.
struct ClipNoteCardContent {
    let updatedAt: Date
    /// The language the content was made in, so a switch rebuilds it.
    let strings: String
    let text: AttributedString?
    let meta: String

    @MainActor
    init(item: ClipItem, terms: [String], strings: ClipNoteStrings) {
        updatedAt = item.updatedAt
        self.strings = strings.id
        switch item.type {
        case .text, .rich:
            text = ClipNoteHighlighter.attributed(Snippet.make(item.content, terms: terms, maxLength: 320), terms: terms)
        case .link:
            text = ClipNoteHighlighter.attributed(String(item.content.prefix(300)), terms: terms)
        case .file, .image:
            text = nil
        }
        meta = ClipNoteFormatters.meta(for: item, strings: strings)
    }
}
