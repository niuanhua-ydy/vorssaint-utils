// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import ClipNoteCore
import Combine
import SwiftUI

/// A panel that can become key without activating anything (like Spotlight).
final class ClipNoteFloatingPanel: NSPanel {
    var allowsKey = true

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The panel sits on the screen's bottom edge and its content slides
        // inside it; a window shadow would be recomputed every frame and flicker.
        hasShadow = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// The card panel along the bottom of the screen: showing and hiding, the
/// keyboard, pasting, and the preview window above it.
@MainActor
final class ClipNotePanelController: NSObject, NSWindowDelegate {
    /// Paste's measurements: 60 (top bar) + 8 + 232 (cards) + 33.
    static let panelHeight: CGFloat = 333

    /// Slides in from below the screen's edge while fading in, with no
    /// bounce, like Paste: cubic-bezier(0.32, 0.72, 0, 1), fast then settling.
    static let showAnimation = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.35)
    static let hideDuration = 0.25
    static let hideAnimation = Animation.timingCurve(0.32, 0.72, 0, 1, duration: hideDuration)

    let model: ClipNotePanelModel
    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private let monitor: ClipNoteMonitor
    private let panel = ClipNoteFloatingPanel()
    private let previewPanel = ClipNoteFloatingPanel()
    private let previewModel = ClipNotePreviewModel()
    /// The filter popover, a window of its own so it can stand above the
    /// panel like Paste's. It never takes key: typing stays in the search field.
    private let filterPanel = ClipNoteFloatingPanel()
    private var filterObserver: AnyCancellable?
    let ai: ClipNoteAIController
    private let textEditor: ClipNoteEditController
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// A held Delete that began editing the search keeps editing it, and
    /// never runs on into the items once the field is empty.
    private var deleteHoldBeganInSearch = false
    /// Where the mouse went down on a card (window coordinates), and that
    /// card; past a few points of movement the card is dragged out.
    private var dragStart: (point: NSPoint, item: ClipItem)?
    /// What is being dragged out, which decides the operations offered.
    private var draggingType: ClipType?
    private var clockTimer: Timer?
    private let idleRelease = IdleResourceRelease()
    private var previousApp: NSRunningApplication?
    private var selectionObserver: AnyCancellable?
    /// Opens Settings at a tab, or where it was when nil.
    var onOpenSettings: ((ClipNoteSettingsTab?) -> Void)?
    var onShow: (() -> Void)?

    init(store: ClipStore, preferences: ClipNotePreferences, monitor: ClipNoteMonitor) {
        self.store = store
        self.preferences = preferences
        self.monitor = monitor
        model = ClipNotePanelModel(store: store)
        ai = ClipNoteAIController(store: store, preferences: preferences, monitor: monitor)
        textEditor = ClipNoteEditController(store: store)
        super.init()

        ensurePanelContent()

        model.onPaste = { [weak self] item, mode in self?.paste(item, mode: mode) }
        model.onCopy = { [weak self] item in self?.copy(item) }
        model.onPreview = { [weak self] item in self?.togglePreview(item) }
        model.onEdit = { [weak self] item in self?.edit(item) }
        model.onOpenSettings = { [weak self] in
            self?.hide(restoreFocus: false)
            self?.onOpenSettings?(nil)
        }
        model.onAIAction = { [weak self] item, action in self?.runAI(action, on: item) }
        model.onAICustom = { [weak self] item in self?.beginCustomAI(on: item) }
        ai.onPasteText = { [weak self] item, text in self?.paste(item, mode: .transformed(text)) }
        ai.onOpenSettings = { [weak self] in
            self?.hide(restoreFocus: false)
            self?.onOpenSettings?(.ai)
        }
        // After the AI window closes, the panel takes the keyboard back.
        ai.onClosed = { [weak self] in
            guard let self, self.model.isPresented else { return }
            self.panel.makeKey()
        }
        // The edited text is a new item; the selection follows it.
        textEditor.onSaved = { [weak self] id in self?.model.selectedID = id }
        textEditor.onClosed = { [weak self] in
            guard let self, self.model.isPresented else { return }
            self.panel.makeKey()
        }
        model.onClearHistory = { [weak self] in self?.confirmClearHistory() }
        model.onFocusSearch = { [weak self] in self?.focusSearch() }

        // A safety net: when the window becomes visible, force one refresh in
        // case SwiftUI held back updates while it was hidden.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.occlusionState.contains(.visible) else { return }
                self.model.objectWillChange.send()
                self.panel.contentView?.needsDisplay = true
            }
        })

        // The popover opens and closes with the model, and refits when what it lists changes.
        filterObserver = model.$isFilterOpen.combineLatest(model.$showsAllApps, model.$sourceApps, model.$pinboards)
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.syncFilterPanel() } }
            }

        // An open preview follows the selection.
        selectionObserver = model.$selectedID.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.syncPreviewWithSelection() } }
        }

        warmUp()
        scheduleIdleRelease()
        installEventMonitors()

        // Switching to another app (a click elsewhere, ⌘⇥) hides the panel.
        // Only the app losing front counts, not the window losing key: an
        // input source switch takes focus for a moment and must not close it.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appDidResignActive() }
        })
    }

    /// `consumes` answers on the main thread whether the event stops here.
    private func addMonitor(_ mask: NSEvent.EventTypeMask, _ consumes: @escaping @MainActor (NSEvent) -> Bool) {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { consumes(event) } ? nil : event
        }
        if let monitor { eventMonitors.append(monitor) }
    }

    private func installEventMonitors() {
        addMonitor(.keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return false }
            return self.handleKey(event)
        }

        // A click anywhere else on the panel closes the filter popover; the
        // filter button toggles it itself.
        addMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.panel, self.model.isFilterOpen,
                  let content = self.panel.contentView else { return false }
            let location = event.locationInWindow
            let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
            if !self.model.filterButtonFrame.contains(point) {
                self.model.isFilterOpen = false
            }
            return false
        }

        // A click outside a title or pinboard name being edited saves it first.
        addMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.panel, self.isEditingText else { return false }
            if let editor = self.panel.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
               field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                return false
            }
            self.commitPendingEdits()
            return false
        }

        // Holding ⌘ shows the number shortcuts on the cards.
        addMonitor(.flagsChanged) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return false }
            let holding = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            if self.model.showShortcuts != holding { self.model.showShortcuts = holding }
            return false
        }

        // Cards dragged out to other apps (Finder, a browser upload, a chat).
        addMonitor([.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.panel else { return false }
            return self.handleDragEvent(event)
        }

        // A wheel's vertical scroll moves the strip of cards sideways.
        addMonitor(.scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return false }
            return ClipNoteScrollRedirect.handle(event, in: self.panel) == nil
        }

        // A click on the empty desktop lands on a catcher and hides the panel.
        addMonitor([.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let window = event.window,
                  self.desktopCatchers.contains(where: { $0 === window }) else { return false }
            self.hide()
            return true
        }
    }

    // MARK: - Desktop clicks

    /// Clear windows just above the wallpaper, one per screen, while the panel
    /// is open. A click on the empty desktop makes no app active (with desktop
    /// icons off nothing owns it, and other apps' clicks never reach a global
    /// monitor), so the resign-active path never hears of it; it reaches these
    /// instead. They sit below Finder's icons and every other window, so a
    /// click on anything else goes where it always did.
    private var desktopCatchers: [NSPanel] = []

    private func showDesktopCatchers() {
        hideDesktopCatchers()
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        desktopCatchers = NSScreen.screens.map { screen in
            let catcher = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            catcher.level = level
            catcher.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            catcher.isOpaque = false
            catcher.backgroundColor = .clear
            catcher.hasShadow = false
            // Set explicitly, a clear window takes clicks rather than passing them through.
            catcher.ignoresMouseEvents = false
            catcher.animationBehavior = .none
            catcher.isReleasedWhenClosed = false
            catcher.setFrame(screen.frame, display: false)
            catcher.orderFrontRegardless()
            return catcher
        }
    }

    private func hideDesktopCatchers() {
        desktopCatchers.forEach { $0.orderOut(nil) }
        desktopCatchers = []
    }

    /// Removes every monitor and window; the controller is done after this.
    func tearDown() {
        hide(restoreFocus: false)
        idleRelease.cancel()
        ai.tearDown()
        textEditor.tearDown()
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        selectionObserver = nil
        filterObserver = nil
        clockTimer?.invalidate()
        clockTimer = nil
        panel.orderOut(nil)
        previewPanel.orderOut(nil)
        filterPanel.orderOut(nil)
    }

    /// Along the very bottom of the screen and its full width, over the Dock, like Paste.
    static func targetFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: panelHeight)
    }

    /// Rebuild only disposable view trees; panel state and recording survive idle release.
    private func ensurePanelContent() {
        guard !(panel.contentView is NSHostingView<ClipNotePanelView>) else { return }
        let hosting = NSHostingView(rootView: ClipNotePanelView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self

        previewPanel.allowsKey = false
        let previewHosting = NSHostingView(rootView: ClipNotePreviewView(model: previewModel, store: store))
        previewHosting.sizingOptions = []
        previewPanel.contentView = previewHosting

        filterPanel.allowsKey = false
        filterPanel.hasShadow = true
        let filterHosting = ClipNoteFirstMouseHostingView(rootView: ClipNoteFilterPopover(model: model))
        // Measured by its intrinsic size (with no sizing options a hosting
        // view measures 0 × 0); the frame is still set by hand.
        filterHosting.sizingOptions = [.intrinsicContentSize]
        filterPanel.contentView = filterHosting
    }

    private func scheduleIdleRelease() {
        idleRelease.schedule { [weak self] in
            guard let self, !self.model.isPresented, !self.panel.isVisible else { return }
            self.panel.contentView = nil
            self.previewPanel.contentView = nil
            self.filterPanel.contentView = nil
            self.model.releaseIdleResources()
            ClipNoteThumbnails.shared.removeAll()
            ClipNoteAppIcons.removeAll()
            ClipNoteFileIcons.removeAll()
            self.ai.releaseHiddenView()
            self.textEditor.releaseHiddenView()
        }
    }

    /// Preserve the fast initial opening within the idle grace period.
    private func warmUp() {
        if let screen = NSScreen.main { panel.setFrame(Self.targetFrame(on: screen), display: false) }
        model.reload(resetSelection: true, synchronous: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    var isVisible: Bool { panel.isVisible && model.isPresented }

    /// The panel window while it is open, so another window can sit above it.
    var visibleWindow: NSWindow? { isVisible ? panel : nil }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Bumped to cancel a slide out still running when the panel reopens.
    private var presentationGeneration = 0

    func show() {
        idleRelease.cancel()
        ensurePanelContent()
        guard !panel.isVisible || !model.isPresented else { return }
        presentationGeneration += 1
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        model.pasteTarget = preferences.autoPaste
            ? previousApp.flatMap { app in app.localizedName.map { ($0, app.bundleIdentifier) } }
            : nil

        model.prepareForShow()
        onShow?()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }
        let target = Self.targetFrame(on: screen)
        if panel.frame != target { panel.setFrame(target, display: false) }
        // The window stays opaque: one at alpha 0 counts as invisible, SwiftUI
        // pauses it, and the slide in stalls. The fade is SwiftUI's alone.
        panel.alphaValue = 1
        // Vorssaint becomes the active app, as Paste does: input sources and
        // other system services follow the active app, so switching input
        // methods in the search field would otherwise send focus back. Focus
        // returns to the previous app on hiding. Activating also brings every
        // open Vorssaint window forward (a Settings window hidden behind other
        // apps, say), so those are parked offscreen first and put back on
        // hiding; only the panel appears.
        if !NSApp.isActive { parkBackgroundWindows() }
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
        showDesktopCatchers()
        focusSearch()

        // The slide in starts once the window is really on screen, or it
        // commits while invisible and stalls.
        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.presentationGeneration else { return }
                withAnimation(Self.showAnimation) {
                    self.model.isPresented = true
                }
            }
        }

        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.now = Date() }
        }
    }

    /// Ordinary windows on screen (every app's), front to back.
    private static func onScreenWindowNumbers() -> [Int] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { $0[kCGWindowNumber as String] as? Int }
    }

    /// Vorssaint windows parked offscreen (front to back), each with the window that was just in front of it.
    private var parkedWindows: [(window: NSWindow, below: Int?)] = []

    private func parkBackgroundWindows() {
        let windows = NSApp.orderedWindows.filter { $0 !== panel && $0.isVisible && $0.styleMask.contains(.titled) }
        guard !windows.isEmpty else { return }
        let onScreen = Self.onScreenWindowNumbers()
        parkedWindows = windows.map { window in
            let index = onScreen.firstIndex(of: window.windowNumber)
            return (window, index.flatMap { $0 > 0 ? onScreen[$0 - 1] : nil })
        }
        windows.forEach { $0.orderOut(nil) }
    }

    /// Back where they were (behind everything if their neighbor closed),
    /// never raised above other apps.
    private func restoreParkedWindows() {
        guard !parkedWindows.isEmpty else { return }
        var onScreen = Set(Self.onScreenWindowNumbers())
        for (window, below) in parkedWindows where !window.isVisible {
            if let below, onScreen.contains(below) {
                window.order(.below, relativeTo: below)
            } else {
                window.orderBack(nil)
            }
            onScreen.insert(window.windowNumber)
        }
        parkedWindows = []
    }

    /// Slides out; `completion` runs once the window is gone. `restoreFocus`
    /// hands focus back to the app that was in front (not needed when the
    /// user already switched elsewhere).
    func hide(restoreFocus: Bool = true, completion: (() -> Void)? = nil) {
        restoreParkedWindows()
        hideDesktopCatchers()
        guard panel.isVisible, model.isPresented else {
            completion?()
            return
        }
        // A title or pinboard name being edited is saved first.
        commitPendingEdits()
        presentationGeneration += 1
        let generation = presentationGeneration
        clockTimer?.invalidate()
        clockTimer = nil
        ClipNoteScrollRedirect.scroller.stop()
        hidePreview()
        model.isFilterOpen = false
        filterPanel.orderOut(nil)
        withAnimation(Self.hideAnimation) {
            model.isPresented = false
        }
        ai.close()
        textEditor.close(saving: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.presentationGeneration else { return }
                self.panel.orderOut(nil)
                self.model.didHide()
                self.scheduleIdleRelease()
                if restoreFocus {
                    self.restorePreviousApp { completion?() }
                } else {
                    completion?()
                }
            }
        }
    }

    /// Gives focus back to the app in front before the panel, and waits (up
    /// to 0.6 s) until it really is in front.
    private func restorePreviousApp(then completion: @escaping () -> Void) {
        guard NSApp.isActive, let previousApp, !previousApp.isTerminated else {
            completion()
            return
        }
        ActivationHandoff.yield(to: previousApp)
        previousApp.activate()
        waitUntilFrontmost(previousApp, deadline: Date().addingTimeInterval(0.6), then: completion)
    }

    private func waitUntilFrontmost(_ app: NSRunningApplication, deadline: Date, then completion: @escaping () -> Void) {
        if NSWorkspace.shared.frontmostApplication == app || Date() > deadline {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            MainActor.assumeIsolated { self?.waitUntilFrontmost(app, deadline: deadline, then: completion) }
        }
    }

    private var isEditingText: Bool { model.editingTitleID != nil || model.editor != nil }

    /// Moving focus off the editing field saves it.
    private func commitPendingEdits() {
        guard isEditingText else { return }
        focusSearch()
    }

    // MARK: - NSWindowDelegate

    /// A fallback for when activation was refused: hide on losing key.
    func windowDidResignKey(_ notification: Notification) {
        guard !NSApp.isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.isPresented, !self.panel.isKeyWindow, !NSApp.isActive else { return }
                self.hide(restoreFocus: false)
            }
        }
    }

    private func appDidResignActive() {
        guard model.isPresented else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.isPresented, !NSApp.isActive else { return }
                self.hide(restoreFocus: false)
            }
        }
    }

    func focusSearch() {
        if let field = model.searchField {
            panel.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
    }

    // MARK: - Pasting

    private func paste(_ item: ClipItem, mode: ClipNotePasteMode) {
        guard let full = store.item(id: item.id) else { return }
        let autoPaste = preferences.autoPaste
        ClipNotePasteboard.write(full, mode: mode, store: store, monitor: monitor) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .transformed = mode {} else { self.store.markUsed(id: full.id) }
                // Focus goes back first (hide waits for it), then ⌘V.
                self.hide {
                    if autoPaste { ClipNotePasteboard.pasteIntoFrontApp() }
                }
            }
        }
    }

    private func copy(_ item: ClipItem) {
        guard let full = store.item(id: item.id) else { return }
        ClipNotePasteboard.write(full, mode: .original, store: store, monitor: monitor)
        store.markUsed(id: full.id)
        hide()
    }

    private func confirmClearHistory() {
        hide(restoreFocus: false) { [weak self] in self?.runClearHistoryAlert() }
    }

    func runClearHistoryAlert() {
        let strings = FeatureStrings.clipNote(L10n.shared.language)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = strings.clearHistoryTitle
        alert.informativeText = strings.clearHistoryMessage
        alert.addButton(withTitle: strings.clear)
        alert.addButton(withTitle: strings.cancel)
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearHistory(keepPinned: true)
        }
    }

    // MARK: - Preview

    private func togglePreview(_ item: ClipItem) {
        if previewPanel.isVisible && previewModel.item?.id == item.id {
            hidePreview()
        } else {
            showPreview(item)
        }
    }

    private func showPreview(_ item: ClipItem) {
        ai.close()
        previewModel.item = store.item(id: item.id) ?? item
        guard let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let width = min(900, visible.width * 0.6)
        let height = min(560, visible.height - Self.panelHeight - 48)
        let frame = NSRect(x: visible.midX - width / 2, y: panel.frame.maxY + 12, width: width, height: height)
        previewPanel.setFrame(frame, display: true)
        previewPanel.orderFrontRegardless()
    }

    private func hidePreview() {
        guard previewPanel.isVisible else { return }
        previewPanel.orderOut(nil)
        previewModel.item = nil
    }

    private func syncPreviewWithSelection() {
        guard previewPanel.isVisible, let item = model.selectedItem else { return }
        previewModel.item = store.item(id: item.id) ?? item
    }

    // MARK: - Filter popover

    /// Shows the popover above the filter button, its arrow on the button,
    /// sized to what it lists; or hides it.
    private func syncFilterPanel() {
        guard model.isFilterOpen, model.isPresented, let screen = panel.screen,
              let hosting = filterPanel.contentView else {
            filterPanel.orderOut(nil)
            return
        }
        let button = model.filterButtonFrame
        let anchorX = panel.frame.minX + button.midX
        let buttonTop = panel.frame.maxY - button.minY
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else {
            filterPanel.orderOut(nil)
            return
        }
        let margin: CGFloat = 8
        let x = min(max(anchorX - size.width / 2, screen.frame.minX + margin), screen.frame.maxX - size.width - margin)
        let arrowX = anchorX - x
        if model.filterArrowX != arrowX { model.filterArrowX = arrowX }
        filterPanel.setFrame(NSRect(x: x, y: buttonTop + 4, width: size.width, height: size.height), display: true)
        if !filterPanel.isVisible { filterPanel.orderFrontRegardless() }
    }

    // MARK: - Dragging cards out

    /// True once a drag has started and the event is used.
    private func handleDragEvent(_ event: NSEvent) -> Bool {
        guard let hosting = panel.contentView else { return false }
        switch event.type {
        case .leftMouseDown:
            dragStart = nil
            guard model.isPresented, !isEditingText else { return false }
            // SwiftUI puts the origin top left.
            var point = hosting.convert(event.locationInWindow, from: nil)
            if !hosting.isFlipped { point.y = hosting.bounds.height - point.y }
            if let item = model.card(at: point) { dragStart = (event.locationInWindow, item) }
        case .leftMouseDragged:
            guard let start = dragStart else { return false }
            let distance = hypot(event.locationInWindow.x - start.point.x, event.locationInWindow.y - start.point.y)
            guard distance >= 4 else { return false }
            dragStart = nil
            return beginDrag(start.item, event: event, in: hosting)
        default:
            dragStart = nil
        }
        return false
    }

    private func beginDrag(_ item: ClipItem, event: NSEvent, in view: NSView) -> Bool {
        let strings = FeatureStrings.clipNote(L10n.shared.language)
        guard let full = store.item(id: item.id),
              let writers = ClipNoteDragExport.writers(for: full, store: store, strings: strings) else {
            NSSound.beep()
            return false
        }
        model.select(item)
        hidePreview()
        let image = ClipNoteDragExport.dragImage(for: full, store: store, strings: strings)
        let point = view.convert(event.locationInWindow, from: nil)
        let items = writers.enumerated().map { index, writer in
            let dragItem = NSDraggingItem(pasteboardWriter: writer)
            // The pointer sits at the image's center; several files show one image with a count.
            let frame = NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                               width: image.size.width, height: image.size.height)
            dragItem.setDraggingFrame(frame, contents: index == 0 ? image : nil)
            return dragItem
        }
        draggingType = full.type
        let session = view.beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        return true
    }

    // MARK: - AI

    private func runAI(_ action: ClipNoteAIAction, on item: ClipItem) {
        hidePreview()
        textEditor.close(saving: true)
        model.select(item)
        ai.run(action, on: item, above: panel)
    }

    private func beginCustomAI(on item: ClipItem) {
        hidePreview()
        textEditor.close(saving: true)
        model.select(item)
        ai.beginCustom(on: item, above: panel)
    }

    /// Opens a text item in the editor window above the panel.
    private func edit(_ item: ClipItem) {
        guard ClipNoteEditController.isAvailable(for: item) else { return }
        hidePreview()
        ai.close()
        model.select(item)
        textEditor.edit(item, above: panel)
    }

    // MARK: - Keyboard

    private var searchFieldHasSelection: Bool {
        guard let editor = panel.firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length > 0
    }

    /// The standard editing keys in a text view; the editor window uses them too.
    static func handleTextEditingKey(_ keyCode: Int, flags: NSEvent.ModifierFlags, editor: NSTextView) -> Bool {
        let hasSelection = editor.selectedRange().length > 0
        switch (keyCode, flags) {
        case (kVK_ANSI_A, .command), (kVK_ANSI_A, .control):
            editor.selectAll(nil)
        case (kVK_ANSI_X, .command):
            guard hasSelection else { return false }
            editor.cut(nil)
        case (kVK_ANSI_C, .command):
            // With no text selected, ⌘C copies the selected card (handled below).
            guard hasSelection else { return false }
            editor.copy(nil)
        case (kVK_ANSI_V, .command):
            editor.pasteAsPlainText(nil)
        case (kVK_ANSI_Z, .command):
            editor.undoManager?.undo()
        case (kVK_ANSI_Z, [.command, .shift]):
            editor.undoManager?.redo()
        default:
            return false
        }
        return true
    }

    /// True when the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let keyCode = Int(event.keyCode)

        // While an input method is composing, every key is its own: space and
        // Return commit, arrows and digits pick, Escape cancels.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }

        // The standard editing keys in a field (select all, cut, copy, paste,
        // undo); the panel has no Edit menu to route them. ⌃A selects all too,
        // over macOS's own "move to line start".
        if let editor = panel.firstResponder as? NSTextView, Self.handleTextEditingKey(keyCode, flags: flags, editor: editor) {
            return true
        }

        // While a card title is edited, only Escape is the panel's.
        if model.editingTitleID != nil {
            if keyCode == kVK_Escape {
                model.cancelEditingTitle()
                return true
            }
            return false
        }

        // Likewise while a pinboard is named.
        if model.editor != nil {
            if keyCode == kVK_Escape {
                model.cancelEditor()
                return true
            }
            return false
        }

        if ClipNotePanelKeys.isDelete(keyCode), !event.isARepeat {
            deleteHoldBeganInSearch = !model.query.isEmpty
        }
        // Delete in the open, empty search field takes off the last filter token.
        if keyCode == kVK_Delete, flags.isEmpty, !event.isARepeat, model.isSearchActive,
           model.query.isEmpty, model.hasActiveFilter {
            model.removeLastFilter()
            return true
        }
        if ClipNotePanelKeys.deletesItem(keyCode: keyCode, command: flags.contains(.command),
                                         otherModifiers: !flags.subtracting(.command).isEmpty,
                                         isRepeat: event.isARepeat, queryIsEmpty: model.query.isEmpty,
                                         searchIsOpen: model.isSearchActive,
                                         holdBeganInSearch: deleteHoldBeganInSearch,
                                         needsCommand: preferences.deleteNeedsCommand) {
            model.delete()
            return true
        }

        switch keyCode {
        case kVK_Escape:
            if model.isFilterOpen {
                model.isFilterOpen = false
            } else if ai.isVisible {
                ai.close()
            } else if textEditor.isVisible {
                textEditor.close(saving: false)
            } else if previewPanel.isVisible {
                hidePreview()
            } else if !model.query.isEmpty {
                model.query = ""
            } else if model.hasActiveFilter {
                model.clearFilters()
            } else {
                hide()
            }
            return true

        case kVK_LeftArrow, kVK_RightArrow:
            guard flags.isEmpty || flags == .command else { return false }
            ClipNoteScrollRedirect.scroller.stop()
            let step = keyCode == kVK_LeftArrow ? -1 : 1
            if flags == .command {
                model.move(by: step * model.items.count)
            } else {
                model.move(by: step)
            }
            return true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.paste(mode: flags.contains(.shift) ? .plainText : .original)
            return true

        case kVK_Space where flags.isEmpty && model.query.isEmpty:
            if let item = model.selectedItem { togglePreview(item) }
            return true

        case kVK_Tab:
            model.switchTab(by: flags.contains(.shift) ? -1 : 1)
            return true

        default:
            break
        }

        guard flags.contains(.command) else { return false }

        // ⌘1…⌘9 paste that card (with ⇧, as plain text).
        let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                         kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        if let digit = digitKeys.firstIndex(of: keyCode) {
            model.paste(atIndex: digit, mode: flags.contains(.shift) ? .plainText : .original)
            return true
        }

        switch keyCode {
        case kVK_ANSI_C where !searchFieldHasSelection:
            model.copy()
            return true
        case kVK_ANSI_F:
            focusSearch()
            return true
        case kVK_ANSI_R where flags.contains(.shift):
            model.onSyncNow?()
            return true
        case kVK_ANSI_R:
            if let item = model.selectedItem { model.beginEditingTitle(item) }
            return true
        case kVK_ANSI_W:
            hide()
            return true
        case kVK_ANSI_Y:
            if let item = model.selectedItem { togglePreview(item) }
            return true
        case kVK_ANSI_E:
            if let item = model.selectedItem { edit(item) }
            return true
        case kVK_ANSI_Comma:
            model.onOpenSettings?()
            return true
        default:
            return false
        }
    }
}

extension ClipNotePanelController: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        // A user's own file is only ever copied, so Finder cannot move it
        // away; images (temporary copies) and text are up to the target.
        return draggingType == .file ? .copy : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingType = nil
    }
}
