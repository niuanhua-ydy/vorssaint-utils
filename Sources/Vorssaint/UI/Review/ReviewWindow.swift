// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The two reviews the command bar hands off - an app's leftover files and the
/// junk cleaner - in a window that outlives a loss of focus. The bar is for a
/// decision and its result; a review is a place to read, tick and watch, so it
/// gets the room and the lifetime to match. One window at a time; asking for
/// the same review again brings it forward, and the scan belongs to the
/// service behind it, so closing and opening never throws it away.
final class ReviewWindow: NSObject, NSWindowDelegate {
    enum Kind {
        case uninstaller, cleaner

        var title: String {
            switch self {
            case .uninstaller: return L10n.shared.s.uninstallerName
            case .cleaner: return L10n.shared.s.cleanerName
            }
        }

        var size: NSSize {
            switch self {
            case .uninstaller: return NSSize(width: 620, height: 700)
            case .cleaner: return NSSize(width: 560, height: 700)
            }
        }

        var minSize: NSSize {
            switch self {
            case .uninstaller: return NSSize(width: 500, height: 480)
            case .cleaner: return NSSize(width: 460, height: 480)
            }
        }

        var autosaveName: String {
            switch self {
            case .uninstaller: return "UninstallerReviewWindow"
            case .cleaner: return "CleanerReviewWindow"
            }
        }

        @ViewBuilder var content: some View {
            switch self {
            case .uninstaller: UninstallerView()
            case .cleaner: CleanerView()
            }
        }
    }

    static let shared = ReviewWindow()
    private var window: NSWindow?
    private var kind: Kind?

    func show(_ kind: Kind) {
        if let window, self.kind == kind {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // The other review's window is replaced; whatever it was showing lives
        // in its service, so asking for it again returns to the same step.
        window?.close()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: kind.size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = kind.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: kind.content)
        window.contentMinSize = kind.minSize
        window.setFrameAutosaveName(kind.autosaveName)
        if window.frame.origin == .zero { window.center() }
        self.window = window
        self.kind = kind
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        kind = nil
    }
}
