// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production preview Copy text handler and the latest-capture
/// bookkeeping with controlled collaborators. No native preview is created.
enum ScreenshotCaptureCompletionTests {
    struct PreviewCapture {
        let image: Int
    }

    final class ScreenTextService {
        static let shared = ScreenTextService()
        var copiedImages: [Int] = []
        func copyText(from image: Int) { copiedImages.append(image) }
    }

    /// Holds Copy text back while an after-capture copy is pending.
    final class ScreenshotService {
        static let shared = ScreenshotService()
        var autoCopyPending = false
        var waiting: [() -> Void] = []
        func afterAutoCopy(_ body: @escaping () -> Void) {
            if autoCopyPending { waiting.append(body) } else { body() }
        }
    }

    class State {
        var closed = false
        let capture = PreviewCapture(image: 42)
        func close() { closed = true }
    }

    enum AppFeature {
        case screenshot, screenOCR
        static var ocrAvailable = true
        var isAvailable: Bool { self == .screenOCR ? Self.ocrAvailable : true }
    }

    enum ScreenshotLastCaptureStore {
        static var stored: Int? = 1
        static func save(_ capture: Int) { stored = capture }
        static func clear() { stored = nil }
    }

    enum ScreenshotSelectionController {
        typealias Capture = Int
    }

    final class ScreenshotEditorController {
        let capture: Int
        var shown = false
        init(capture: Int) { self.capture = capture }
        func show() { shown = true }
    }

    enum WindowActivationPolicy {
        static var retained = 0
        static func retain() { retained += 1 }
        static func release() { retained -= 1 }
    }

    @MainActor class ServiceState {
        let defaultsName = "vorss.tests.screenshot-latest-capture.\(UUID().uuidString)"
        let defaults: UserDefaults
        var latestCaptureToken = UUID()
        var editors: [ScreenshotEditorController] = []
        var autoCopyTask: Task<Void, Never>?

        init() {
            defaults = UserDefaults(suiteName: defaultsName)!
            ScreenshotLastCaptureStore.stored = 1
        }
        deinit {
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await checks(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "screenshot capture completion tests finish")
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        ScreenTextService.shared.copiedImages = []
        ScreenshotService.shared.autoCopyPending = true
        ScreenshotService.shared.waiting = []
        let ocr = Controller()
        ocr.copyText()
        ocr.copyText()
        suite.expect(ocr.closed && ScreenTextService.shared.copiedImages.isEmpty
                     && ScreenshotService.shared.waiting.count == 1,
                     "Copy text closes at once and waits for a pending after-capture copy")
        ScreenshotService.shared.autoCopyPending = false
        ScreenshotService.shared.waiting.forEach { $0() }
        ScreenshotService.shared.waiting = []
        suite.expect(ScreenTextService.shared.copiedImages == [ocr.capture.image],
                     "preview OCR closes once and recognizes the full-resolution capture")
        AppFeature.ocrAvailable = false
        let disabledOCR = Controller()
        disabledOCR.copyText()
        suite.expect(!disabledOCR.closed && ScreenTextService.shared.copiedImages.count == 1,
                     "a stale OCR button cannot close the preview or start work after OCR is disabled")
        AppFeature.ocrAvailable = true

        let editing = Service()
        editing.openEditor(with: 1)
        editing.openEditor(with: 2)
        suite.expect(editing.editors.allSatisfy { $0.shown }, "editors are tracked when shown")
        let firstEditor = editing.editors[0]
        editing.editorDidClose(firstEditor)
        editing.editorDidClose(firstEditor)
        suite.expect(editing.editors.count == 1, "duplicate close preserves the remaining editor")

        // The capture is kept for the shortcut that reopens it, and only then.
        let retention = Service()
        ScreenshotLastCaptureStore.stored = nil
        retention.beginLatestCapture(8)
        suite.expect(ScreenshotLastCaptureStore.stored == nil,
                     "with the latest screenshot shortcut off the capture is not kept")
        retention.defaults.set(true, forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        retention.beginLatestCapture(9)
        retention.syncLatestCapture(with: retention.defaults)
        suite.expect(ScreenshotLastCaptureStore.stored == 9,
                     "edit latest screenshot keeps the latest capture")
        retention.defaults.set(false, forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        retention.syncLatestCapture(with: retention.defaults)
        suite.expect(ScreenshotLastCaptureStore.stored == nil,
                     "turning the latest screenshot shortcut off clears the kept capture")
        ScreenshotLastCaptureStore.stored = 1

        // A preview's Copy text waits for the after-capture copy, so the
        // capture lands first and the text, when there is any, replaces it.
        let copying = Service()
        var recognitions = 0
        copying.afterAutoCopy { recognitions += 1 }
        suite.expect(recognitions == 1, "with no after-capture copy pending, Copy text starts at once")
        var finishCopy: CheckedContinuation<Void, Never>?
        copying.autoCopyTask = Task { @MainActor in
            await withCheckedContinuation { finishCopy = $0 }
        }
        copying.afterAutoCopy { recognitions += 1 }
        let copyDeadline = Date().addingTimeInterval(2)
        while finishCopy == nil && Date() < copyDeadline { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        suite.expect(finishCopy != nil && recognitions == 1,
                     "Copy text waits while the after-capture copy is still being prepared")
        finishCopy?.resume()
        while recognitions == 1 && Date() < copyDeadline { await Task.yield() }
        suite.expect(recognitions == 2, "Copy text starts once the after-capture copy is in")
    }
}
