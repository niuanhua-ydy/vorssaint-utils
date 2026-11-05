// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One pressure source for disposable resources. Callers must not discard
/// documents, active work or visible UI in response to this notification.
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()
    static let notification = Notification.Name("Vorssaint.releaseDisposableMemory")
    private let source: DispatchSourceMemoryPressure

    private init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            NotificationCenter.default.post(name: Self.notification, object: nil)
        }
        source.resume()
    }
}

final class MemoryPressureObservation {
    private let token: NSObjectProtocol

    init(_ release: @escaping () -> Void) {
        _ = MemoryPressureMonitor.shared
        token = NotificationCenter.default.addObserver(
            forName: MemoryPressureMonitor.notification, object: nil, queue: .main
        ) { _ in release() }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Main-thread-only grace period: quick reopening stays warm, long-idle UI
/// can be rebuilt. Pressure shortens the grace period, never closes active UI.
final class IdleResourceRelease {
    static let gracePeriod: TimeInterval = 60
    private var work: DispatchWorkItem?
    private var release: (() -> Void)?
    private var generation = 0
    private var pressure: MemoryPressureObservation?

    init() {
        pressure = MemoryPressureObservation { [weak self] in self?.releaseNow() }
    }

    func schedule(after delay: TimeInterval = gracePeriod, _ release: @escaping () -> Void) {
        cancel()
        self.release = release
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.releaseNow()
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancel() {
        generation += 1
        work?.cancel()
        work = nil
        release = nil
    }

    func releaseNow() {
        let action = release
        cancel()
        action?()
    }

    deinit { work?.cancel() }
}

/// Request generation plus cooperative cancellation. Unlike image identity,
/// it also rejects an old result after crop -> undo back to the same image.
/// Background work never needs to read the UI model to check its lifetime.
final class LatestRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var current: UUID?
    private var cancellation: (() -> Void)?

    func begin() -> UUID {
        let token = UUID()
        lock.lock()
        let previous = cancellation
        current = token
        cancellation = nil
        lock.unlock()
        previous?()
        return token
    }

    func isCurrent(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return current == token
    }

    @discardableResult
    func installCancellation(for token: UUID, _ cancel: @escaping () -> Void) -> Bool {
        lock.lock()
        let accepted = current == token
        if accepted { cancellation = cancel }
        lock.unlock()
        if !accepted { cancel() }
        return accepted
    }

    /// Drop the request (and its results/model references) before publishing.
    func finish(_ token: UUID) {
        lock.lock()
        if current == token { cancellation = nil }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let previous = cancellation
        current = nil
        cancellation = nil
        lock.unlock()
        previous?()
    }

    deinit { cancel() }
}

/// A strict decoded-byte budget (NSCache's totalCostLimit is advisory).
/// Epochs prevent a decode started before eviction from refilling an idle cache.
final class CostBoundedCache<Key: Hashable, Value>: @unchecked Sendable {
    private struct Entry {
        let value: Value
        let cost: Int
        var access: UInt64
    }
    private let lock = NSLock()
    private let byteLimit: Int
    private let countLimit: Int
    private var entries: [Key: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private var epoch: UInt64 = 0

    init(byteLimit: Int, countLimit: Int) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
    }

    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return epoch
    }

    var totalCost: Int {
        lock.lock(); defer { lock.unlock() }
        return bytes
    }

    func value(for key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.value
    }

    func insert(_ value: Value, for key: Key, cost: Int, generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard epoch == generation, cost >= 0, cost <= byteLimit, countLimit > 0 else { return }
        if let old = entries.removeValue(forKey: key) { bytes -= old.cost }
        while bytes > byteLimit - cost || entries.count >= countLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key,
                  let removed = entries.removeValue(forKey: oldest) else { break }
            bytes -= removed.cost
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, access: clock)
        bytes += cost
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        epoch &+= 1
        entries = [:]
        bytes = 0
    }

    static func bitmapCost(width: Int, height: Int, bytesPerRow: Int? = nil) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let row = width.multipliedReportingOverflow(by: 4)
        guard !row.overflow else { return Int.max }
        let size = max(row.partialValue, bytesPerRow ?? 0).multipliedReportingOverflow(by: height)
        return size.overflow ? Int.max : size.partialValue
    }
}
