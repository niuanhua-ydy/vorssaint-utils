// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import SwiftUI
import UniformTypeIdentifiers

/// Export, import, and the daily backup to iCloud Drive.
///
/// There is no CloudKit here: the daily backup is a zip written into iCloud
/// Drive, which the system carries to other Macs, where "Import Backup"
/// merges it.
@MainActor
final class ClipNoteBackupController: ObservableObject {
    nonisolated static let autoBackupKeep = 7
    nonisolated static let autoBackupInterval: TimeInterval = 24 * 3600
    /// File and folder names the standalone app wrote; kept so its backups
    /// are still found and pruned.
    nonisolated static let autoBackupPrefix = "ClipNote-自动备份"
    nonisolated static let manualBackupPrefix = "ClipNote-备份"

    @Published private(set) var isRunning = false
    @Published private(set) var progressText = ""
    @Published private(set) var lastAutoBackup: Date? =
        UserDefaults.standard.object(forKey: DefaultsKey.clipNoteLastAutoBackup) as? Date

    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private var timer: Timer?
    private var progressWindow: NSWindow?

    init(store: ClipStore, preferences: ClipNotePreferences) {
        self.store = store
        self.preferences = preferences
    }

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(L10n.shared.language) }

    static var appVersion: String { "Vorssaint \(AppInfo.version)" }

    /// The iCloud Drive folder, nil when iCloud Drive is off.
    nonisolated static var iCloudDriveRoot: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated static var autoBackupFolder: URL? {
        iCloudDriveRoot?.appendingPathComponent("ClipNote/自动备份", isDirectory: true)
    }

    nonisolated static func defaultFileName(prefix: String = manualBackupPrefix) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix)-\(formatter.string(from: Date())).zip"
    }

    // MARK: - Daily backup

    func startAutoBackup() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoBackupIfNeeded() }
        }
        // A minute after starting, out of the way of launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated { self?.autoBackupIfNeeded() }
        }
    }

    func stopAutoBackup() {
        timer?.invalidate()
        timer = nil
    }

    func autoBackupIfNeeded() {
        guard timer != nil, preferences.autoBackupToICloud, !isRunning else { return }
        if let last = lastAutoBackup, Date().timeIntervalSince(last) < Self.autoBackupInterval { return }
        backupToICloudNow(interactive: false)
    }

    func backupToICloudNow(interactive: Bool) {
        let strings = self.strings
        guard let folder = Self.autoBackupFolder else {
            if interactive { showAlert(strings.iCloudMissingTitle, strings.iCloudMissingMessage) }
            return
        }
        let store = self.store
        let version = Self.appVersion
        run(title: interactive ? strings.backingUpToICloud : nil, work: { progress in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Exported to a temporary file first, so iCloud never syncs half a backup.
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(Self.defaultFileName())
            let count = try BackupService.export(store: store, to: temp, appVersion: version, progress: progress)
            let destination = folder.appendingPathComponent(Self.defaultFileName(prefix: Self.autoBackupPrefix))
            try FileManager.default.moveItem(at: temp, to: destination)
            Self.pruneAutoBackups(in: folder)
            return String(format: strings.backedUpToICloudFormat, count)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.lastAutoBackup = Date()
                UserDefaults.standard.set(self.lastAutoBackup, forKey: DefaultsKey.clipNoteLastAutoBackup)
                if interactive { self.showAlert(strings.backupDoneTitle, message) }
            case .failure(let error):
                NSLog("[ClipNote] auto backup: \(error)")
                if interactive { self.showAlert(strings.backupFailedTitle, strings.describe(error)) }
            }
        })
    }

    nonisolated private static func pruneAutoBackups(in folder: URL) {
        let manager = FileManager.default
        let files = ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(autoBackupPrefix) && $0.pathExtension == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(autoBackupKeep) {
            try? manager.removeItem(at: old)
        }
    }

    // MARK: - Export and import

    func exportInteractive() {
        let strings = self.strings
        let panel = NSSavePanel()
        panel.title = strings.exportPanelTitle
        panel.nameFieldStringValue = Self.defaultFileName()
        panel.allowedContentTypes = [.zip]
        let onlyPinned = NSButton(checkboxWithTitle: strings.exportOnlyPinned, target: nil, action: nil)
        panel.accessoryView = onlyPinned
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let pinnedOnly = onlyPinned.state == .on
        let store = self.store
        let version = Self.appVersion
        run(title: strings.exporting, work: { progress in
            let count = try BackupService.export(store: store, to: url, onlyPinned: pinnedOnly, appVersion: version,
                                                 progress: progress)
            return String(format: strings.exportedFormat, count, url.lastPathComponent)
        }, completion: { [weak self] result in
            switch result {
            case .success(let message):
                self?.showAlert(strings.exportDoneTitle, message, revealing: url)
            case .failure(let error):
                self?.showAlert(strings.exportFailedTitle, strings.describe(error))
            }
        })
    }

    func importInteractive() {
        let strings = self.strings
        let panel = NSOpenPanel()
        panel.title = strings.importPanelTitle
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = Self.autoBackupFolder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let manifest: BackupService.Manifest
        do {
            manifest = try BackupService.readManifest(from: url)
        } catch {
            showAlert(strings.backupUnreadableTitle, strings.describe(error))
            return
        }
        let confirm = NSAlert()
        confirm.messageText = String(format: strings.importConfirmFormat, manifest.itemCount)
        confirm.informativeText = String(format: strings.importConfirmDetailFormat,
                                         ClipNoteFormatters.absolute.string(from: manifest.exportedAt))
        confirm.addButton(withTitle: strings.importButton)
        confirm.addButton(withTitle: strings.cancel)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let store = self.store
        run(title: strings.importing, total: manifest.itemCount, work: { progress in
            let summary = try BackupService.importBackup(from: url, into: store, progress: progress)
            var message = String(format: strings.importSummaryFormat, summary.inserted, summary.skipped)
            if summary.pinboardsCreated > 0 {
                message += String(format: strings.importPinboardsFormat, summary.pinboardsCreated)
            }
            if summary.missingFiles > 0 {
                message += String(format: strings.importMissingFilesFormat, summary.missingFiles)
            }
            return message
        }, completion: { [weak self] result in
            switch result {
            case .success(let message): self?.showAlert(strings.importDoneTitle, message)
            case .failure(let error): self?.showAlert(strings.importFailedTitle, strings.describe(error))
            }
        })
    }

    // MARK: - Running and progress

    /// Runs in the background; a title shows a progress window.
    private func run(title: String?, total: Int? = nil,
                     work: @escaping @Sendable (@escaping (Int) -> Void) throws -> String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        progressText = title ?? ""
        if let title { showProgressWindow(title: title) }
        let strings = self.strings
        let progress: (Int) -> Void = { [weak self] done in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let label = title ?? ""
                    self.progressText = total.map { String(format: strings.progressOfFormat, label, done, $0) }
                        ?? String(format: strings.progressProcessedFormat, label, done)
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work(progress) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.isRunning = false
                    self?.progressWindow?.close()
                    self?.progressWindow = nil
                    completion(result)
                }
            }
        }
    }

    private func showProgressWindow(title: String) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                             styleMask: [.titled], backing: .buffered, defer: false)
        window.title = strings.title
        window.contentView = NSHostingView(rootView: ClipNoteBackupProgressView(controller: self))
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        progressWindow = window
    }

    private func showAlert(_ title: String, _ message: String, revealing url: URL? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: strings.ok)
        if url != nil { alert.addButton(withTitle: strings.revealInFinder) }
        if alert.runModal() == .alertSecondButtonReturn, let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

private struct ClipNoteBackupProgressView: View {
    @ObservedObject var controller: ClipNoteBackupController

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().progressViewStyle(.linear)
            Text(controller.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 360)
    }
}
