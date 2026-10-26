// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

/// The translation window, modeled on Bob: one floating panel opened on the
/// selection, on typed text or on a picked area of the screen. It never
/// takes the app in front away from the person, so the selection stays
/// readable and Return goes back to where they were. Unpinned, a click
/// anywhere else puts it away; pinned, it stays beside what is being read.
final class TranslatorService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = TranslatorService()

    @Published private(set) var isPinned = UserDefaults.standard.bool(forKey: DefaultsKey.translatorPinned)
    @Published private(set) var refusedShortcuts: Set<String> = []
    let model = TranslatorModel()

    private let selectionHotkey = QuickToolHotkey(id: 95)
    private let inputHotkey = QuickToolHotkey(id: 96)
    private let screenshotHotkey = QuickToolHotkey(id: 97)
    private var panel: TranslatorPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    /// The top edge the window grows down from, as results come in.
    private var anchoredTop: CGFloat?
    private let speech = AVSpeechSynthesizer()
    private var selectionRead = 0

    private var text: TranslatorStrings { .strings(L10n.shared.language) }

    private override init() {
        super.init()
        selectionHotkey.onPress = { [weak self] in self?.translateSelection() }
        inputHotkey.onPress = { [weak self] in self?.translateInput() }
        screenshotHotkey.onPress = { [weak self] in self?.translateScreenshot() }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func syncWithPreferences() {
        let available = AppFeature.commandBar.isAvailable
        var refused: Set<String> = []
        for (hotkey, role) in [(selectionHotkey, GlobalShortcutRole.translatorSelection),
                               (inputHotkey, .translatorInput), (screenshotHotkey, .translatorScreenshot)] {
            let enabled = available && role.requiredEnableKeys.allSatisfy { UserDefaults.standard.bool(forKey: $0) }
            if !hotkey.sync(enabled: enabled, shortcut: role.savedShortcut, storageKey: role.storageKey) {
                refused.insert(role.storageKey)
            }
        }
        refusedShortcuts = refused
        if !available { close() }
    }

    func suspend() {
        selectionHotkey.unregister()
        inputHotkey.unregister()
        screenshotHotkey.unregister()
        close()
    }

    // MARK: Opening

    /// Reads what is selected in the app in front and translates it.
    func translateSelection() {
        guard AppFeature.commandBar.isAvailable else { return }
        selectionRead += 1
        let read = selectionRead
        let trusted = AXIsProcessTrusted()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let selection = CommandBarSelectionReader.readSelection().text
            DispatchQueue.main.async {
                guard let self, self.selectionRead == read else { return }
                if selection.isEmpty {
                    self.show(text: "", notice: trusted ? self.text.noSelection : self.text.needsAccessibility)
                    if !trusted { Permissions.shared.requestAccessibility() }
                } else {
                    self.show(text: selection)
                }
            }
        }
    }

    func translateInput() {
        guard AppFeature.commandBar.isAvailable else { return }
        show(text: "")
    }

    func translateScreenshot() {
        guard AppFeature.commandBar.isAvailable else { return }
        guard AppFeature.screenOCR.isAvailable else {
            QuickToolHUD.show(icon: "text.viewfinder", message: text.ocrUnavailable)
            return
        }
        // The window would otherwise sit in the area being picked.
        if !isPinned { close() }
        ScreenTextService.shared.captureForTranslation()
    }

    func show(text value: String, notice: String? = nil) {
        guard AppFeature.commandBar.isAvailable else { return }
        let wasVisible = isVisible
        let panel = ensurePanel()
        model.open(text: value, notice: notice)
        if !wasVisible {
            place(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
        panel.makeKey()
        installMonitors()
        focusInput()
    }

    func close() {
        speech.stopSpeaking(at: .immediate)
        removeMonitors()
        panel?.orderOut(nil)
        model.reset()
    }

    func togglePin() {
        isPinned.toggle()
        UserDefaults.standard.set(isPinned, forKey: DefaultsKey.translatorPinned)
    }

    func openSettings() {
        if !isPinned { close() }
        SettingsRouter.shared.page = .commandBar
        appDelegate()?.openSettingsWindow()
    }

    func copy(_ value: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.declareVorssaintSource()
        board.setString(value, forType: .string)
    }

    func speak(_ value: String, language: TranslatorLanguage?) {
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: String(value.prefix(4_000)))
        if let language, let voice = AVSpeechSynthesisVoice(language: language.speechCode) {
            utterance.voice = voice
        }
        speech.speak(utterance)
    }

    // MARK: Window

    private final class TranslatorPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> TranslatorPanel {
        if let panel { return panel }
        let panel = TranslatorPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered,
                                    defer: false)
        panel.title = text.title
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        let host = NSHostingController(rootView: TranslatorView(model: model, service: self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Below and to the right of the pointer, where the eye already is,
    /// kept fully on the screen the pointer is on.
    private func place(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let visible = NSScreen.pointerVisibleFrame
        let pointer = NSEvent.mouseLocation
        let top = min(max(pointer.y - 16, visible.minY + 240), visible.maxY - 8)
        var origin = CGPoint(x: pointer.x + 12, y: top - size.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        anchoredTop = top
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, let top = anchoredTop else { return }
        // The window grows downward from a fixed top edge, and never off screen.
        let visible = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let y = max(top - panel.frame.height, visible.minY + 8)
        if abs(panel.frame.origin.y - y) > 0.5 { panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: y)) }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        anchoredTop = panel.frame.maxY
    }

    private func focusInput() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let field = Self.firstTextView(in: panel.contentView) else { return }
            panel.makeFirstResponder(field)
        }
    }

    private static func firstTextView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSTextView || view is NSTextField, view.acceptsFirstResponder { return view }
        for child in view.subviews { if let found = firstTextView(in: child) { return found } }
        return nil
    }

    // MARK: Keys and clicks

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            return self.handle(event, in: panel)
        }
        // A click outside, in another app or on another of our windows, puts
        // an unpinned window away.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isPinned else { return }
            self.close()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    /// The panel never makes the app active, so the menu's key equivalents
    /// do not reach it; the editing keys are answered here.
    private func handle(_ event: NSEvent, in panel: NSPanel) -> NSEvent? {
        let code = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if code == kVK_Escape {
            // Esc first leaves the input method's composition, then the window.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            close()
            return nil
        }
        let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter
        if isReturn, panel.firstResponder is NSTextView {
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            switch modifiers {
            case []:
                if !event.isARepeat { model.translate() }
                return nil
            case [.shift], [.option]:
                return NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: panel)
                    ? nil : event
            default: break
            }
        }
        guard modifiers == [.command] else { return event }
        if isReturn {
            if let result = model.primaryResult {
                copy(result)
                if !isPinned { close() }
            }
            return nil
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": close(); return nil
        case ",": openSettings(); return nil
        case "p": togglePin(); return nil
        case "s": model.swap(); return nil
        case "q", "m", "h": return nil
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: panel) ? nil : event
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: panel) ? nil : event
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: panel) ? nil : event
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: panel) ? nil : event
        case "z": return NSApp.sendAction(Selector(("undo:")), to: nil, from: panel) ? nil : event
        default: return event
        }
    }
}
