// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// While the pointer rests on the capture preview, its keys act on it without
/// the preview ever taking the keyboard: E edits, Command-C copies and so on,
/// and the app being typed into keeps its caret. Taking key focus on hover
/// would cost that caret (#1089), so instead this active tap swallows just
/// the keys the preview answers to and lets every other key through.
///
/// The tap lives only while the pointer is over one preview. Without
/// Accessibility it cannot exist, and the preview keeps its click-to-focus
/// path. Main thread only.
enum ScreenshotPreviewHoverKeys {
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var handler: ((ScreenshotSupport.QuickPreviewKeyAction) -> Void)?
    private static var owner: UUID?
    /// Presses swallowed here, so their releases do not reach the app alone.
    private static var swallowedKeyCodes: Set<Int64> = []

    /// Starts answering keys for `owner`. Returns false when the tap cannot
    /// exist, in which case the caller keeps its ordinary event path.
    @discardableResult
    static func begin(owner newOwner: UUID,
                      _ newHandler: @escaping (ScreenshotSupport.QuickPreviewKeyAction) -> Void) -> Bool {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDown()
        }
        if tap == nil {
            guard AXIsProcessTrusted() else { return false }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            guard let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    ScreenshotPreviewHoverKeys.handle(type: type, event: event)
                },
                userInfo: nil
            ) else { return false }
            tap = created
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
        }
        owner = newOwner
        handler = newHandler
        return true
    }

    /// Ends `owner`'s session; a later preview that already took over keeps
    /// the tap. Safe to call when begin failed.
    static func end(owner endingOwner: UUID) {
        guard owner == endingOwner else { return }
        tearDown()
    }

    private static func tearDown() {
        owner = nil
        handler = nil
        swallowedKeyCodes.removeAll()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return swallowedKeyCodes.remove(keyCode) == nil ? Unmanaged.passUnretained(event) : nil
        }
        // A shortcut field that is recording owns every key, and a held
        // super key turns a plain letter into someone else's shortcut.
        guard type == .keyDown, let handler, !ShortcutCapture.isCapturing,
              !(SuperKeyService.isEngaged && SuperKeyService.shared.isHeld),
              let action = ScreenshotSupport.quickPreviewKeyAction(
                keyCode: Int(keyCode),
                modifiers: GlobalShortcutModifiers(cgFlags: event.flags),
                charactersIgnoringModifiers: NSEvent(cgEvent: event)?.charactersIgnoringModifiers)
        else { return Unmanaged.passUnretained(event) }
        swallowedKeyCodes.insert(keyCode)
        // A held key acts once; its autorepeats are only swallowed.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            // Off the tap callback: the action may close windows or open the
            // editor, which must not hold up the event stream.
            DispatchQueue.main.async { handler(action) }
        }
        return nil
    }
}
