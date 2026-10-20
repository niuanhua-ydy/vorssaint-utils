// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import Combine

/// Recognizes text, one image at a time, in images saved before recognition
/// ran on them (Paste imports among them).
///
/// - One image at a time at utility priority, with a short pause between
///   images; it waits while Low Power Mode is on.
/// - Each result is stored at once, so stopping, quitting or restarting
///   carries on with the images left.
/// - An image that cannot be read (missing, damaged) is marked and never retried.
/// - Results stay on this Mac: they start no sync upload.
@MainActor
final class ClipNoteOCRBackfill: ObservableObject {
    @Published private(set) var stats = ClipStore.OCRStats()
    @Published private(set) var isRunning = false
    @Published private(set) var isWaitingForPower = false

    private let store: ClipStore
    private let preferences: ClipNotePreferences
    // Utility, not background: background throttles CPU and disk so hard that
    // loading the recognition model the first time can stall for a long while.
    private let queue = DispatchQueue(label: "com.vorssaint.utils.clipnote.ocr-backfill", qos: .utility)
    private let control = ClipNoteRunControl()
    private var cancellables: Set<AnyCancellable> = []
    private var refreshWork: DispatchWorkItem?
    private var isActive = false

    /// Rest between images, so the work never holds a core for long.
    nonisolated private static let pause: TimeInterval = 0.15
    /// Images between progress notifications.
    nonisolated private static let notifyEvery = 20

    init(store: ClipStore, preferences: ClipNotePreferences) {
        self.store = store
        self.preferences = preferences
    }

    /// Starts following the preference; `shutDown` stops for good.
    func activate() {
        guard !isActive else { return }
        isActive = true
        refresh()
        preferences.$ocrBackfillEnabled.removeDuplicates().sink { [weak self] enabled in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { enabled ? self?.start() : self?.stop() }
            }
        }.store(in: &cancellables)
        // New images (an import, say) refresh the progress, and resume the work when it is on.
        NotificationCenter.default.publisher(for: ClipStore.didChangeNotification, object: store)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            .store(in: &cancellables)
    }

    func shutDown() {
        isActive = false
        cancellables.removeAll()
        refreshWork?.cancel()
        control.cancel()
        isRunning = false
        isWaitingForPower = false
    }

    func refresh() {
        let store = self.store
        Task.detached(priority: .utility) {
            let stats = store.ocrStats()
            await MainActor.run {
                if self.stats != stats { self.stats = stats }
                if self.isActive, stats.pending > 0, self.preferences.ocrBackfillEnabled, !self.isRunning {
                    self.start()
                }
            }
        }
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func start() {
        guard isActive, preferences.ocrBackfillEnabled, !isRunning else { return }
        isRunning = true
        let token = control.begin()
        let store = self.store
        let control = self.control
        queue.async { [weak self] in
            var sinceNotify = 0
            outer: while control.isCurrent(token) {
                // In Low Power Mode, look again every minute.
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.isWaitingForPower = true } }
                    Thread.sleep(forTimeInterval: 60)
                    continue
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if self?.isWaitingForPower == true { self?.isWaitingForPower = false } }
                }
                let batch = store.pendingOCRImages(limit: 10)
                if batch.isEmpty { break }
                for image in batch {
                    guard control.isCurrent(token) else { break outer }
                    let text = autoreleasepool { () -> String? in
                        guard FileManager.default.fileExists(atPath: image.url.path) else { return nil }
                        return ClipNoteOCR.recognizeText(at: image.url)
                    }
                    store.completeOCR(id: image.id, text: text, recordSync: false, notify: false)
                    sinceNotify += 1
                    if sinceNotify >= Self.notifyEvery {
                        sinceNotify = 0
                        store.postChangeNotification()
                    }
                    Thread.sleep(forTimeInterval: Self.pause)
                }
            }
            if sinceNotify > 0 { store.postChangeNotification() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, control.isCurrent(token) else { return }
                    self.isRunning = false
                    self.isWaitingForPower = false
                    self.refresh()
                }
            }
        }
    }

    /// Stops after the image in progress; every result so far is kept.
    func stop() {
        control.cancel()
        isRunning = false
        isWaitingForPower = false
        refresh()
    }
}

/// A thread-safe run token: each start makes a new one, a cancel retires it.
final class ClipNoteRunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    func begin() -> Int { lock.withLock { current += 1; return current } }
    func cancel() { lock.withLock { current += 1 } }
    func isCurrent(_ token: Int) -> Bool { lock.withLock { current == token } }
}
