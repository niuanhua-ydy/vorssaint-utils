// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// SwiftUI's horizontal ScrollView ignores a mouse wheel's vertical scroll on
/// macOS, and its hosting scroll view ignores forwarded scroll events. The
/// vertical amount becomes the offset of the horizontal scroll view under the
/// pointer instead: eased at the display's refresh rate for a wheel, 1:1 for
/// a trackpad's precise deltas.
@MainActor
enum ClipNoteScrollRedirect {
    /// How far one wheel "line" moves the strip.
    static let lineScroll: CGFloat = 56

    static let scroller = ClipNoteSmoothScroller()

    /// Nil when the event was used; otherwise the event to pass on.
    static func handle(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let root = window.contentView,
              let scrollView = horizontalScrollView(at: root.convert(event.locationInWindow, from: nil), in: root)
        else { return event }
        if event.hasPreciseScrollingDeltas {
            scroller.scroll(scrollView, by: -event.scrollingDeltaY, animated: false)
        } else {
            scroller.scroll(scrollView, by: -event.scrollingDeltaY * lineScroll, animated: true)
        }
        return nil
    }

    static func clampedOffset(_ scrollView: NSScrollView, _ x: CGFloat) -> CGFloat {
        guard let document = scrollView.documentView else { return x }
        let minX = document.frame.minX
        let maxX = max(minX, document.frame.maxX - scrollView.contentView.bounds.width)
        return min(max(x, minX), maxX)
    }

    static func setOffset(_ scrollView: NSScrollView, _ x: CGFloat) {
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The nearest scroll view up from the hit view whose content is wider than it.
    static func horizontalScrollView(at point: NSPoint, in root: NSView) -> NSScrollView? {
        var view = root.hitTest(point)
        while let current = view {
            if let scrollView = current as? NSScrollView, let document = scrollView.documentView,
               document.frame.width > scrollView.contentView.bounds.width + 1 {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

/// Eased scrolling driven by a display link, so it runs at the display's own
/// rate (120 Hz on ProMotion).
@MainActor
final class ClipNoteSmoothScroller: NSObject {
    private weak var scrollView: NSScrollView?
    private var targetX: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    /// Higher closes in on the target faster.
    private let stiffness: Double = 14

    func scroll(_ scrollView: NSScrollView, by dx: CGFloat, animated: Bool) {
        if self.scrollView !== scrollView || displayLink == nil {
            // Start from wherever something else (a keyboard scrollTo) left it.
            self.scrollView = scrollView
            targetX = scrollView.contentView.bounds.origin.x
        }
        targetX = ClipNoteScrollRedirect.clampedOffset(scrollView, targetX + dx)
        if animated {
            start(on: scrollView)
        } else {
            stop()
            ClipNoteScrollRedirect.setOffset(scrollView, targetX)
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    private func start(on view: NSView) {
        guard displayLink == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else { return stop() }
        let dt = lastTimestamp == 0 ? 1.0 / 120 : min(link.timestamp - lastTimestamp, 1.0 / 30)
        lastTimestamp = link.timestamp
        let current = scrollView.contentView.bounds.origin.x
        let diff = targetX - current
        if abs(diff) < 0.5 {
            ClipNoteScrollRedirect.setOffset(scrollView, targetX)
            return stop()
        }
        // Exponential easing, independent of the frame rate.
        let t = CGFloat(1 - exp(-dt * stiffness))
        ClipNoteScrollRedirect.setOffset(scrollView, current + diff * t)
    }
}
