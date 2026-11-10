// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Exercise production focus/routing and the real native search field in an
/// unordered, offscreen window. No global events or clipboard data are used.
enum ClipNotePanelSearchTests {
    final class Model: ObservableObject {
        @Published var query = ""
        @Published var isSearchExpanded = false
        weak var searchField: NSTextField?
    }

    class Fixture {
        let model = Model()
        let panel = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 333),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    private struct Content: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack {
                Text("Search")
                ClipNoteSearchField(text: $model.query, placeholder: "Search") { model.searchField = $0 }
                    .frame(width: model.isSearchExpanded ? 190 : 0)
                    .opacity(model.isSearchExpanded ? 1 : 0)
                Text("History")
            }
        }
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        MainActor.assumeIsolated { check(suite) }
    }

    @MainActor
    private static func check(_ suite: TestSuite) {
        let controller = Controller()
        let panel = controller.panel
        let model = controller.model
        func rebuild() {
            let hosting = NSHostingView(rootView: Content(model: model))
            hosting.sizingOptions = []
            panel.contentView = hosting
        }
        func key(_ characters: String, code: Int = kVK_ANSI_A, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: panel.windowNumber, context: nil, characters: characters,
                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
        }
        func type(_ text: String) {
            let event = key(text)
            controller.prepareSearchForTyping(event)
            panel.sendEvent(event)
        }
        defer {
            panel.makeFirstResponder(nil)
            panel.contentView = nil
        }

        rebuild()
        controller.focusSearch()
        suite.expect(model.searchField?.window === panel && model.searchField?.currentEditor() != nil,
                     "opening lays out and focuses the collapsed search before its first keystroke")
        suite.expect(!model.isSearchExpanded, "focusing on opening preserves the collapsed search layout")

        panel.makeFirstResponder(panel)
        type("a")
        suite.expect(model.isSearchExpanded && model.query == "a",
                     "typing after focus was lost opens search and keeps the first character")
        type("b")
        suite.expectEqual(model.query, "ab", "subsequent characters continue the same search")

        if let editor = model.searchField?.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: 0, length: 1))
            type("z")
            suite.expectEqual(model.query, "zb", "typing preserves the search selection instead of moving to the end")
        } else {
            suite.expect(false, "search keeps its native editor")
        }

        for event in [key("f", flags: .command), key("a", flags: .control),
                      key("\u{f702}", code: kVK_LeftArrow), key("\r", code: kVK_Return),
                      key("\t", code: kVK_Tab), key("\u{7f}", code: kVK_Delete), key("")] {
            panel.makeFirstResponder(panel)
            model.isSearchExpanded = false
            controller.prepareSearchForTyping(event)
            suite.expect(!model.isSearchExpanded && panel.firstResponder === panel,
                         "shortcuts, navigation, deletion and empty events do not take search focus")
        }
        for event in [key("A", flags: .shift), key("e", flags: .option), key("中"), key("🙂")] {
            controller.prepareSearchForTyping(event)
            suite.expect(model.isSearchExpanded && model.searchField?.currentEditor() != nil,
                         "shifted, option/dead-key, Chinese and emoji input can start search")
            model.isSearchExpanded = false
            panel.makeFirstResponder(panel)
        }

        // Simulate idle release: the next view has not registered its field yet.
        panel.makeFirstResponder(nil)
        panel.contentView = nil
        model.searchField = nil
        model.query = ""
        rebuild()
        controller.focusSearch()
        type("中")
        suite.expectEqual(model.query, "中", "a rebuilt panel accepts the first committed Chinese character")
    }
}
