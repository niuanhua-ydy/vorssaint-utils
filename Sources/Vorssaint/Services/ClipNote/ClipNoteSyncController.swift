// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore

/// When and how ClipNote syncs over WebDAV (Jianguoyun, a NAS, Nextcloud…).
///
/// - Every 15 seconds, and 3 seconds after a change on this Mac; opening the
///   panel pulls at once when the last sync is over 5 seconds old.
/// - A refusal (403) or a rate limit (429 / 503) pauses for a while, as long
///   as `Retry-After` asks when the server sends one.
/// - After several failures in a row it stops retrying on its own, to spare
///   battery and traffic, until "Sync Now" or a settings change.
/// - A wrong password or passphrase pauses until the settings change.
@MainActor
final class ClipNoteSyncController: ObservableObject {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case error(String)
    }

    static let passwordAccount = "webdav-password"
    static let passphraseAccount = "e2e-passphrase"
    static let maxAutoRetries = 5

    @Published private(set) var status: Status = .off
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastSummary = ""
    @Published private(set) var pendingCount = 0

    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private var engine: SyncEngine?
    private var timer: Timer?
    private var debounce: DispatchWorkItem?
    private var running = false
    private var rerunRequested = false
    private var pausedUntil: Date?
    /// Failures in a row; a success, a manual sync or new settings reset it.
    private var consecutiveFailures = 0
    private var observer: NSObjectProtocol?

    private let pollInterval: TimeInterval = 15
    private let uploadDelay: TimeInterval = 3
    private let staleInterval: TimeInterval = 5

    init(store: ClipStore, preferences: ClipNotePreferences) {
        self.store = store
        self.preferences = preferences
        if let last = store.syncMeta("lastSync").flatMap(Double.init) {
            lastSync = Date(timeIntervalSince1970: last)
        }
        observer = NotificationCenter.default.addObserver(forName: ClipStore.didChangeNotification, object: store,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localDataChanged() }
        }
    }

    var isConfigured: Bool {
        !preferences.webdavUser.isEmpty && serverURL != nil && ClipNoteKeychain.get(Self.passwordAccount) != nil
    }

    var serverURL: URL? { Self.parseURL(preferences.webdavURL) }

    static func parseURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// Rebuilds the engine after a settings change, or tears it down.
    func reconfigure() {
        timer?.invalidate()
        timer = nil
        pausedUntil = nil
        consecutiveFailures = 0
        guard preferences.syncEnabled, isConfigured, let url = serverURL,
              let password = ClipNoteKeychain.get(Self.passwordAccount) else {
            engine = nil
            store.isSyncRecording = false
            status = .off
            return
        }
        store.isSyncRecording = true
        let folder = preferences.webdavFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let remote = WebDAVRemote(baseURL: url, username: preferences.webdavUser, password: password,
                                  rootPath: (folder.isEmpty ? "ClipNote" : folder) + "/sync",
                                  requestInterval: 0.05,
                                  allowSelfSignedCertificates: preferences.webdavTrustSelfSigned)
        let configuration = SyncConfiguration(
            deviceName: Host.current().localizedName ?? "Mac",
            passphrase: ClipNoteKeychain.get(Self.passphraseAccount),
            includeImages: preferences.syncImages,
            target: [url.absoluteString, preferences.webdavUser, folder].joined(separator: "|"),
            maxFileBytes: max(1, preferences.maxSyncItemMB) * 1024 * 1024)
        engine = SyncEngine(store: store, remote: remote, configuration: configuration)
        status = .idle
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        syncNow()
    }

    /// Stops syncing without touching the settings, when ClipNote stops.
    func shutDown() {
        timer?.invalidate()
        timer = nil
        debounce?.cancel()
        engine = nil
        status = .off
    }

    /// The panel opened: pull if the last sync is a few seconds old.
    func pullIfStale() {
        guard engine != nil, Date().timeIntervalSince(lastSync ?? .distantPast) > staleInterval else { return }
        syncNow()
    }

    func syncNow(userInitiated: Bool = false) {
        guard let engine else { return }
        if userInitiated {
            pausedUntil = nil
            consecutiveFailures = 0
        }
        if let pausedUntil, Date() < pausedUntil { return }
        guard !running else {
            rerunRequested = true
            return
        }
        running = true
        status = .syncing
        Task { [weak self] in
            let result: Result<SyncReport, Error>
            do {
                result = .success(try await engine.syncOnce())
            } catch {
                result = .failure(error)
            }
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<SyncReport, Error>) {
        running = false
        pendingCount = store.pendingSyncChangeCount
        let strings = FeatureStrings.clipNote(L10n.shared.language)
        switch result {
        case .success(let report):
            consecutiveFailures = 0
            lastSync = Date()
            status = .idle
            lastSummary = strings.syncSummary(report)
        case .failure(let error):
            consecutiveFailures += 1
            let message = strings.describe(error)
            status = .error(message)
            switch error {
            case WebDAVError.rateLimited(let retryAfter):
                pausedUntil = Date().addingTimeInterval(min(max(retryAfter ?? 15 * 60, 60), 60 * 60))
            case WebDAVError.forbidden:
                // A missing permission, or the service's own rate limit: try again later.
                pausedUntil = Date().addingTimeInterval(15 * 60)
            case WebDAVError.unauthorized, is SyncError:
                // Only new settings can fix these.
                pausedUntil = .distantFuture
            default:
                pausedUntil = Date().addingTimeInterval(5 * 60)
            }
            if consecutiveFailures >= Self.maxAutoRetries, pausedUntil != .distantFuture {
                pausedUntil = .distantFuture
                status = .error(String(format: strings.syncStoppedFormat, message, consecutiveFailures))
            }
            NSLog("[ClipNote] sync: \(error)")
        }
        if rerunRequested {
            rerunRequested = false
            syncNow()
        }
    }

    private func localDataChanged() {
        guard engine != nil else { return }
        // Changes received from other devices notify too; only upload when
        // this Mac has something waiting.
        pendingCount = store.pendingSyncChangeCount
        guard pendingCount > 0 else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + uploadDelay, execute: work)
    }

    /// Tries the address and account, and that the sync folder can be written.
    static func testConnection(url: String, user: String, password: String,
                               folder: String, trustSelfSigned: Bool) async throws {
        guard let base = parseURL(url) else {
            throw WebDAVError.network(FeatureStrings.clipNote(L10n.shared.language).invalidServerURL)
        }
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let remote = WebDAVRemote(baseURL: base, username: user, password: password,
                                  rootPath: (folder.isEmpty ? "ClipNote" : folder) + "/sync",
                                  requestInterval: 0.05, allowSelfSignedCertificates: trustSelfSigned)
        try await remote.testConnection()
        // Write and delete a file, to be sure the account may write here.
        try await remote.write(".clipnote-test", data: Data("ok".utf8))
        try await remote.delete(".clipnote-test")
    }
}
