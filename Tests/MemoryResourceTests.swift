// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import Vision

enum MemoryResourceTests {
    static func run(_ suite: TestSuite) {
        idle(suite)
        cache(suite)
        cancellation(suite)
        clipPanel(suite)
        recognition(suite)
        windows(suite)
    }

    private static func idle(_ suite: TestSuite) {
        let idle = IdleResourceRelease()
        var released = 0
        idle.schedule(after: 0.01) { released += 1 }
        idle.cancel() // reopened before the grace period elapsed
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        suite.expect(released == 0, "reopening cancels the pending release")
        idle.schedule(after: 0.01) { released += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        suite.expect(released == 1, "idle resources are released when the grace period expires")
        idle.releaseNow()
        suite.expect(released == 1, "an idle release runs only once")
        idle.schedule(after: 10) { released += 10 }
        idle.schedule(after: 10) { released += 100 }
        NotificationCenter.default.post(name: MemoryPressureMonitor.notification, object: nil)
        suite.expect(released == 101, "pressure releases only the latest idle generation immediately")
        idle.schedule(after: 10) { released += 1000 }
        idle.cancel()
        NotificationCenter.default.post(name: MemoryPressureMonitor.notification, object: nil)
        suite.expect(released == 101, "pressure never releases a reopened active presentation")
        var disposable: IdleResourceRelease? = IdleResourceRelease()
        disposable?.schedule(after: 0.01) { released += 10000 }
        disposable = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        suite.expect(released == 101, "a pending work item does not retain its owner")
    }

    private static func cache(_ suite: TestSuite) {
        typealias Cache = CostBoundedCache<String, Int>
        let cache = Cache(byteLimit: 10, countLimit: 2)
        let generation = cache.generation
        cache.insert(1, for: "a", cost: 4, generation: generation)
        cache.insert(2, for: "b", cost: 4, generation: generation)
        suite.expect(cache.totalCost == 8, "decoded bytes, not item count, are charged")
        suite.expect(cache.value(for: "a") == 1, "a cache hit refreshes recency")
        cache.insert(3, for: "c", cost: 4, generation: generation)
        suite.expect(cache.value(for: "b") == nil && cache.value(for: "a") == 1,
                     "the least recently used item is evicted")
        cache.insert(4, for: "c", cost: 9, generation: generation)
        suite.expect(cache.totalCost == 9 && cache.value(for: "a") == nil,
                     "replacement subtracts the previous entry before enforcing the byte budget")
        cache.insert(5, for: "huge", cost: 11, generation: generation)
        suite.expect(cache.value(for: "huge") == nil && cache.totalCost == 9,
                     "one oversized image is displayed without being kept in the cache")
        cache.removeAll()
        cache.insert(6, for: "late", cost: 4, generation: generation)
        suite.expect(cache.value(for: "late") == nil && cache.totalCost == 0,
                     "a decode started before idle/pressure eviction cannot repopulate the cache")
        cache.insert(7, for: "new", cost: 4, generation: cache.generation)
        suite.expect(cache.value(for: "new") == 7, "a new presentation can populate the cache again")
        suite.expect(Cache.bitmapCost(width: 600, height: 600) == 1_440_000,
                     "thumbnail budget counts decoded RGBA pixels, not compressed file size")
        suite.expect(Cache.bitmapCost(width: 10, height: 20, bytesPerRow: 64) == 1280,
                     "bitmap row padding is counted")
        suite.expect(Cache.bitmapCost(width: Int.max, height: 2) == Int.max,
                     "overflow fails closed rather than admitting an uncharged bitmap")
        suite.expect(Cache.bitmapCost(width: 20, height: 0) == 0, "empty bitmaps have zero cost")
        let disabled = Cache(byteLimit: 10, countLimit: 0)
        disabled.insert(1, for: "a", cost: 1, generation: disabled.generation)
        suite.expect(disabled.totalCost == 0, "a zero count budget disables caching")
        let concurrent = CostBoundedCache<Int, Int>(byteLimit: 64, countLimit: 8)
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let epoch = concurrent.generation
            if index % 13 == 0 { concurrent.removeAll() }
            concurrent.insert(index, for: index, cost: 8, generation: epoch)
            _ = concurrent.value(for: index)
        }
        suite.expect(concurrent.totalCost <= 64, "concurrent completions and eviction preserve the byte budget")
    }

    private static func cancellation(_ suite: TestSuite) {
        let gate = LatestRequestGate()
        var cancelled = 0
        let first = gate.begin()
        suite.expect(gate.installCancellation(for: first, { cancelled += 1 }), "current request is accepted")
        let second = gate.begin()
        suite.expect(cancelled == 1 && !gate.isCurrent(first) && gate.isCurrent(second),
                     "a new image cancels and invalidates the previous OCR request")
        suite.expect(!gate.installCancellation(for: first, { cancelled += 10 }) && cancelled == 11,
                     "a request installed after cancellation is cancelled immediately")
        gate.installCancellation(for: second) { cancelled += 100 }
        gate.finish(first)
        gate.cancel()
        suite.expect(cancelled == 111 && !gate.isCurrent(second),
                     "an old band's completion cannot clear the new request's cancellation")
        let third = gate.begin()
        gate.installCancellation(for: third) { cancelled += 1000 }
        gate.finish(third)
        gate.cancel()
        suite.expect(cancelled == 111, "completed requests are dropped, not retained until the next image")
        let a = gate.begin()
        _ = gate.begin() // crop to B
        let aAgain = gate.begin() // undo to A: identity alone would accept the old result
        suite.expect(!gate.isCurrent(a) && gate.isCurrent(aAgain), "crop then undo rejects stale results for the same image")
        final class Request {}
        var request: Request? = Request()
        weak var weakRequest = request
        gate.installCancellation(for: aAgain) { [kept = request!] in _ = kept }
        request = nil
        suite.expect(weakRequest != nil, "an in-flight request lives until finished or cancelled")
        gate.finish(aAgain)
        suite.expect(weakRequest == nil, "finishing releases the request and any retained Vision results")
    }

    // Vision is a controlled dependency; scheduling/publication methods are
    // taken verbatim from ScreenshotEditorModel, without loading OCR models.
    final class VNRecognizeTextRequest {
        var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        var usesLanguageCorrection = false
        var automaticallyDetectsLanguage = false
        var results: [VNRecognizedTextObservation]? = []
        func cancel() {}
    }
    final class VNImageRequestHandler {
        static let lock = NSLock()
        static var performed = 0
        static var shouldFail = false
        init(cgImage: CGImage, options: [String: Any]) {}
        func perform(_ requests: [VNRecognizeTextRequest]) throws {
            Self.lock.lock(); defer { Self.lock.unlock() }
            Self.performed += 1
            if Self.shouldFail { throw NSError(domain: "vorss.tests.memory.vision", code: 1) }
        }
    }
    enum BarcodeDetector {
        static func read(_ image: CGImage) -> String? { "fixture QR" }
    }
    class RecognitionFixture {
        static let recognitionQueue = DispatchQueue(label: "vorss.tests.memory.recognition")
        let textRecognition = LatestRequestGate()
        let qrRecognition = LatestRequestGate()
        var textRecognitionImage: ObjectIdentifier?
        var qrRecognitionImage: ObjectIdentifier?
        var baseImage: CGImage
        var textWords: [ScreenshotSupport.RecognizedWord] = []
        var textRuns: [CGRect]?
        var carriedRuns: [ObjectIdentifier: [CGRect]] = [:]
        var qrReading: String?
        init(_ image: CGImage) { baseImage = image }
    }
    private static func recognition(_ suite: TestSuite) {
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                                bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let first = context.makeImage()!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let second = context.makeImage()!
        let model = RecognitionModel(first)
        let queue = RecognitionFixture.recognitionQueue
        VNImageRequestHandler.performed = 0
        model.recognizeText()
        model.recognizeText()
        model.recognizeQRCodes()
        queue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(VNImageRequestHandler.performed == 1, "duplicate recognition of one image runs Vision once")
        suite.expect(model.textRuns != nil && model.qrReading == "fixture QR",
                     "text and QR results still reach the editor")
        queue.suspend()
        model.baseImage = second
        model.recognizeText()
        model.recognizeQRCodes()
        model.cancelRecognition()
        queue.resume()
        queue.sync {}
        suite.expect(VNImageRequestHandler.performed == 1, "closing before queued OCR starts avoids running Vision")
        model.textRuns = nil
        model.qrReading = nil
        model.recognizeText()
        model.recognizeQRCodes()
        queue.sync {} // results have been posted, but not delivered on main
        model.cancelRecognition()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(model.textRuns == nil && model.qrReading == nil,
                     "closing after processing but before delivery rejects both late results")
        model.recognizeText()
        queue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(model.textRuns != nil, "recognition can restart after cancellation")
        model.cancelRecognition()
        VNImageRequestHandler.shouldFail = true
        model.recognizeText()
        queue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(model.textRuns == nil, "a failed OCR band preserves full-area blur rather than exposing unread text")
        VNImageRequestHandler.shouldFail = false
    }

    private static func windows(_ suite: TestSuite) {
        let menu = MenuPanelRecoveryTests.Host()
        menu.releasePanelResources()
        menu.menuPanelIdleRelease.releaseNow()
        suite.expect(menu.popover.contentViewController == nil, "idle menu panel releases its view graph")
        menu.ensurePopoverContent()
        menu.popover.isShown = true
        menu.releasePanelResources()
        menu.menuPanelIdleRelease.releaseNow()
        suite.expect(menu.popover.contentViewController != nil, "a reopened menu panel is not reclaimed")
        let settings = UpdateIntroFlowTests.Host()
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        settings.settingsWindow = window
        settings.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        suite.expect(settings.settingsWindow === window, "closed settings stay warm during the grace period")
        settings.settingsIdleRelease.releaseNow()
        suite.expect(settings.settingsWindow == nil && window.contentView == nil,
                     "idle settings release both the window reference and its content")
    }

    // The two methods in ClipPanel are extracted verbatim from production.
    final class Store {
        var discarded = 0 // accessed only on the panel's queryQueue
        func discardSearchCache() { discarded += 1 }
    }
    class ClipFixture {
        let store = Store()
        let queryQueue = DispatchQueue(label: "vorss.tests.memory.clip-query")
        var isVisible = false
        var isSuspended = false
        var reloadGeneration = 0
        var reloadWork: DispatchWorkItem?
        var needsReload = false
        var isLoadingMore = true
        var items = [1, 2, 3]
        var pinboards = [1]
        var sourceApps = [1]
        var contentCache = [1: "computed"]
        var cardFrames = [1: CGRect.zero]
        var selectedID: Int? = 1
        var searchField: NSTextField?
        var reloads = 0
        func reload(resetSelection: Bool, animated: Bool, keepLoadedCount: Bool) { reloads += 1 }
    }

    private static func clipPanel(_ suite: TestSuite) {
        let panel = ClipPanel()
        panel.isVisible = true
        panel.releaseIdleResources()
        suite.expect(panel.items.count == 3 && !panel.isSuspended, "a visible ClipNote panel is never discarded")
        panel.isVisible = false
        panel.releaseIdleResources()
        panel.queryQueue.sync {}
        suite.expect(panel.items.isEmpty && panel.pinboards.isEmpty && panel.sourceApps.isEmpty,
                     "idle ClipNote drops presentation data, not persisted history")
        suite.expect(panel.contentCache.isEmpty && panel.cardFrames.isEmpty && panel.selectedID == nil,
                     "idle ClipNote drops computed content and card geometry")
        suite.expect(panel.isSuspended && panel.needsReload && !panel.isLoadingMore && panel.reloadGeneration == 1,
                     "idle release invalidates pending reads and requests a fresh load on reopening")
        suite.expect(panel.store.discarded == 1, "search cache eviction runs after outstanding reads")
        panel.storeDidChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        suite.expect(panel.reloads == 0, "clipboard capture cannot rewarm a suspended UI")
        panel.isSuspended = false
        panel.isVisible = true
        panel.storeDidChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(panel.reloads == 1, "updates resume after the presentation is activated")
    }
}
