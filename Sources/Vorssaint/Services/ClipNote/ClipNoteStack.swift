// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import Combine
import SwiftUI

/// One Paste Stack row. The same content may be in the list more than once.
struct ClipNoteStackEntry: Identifiable, Equatable {
    let id = UUID()
    var item: ClipItem
}

@MainActor
final class ClipNoteStackModel: ObservableObject {
    /// In copy order, earliest first.
    @Published var entries: [ClipNoteStackEntry] = []
    @Published var lifo = false
    /// Rows picked with ⌘ or ⇧ click, for merging.
    @Published var selected: Set<UUID> = []
    /// Where a ⇧ click range starts.
    var selectionAnchor: UUID?
    /// Whether ⌘V pastes the rows in turn (listening for it needs Accessibility).
    @Published var canAutoPaste = true
    @Published var isPresented = false

    /// In paste order: first copied first, or last copied first.
    var ordered: [ClipNoteStackEntry] { lifo ? entries.reversed() : entries }

    var onTap: ((ClipNoteStackEntry) -> Void)?
    var onPaste: ((ClipNoteStackEntry) -> Void)?
    var onToggleSelection: ((ClipNoteStackEntry) -> Void)?
    var onRemove: ((ClipNoteStackEntry) -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?
    var onToggleOrder: (() -> Void)?
    var onMerge: (() -> Void)?
}

/// Hears ⌘V anywhere without consuming it, so Paste Stack can move on to its
/// next row. Needs Accessibility; runs only while Paste Stack is open.
final class ClipNotePasteKeyWatcher {
    var onCommandV: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let watcher = Unmanaged<ClipNotePasteKeyWatcher>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = watcher.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == 9, // V
                      event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                      event.flags.contains(.maskCommand), !event.flags.contains(.maskControl) {
                DispatchQueue.main.async { watcher.onCommandV?() }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}

/// Clicks land on the first try; the Paste Stack window never takes focus.
final class ClipNoteFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Paste Stack: while it is open, every copy joins the list, and ⌘V in any
/// app pastes the rows in turn. A compact window after Paste's: it grows
/// with its rows, can be dragged, and remembers where it was.
///
/// The clipboard always holds the next row, with the change count of that
/// write ("armed"). When ⌘V comes and the clipboard was left alone, the row
/// goes once the app in front has read it, and the next one takes its place.
@MainActor
final class ClipNoteStackController {
    static let width: CGFloat = 280
    static let headerHeight: CGFloat = 36
    static let rowHeight: CGFloat = 44
    /// More rows than this scroll.
    static let maxVisibleRows = 8
    static let mergeBarHeight: CGFloat = 44
    static let noteHeight: CGFloat = 28

    let model = ClipNoteStackModel()
    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private let monitor: ClipNoteMonitor
    private let panel = ClipNoteFloatingPanel()
    private let watcher = ClipNotePasteKeyWatcher()
    private var armed: (entry: UUID, changeCount: Int)?
    private var cancellables: Set<AnyCancellable> = []

    init(store: ClipStore, preferences: ClipNotePreferences, monitor: ClipNoteMonitor) {
        self.store = store
        self.preferences = preferences
        self.monitor = monitor

        panel.allowsKey = false
        panel.level = .floating
        panel.hasShadow = true
        // Dragged by its header or empty space; the place is remembered.
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.contentView = ClipNoteFirstMouseHostingView(
            rootView: ClipNoteStackView(model: model, preferences: preferences, store: store))

        model.lifo = preferences.stackLIFO
        model.onTap = { [weak self] in self?.tap($0) }
        model.onPaste = { [weak self] in self?.paste($0) }
        model.onToggleSelection = { [weak self] in self?.toggleSelection($0) }
        model.onRemove = { [weak self] in self?.remove($0) }
        model.onClear = { [weak self] in self?.clear() }
        model.onClose = { [weak self] in self?.hide() }
        model.onToggleOrder = { [weak self] in self?.toggleOrder() }
        model.onMerge = { [weak self] in self?.mergeSelected() }
        watcher.onCommandV = { [weak self] in
            MainActor.assumeIsolated { self?.commandVPressed() }
        }

        // The window follows the rows and the merge bar.
        model.$entries.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateFrame(animated: true) } }
        }.store(in: &cancellables)
        model.$selected.map(\.isEmpty).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateFrame(animated: true) } }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                UserDefaults.standard.set([self.panel.frame.minX, self.panel.frame.maxY],
                                          forKey: DefaultsKey.clipNoteStackWindowTopLeft)
            }
        }.store(in: &cancellables)
    }

    private var desiredHeight: CGFloat {
        let rows = CGFloat(min(max(model.entries.count, 1), Self.maxVisibleRows))
        return Self.headerHeight + rows * Self.rowHeight
            + (model.selected.isEmpty ? 0 : Self.mergeBarHeight) + (model.canAutoPaste ? 0 : Self.noteHeight)
    }

    /// Keeps the top left corner where it is, wherever the window was dragged.
    private func updateFrame(animated: Bool) {
        guard panel.isVisible else { return }
        let frame = panel.frame
        let height = desiredHeight
        guard abs(frame.height - height) > 0.5 else { return }
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: Self.width, height: height),
                       display: true, animate: animated)
    }

    /// Where it was last, if still on a screen; else top right of the pointer's screen.
    private func initialTopLeft(height: CGFloat) -> NSPoint {
        if let saved = UserDefaults.standard.array(forKey: DefaultsKey.clipNoteStackWindowTopLeft) as? [Double],
           saved.count == 2 {
            let point = NSPoint(x: saved[0], y: saved[1])
            let probe = NSRect(x: point.x, y: point.y - min(height, 60), width: Self.width, height: min(height, 60))
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(probe) }) { return point }
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - Self.width - 24, y: visible.maxY - 80)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        model.entries = []
        model.selected = []
        model.selectionAnchor = nil
        model.canAutoPaste = AXIsProcessTrusted() && watcher.start()
        let height = desiredHeight
        let topLeft = initialTopLeft(height: height)
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - height, width: Self.width, height: height), display: false)
        armed = nil
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                withAnimation(ClipNotePanelController.showAnimation) { self?.model.isPresented = true }
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        watcher.stop()
        armed = nil
        withAnimation(ClipNotePanelController.hideAnimation) { model.isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipNotePanelController.hideDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isPresented else { return }
                self.panel.orderOut(nil)
                self.model.entries = []
            }
        }
    }

    /// The monitor recorded a copy.
    func captured(itemID: Int64) {
        guard isVisible, model.isPresented, let item = store.item(id: itemID) else { return }
        let entry = ClipNoteStackEntry(item: item)
        withAnimation(.easeOut(duration: 0.2)) { model.entries.append(entry) }
        // Last copied first means the clipboard already holds the next row.
        syncPasteboard(alreadyOnPasteboard: entry.id)
    }

    // MARK: - Clipboard and pasting

    /// Puts the next row on the clipboard.
    private func syncPasteboard(alreadyOnPasteboard: UUID? = nil) {
        guard let next = model.ordered.first else {
            armed = nil
            return
        }
        let changeCount = NSPasteboard.general.changeCount
        if let armed, armed.entry == next.id, armed.changeCount == changeCount { return }
        if next.id == alreadyOnPasteboard {
            armed = (next.id, changeCount)
            return
        }
        guard let full = store.item(id: next.item.id) else { return }
        armed = nil
        ClipNotePasteboard.write(full, mode: .original, store: store, monitor: monitor) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.ordered.first?.id == next.id else { return }
                self.armed = (next.id, NSPasteboard.general.changeCount)
            }
        }
    }

    private func commandVPressed() {
        guard isVisible else { return }
        let matched = armed.map { $0.changeCount == NSPasteboard.general.changeCount } ?? false
        let entryID = armed?.entry
        // Give the app in front time to read the clipboard before it changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if matched, let entryID, let index = self.model.entries.firstIndex(where: { $0.id == entryID }) {
                    self.armed = nil
                    withAnimation(.easeOut(duration: 0.2)) {
                        _ = self.model.entries.remove(at: index)
                        self.model.selected.remove(entryID)
                    }
                }
                // Something else changed the clipboard (a paste from the panel, say): put the next row back.
                self.syncPasteboard()
            }
        }
    }

    /// ⌘ click toggles a row, ⇧ click picks a range; with a selection, a
    /// plain click only clears it (no paste by mistake); else it pastes.
    private func tap(_ entry: ClipNoteStackEntry) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggleSelection(entry)
        } else if flags.contains(.shift), let anchor = model.selectionAnchor {
            let ordered = model.ordered
            guard let a = ordered.firstIndex(where: { $0.id == anchor }),
                  let b = ordered.firstIndex(where: { $0.id == entry.id }) else { return toggleSelection(entry) }
            model.selected.formUnion(ordered[min(a, b)...max(a, b)].map(\.id))
        } else if !model.selected.isEmpty {
            model.selected = []
            model.selectionAnchor = nil
        } else {
            paste(entry)
        }
    }

    private func toggleSelection(_ entry: ClipNoteStackEntry) {
        if model.selected.contains(entry.id) {
            model.selected.remove(entry.id)
        } else {
            model.selected.insert(entry.id)
        }
        model.selectionAnchor = entry.id
    }

    /// Pastes the row into the app in front now (only copies without Accessibility).
    private func paste(_ entry: ClipNoteStackEntry) {
        guard let full = store.item(id: entry.item.id) else { return }
        armed = nil
        ClipNotePasteboard.write(full, mode: .original, store: store, monitor: monitor) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.armed = (entry.id, NSPasteboard.general.changeCount)
                // The watcher hears this ⌘V too, and moves on to the next row.
                if self.model.canAutoPaste { ClipNotePasteboard.pasteIntoFrontApp() }
            }
        }
    }

    private func remove(_ entry: ClipNoteStackEntry) {
        withAnimation(.easeOut(duration: 0.2)) {
            model.entries.removeAll { $0.id == entry.id }
            model.selected.remove(entry.id)
        }
        syncPasteboard()
    }

    private func clear() {
        withAnimation(.easeOut(duration: 0.2)) {
            model.entries = []
            model.selected = []
        }
        armed = nil
    }

    private func toggleOrder() {
        preferences.stackLIFO.toggle()
        withAnimation(.easeOut(duration: 0.25)) { model.lifo = preferences.stackLIFO }
        syncPasteboard()
    }

    /// Joins the selected rows, in list order, into one text that takes the
    /// place of the first of them.
    private func mergeSelected() {
        let chosen = model.ordered.filter { model.selected.contains($0.id) }
        let texts = chosen.compactMap { store.item(id: $0.item.id).flatMap(ClipNotePasteboard.plainText(of:)) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }
        let merged = texts.joined(separator: preferences.stackSeparator.string)
        let clip = NewClip(type: .text, content: merged, searchText: merged, sourceBundleID: Bundle.main.bundleIdentifier,
                           sourceAppName: AppInfo.name, charCount: merged.count, hash: ContentHash.forText(merged))
        guard let id = try? store.insert(clip), let item = store.item(id: id) else { return }

        let mergedEntry = ClipNoteStackEntry(item: item)
        withAnimation(.easeOut(duration: 0.25)) {
            // Placed where the first selected row is in paste order, then mapped back to copy order.
            var ordered = model.ordered
            let anchor = ordered.firstIndex { model.selected.contains($0.id) } ?? 0
            ordered.removeAll { model.selected.contains($0.id) }
            ordered.insert(mergedEntry, at: min(anchor, ordered.count))
            model.entries = model.lifo ? ordered.reversed() : ordered
            model.selected = []
        }
        armed = nil
        syncPasteboard()
    }

    func tearDown() {
        hide()
        watcher.stop()
    }
}
