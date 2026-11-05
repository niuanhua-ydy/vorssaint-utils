// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import ClipNoteCore
import SwiftUI

@MainActor
final class ClipNoteEditModel: ObservableObject {
    @Published var item: ClipItem?
    @Published var text = ""
    /// Bumped to put the cursor in the text.
    @Published var focusRequest = 0
    var original = ""

    var hasChanges: Bool { text != original }
    var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
}

/// The window a text item is edited in, above the panel. Escape and Cancel
/// throw the changes away; Save (⌘S) or the panel closing keep them. The
/// edited text replaces the item (see `ClipStore.replaceContent`), so it
/// comes back under a new id at the front of the history.
@MainActor
final class ClipNoteEditController {
    let model = ClipNoteEditModel()
    private let store: ClipStore
    private let panel = ClipNoteFloatingPanel()
    private var keyMonitor: Any?

    /// The item as saved, so the panel can select it.
    var onSaved: ((Int64) -> Void)?
    /// After the window closes, so the panel can take the keyboard back.
    var onClosed: (() -> Void)?

    init(store: ClipStore) {
        self.store = store

        model.onSave = { [weak self] in self?.save() }
        model.onCancel = { [weak self] in self?.close(saving: false) }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.panel.isKeyWindow else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    func tearDown() {
        close(saving: false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    var isVisible: Bool { panel.isVisible }

    func releaseHiddenView() {
        guard !panel.isVisible else { return }
        panel.contentView = nil
    }

    private func ensureContent() {
        guard !(panel.contentView is NSHostingView<ClipNoteEditView>) else { return }
        let hosting = NSHostingView(rootView: ClipNoteEditView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    static func isAvailable(for item: ClipItem) -> Bool { item.type.isTextual }

    /// Opens the item's full text; the window sits above `anchor`.
    func edit(_ item: ClipItem, above anchor: NSWindow) {
        ensureContent()
        guard let full = store.item(id: item.id), Self.isAvailable(for: full) else { return }
        model.item = full
        model.text = full.content
        model.original = full.content
        guard let screen = anchor.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(760, visible.width * 0.6)
        let height = min(480, visible.height - ClipNotePanelController.panelHeight - 48)
        let frame = NSRect(x: visible.midX - width / 2, y: anchor.frame.maxY + 12, width: width, height: height)
        if !panel.isVisible || panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
        panel.makeKey()
        model.focusRequest += 1
    }

    /// `saving` keeps what was typed; closing unchanged saves nothing either way.
    func close(saving: Bool) {
        guard panel.isVisible else { return }
        if saving { commit() }
        panel.orderOut(nil)
        model.item = nil
        model.text = ""
        model.original = ""
        onClosed?()
    }

    private func save() {
        guard model.canSave else {
            NSSound.beep()
            return
        }
        close(saving: true)
    }

    private func commit() {
        guard let item = model.item, model.hasChanges, model.canSave else { return }
        let text = model.text
        // Classified as a fresh copy would be: a lone web address is a link.
        let clip: NewClip
        if let url = ClipNoteBuilder.linkURL(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            clip = NewClip(type: .link, content: url, searchText: url, sourceBundleID: item.sourceBundleID,
                           sourceAppName: item.sourceAppName, charCount: url.count, hash: ContentHash.forLink(url))
        } else {
            clip = NewClip(type: .text, content: text, searchText: text, sourceBundleID: item.sourceBundleID,
                           sourceAppName: item.sourceAppName, charCount: text.count, hash: ContentHash.forText(text))
        }
        guard let id = try? store.replaceContent(itemID: item.id, with: clip) else {
            NSSound.beep()
            return
        }
        onSaved?(id)
    }

    /// True when the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.contains(.command), let editor = panel.firstResponder as? NSTextView,
           ClipNotePanelController.handleTextEditingKey(Int(event.keyCode), flags: flags, editor: editor) {
            return true
        }
        switch (Int(event.keyCode), flags) {
        case (kVK_Escape, []), (kVK_ANSI_W, .command):
            close(saving: false)
        case (kVK_ANSI_S, .command), (kVK_Return, .command), (kVK_ANSI_KeypadEnter, .command):
            save()
        default:
            return false
        }
        return true
    }
}
