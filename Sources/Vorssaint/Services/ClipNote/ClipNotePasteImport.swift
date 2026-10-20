// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import SwiftUI

/// Imports Paste's history in the background.
///
/// - Paste is only read: its database is copied before reading (see
///   `PasteLibrary`), and none of its files is written.
/// - Only merged: `ClipStore.importClips` keeps local items as they are and
///   deletes nothing.
/// - 200 records per batch: decode, classify and look up in parallel, write
///   image files in parallel, then store the batch in one transaction. A
///   failed transaction removes the batch's files; a killed process rolls the
///   batch back and the next import sweeps what it left.
/// - Pausable between batches; a pause lets the batch in hand commit.
/// - Resumable: every committed batch reports its last Paste key.
final class ClipNotePasteImportJob: @unchecked Sendable {
    struct Options {
        /// Size limit per item in bytes; Int.max for none.
        var maxBytes: Int
        var includeImages: Bool
        /// Whether imported items upload to the sync service.
        var recordSync: Bool
        /// Paste key to start after when resuming; 0 starts over.
        var startAfter: Int64
    }

    struct Progress {
        var total = 0
        var processed = 0
        var inserted = 0
        /// Already here (merged).
        var existing = 0
        var skippedTooLarge = 0
        var skippedImages = 0
        /// Nothing usable (browser-internal data, files not downloaded yet).
        var unsupported = 0
        /// Damaged or unreadable.
        var failed = 0
        /// The last Paste key of the last committed batch.
        var cursor: Int64 = 0
    }

    static let batchSize = 200

    private let library: PasteLibrary
    private let store: ClipStore
    private let options: Options
    private let lock = NSLock()
    private var pauseRequested = false

    init(library: PasteLibrary, store: ClipStore, options: Options) {
        self.library = library
        self.store = store
        self.options = options
    }

    /// Stops after the batch in hand commits.
    func pause() {
        lock.withLock { pauseRequested = true }
    }

    private var isPauseRequested: Bool { lock.withLock { pauseRequested } }

    private enum Outcome {
        case new(ClipNoteClassifiedClip)
        /// Already here, or a later copy in the same batch: its hash fills in a pinboard or title.
        case existing(hash: String)
        case tooLarge
        case skippedImage
        case unsupported
        case failed
    }

    /// Runs synchronously on a background thread. Returns the final progress
    /// and whether everything was read (false after a pause).
    func run(progress report: @escaping (Progress) -> Void) throws -> (Progress, completed: Bool) {
        store.removeOrphanFiles()

        // Pinboards match by name; a missing one is created.
        var boardIDs = Dictionary(store.pinboards().map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        for board in try library.summary().pinboards where boardIDs[board.name] == nil {
            if let created = store.createPinboard(name: board.name, color: board.color) {
                boardIDs[board.name] = created.id
            }
        }

        var progress = Progress()
        progress.total = try library.count(after: options.startAfter)
        progress.cursor = options.startAfter
        report(progress)

        var batchesSinceNotify = 0
        while !isPauseRequested {
            let records = try library.records(after: progress.cursor, limit: Self.batchSize)
            guard let last = records.last else { break }

            // First pass, in parallel: decode, classify, look up.
            var outcomes = [Outcome](repeating: .failed, count: records.count)
            let outcomesLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: records.count) { index in
                let outcome = autoreleasepool { classify(records[index]) }
                outcomesLock.withLock { outcomes[index] = outcome }
            }

            // The same content twice in a batch keeps only its latest use.
            var chosen: [String: Int] = [:]
            for (index, outcome) in outcomes.enumerated() {
                guard case .new(let classified) = outcome else { continue }
                if let previous = chosen[classified.hash], records[previous].lastUsedAt >= records[index].lastUsedAt {
                    outcomes[index] = .existing(hash: classified.hash)
                } else {
                    if let previous = chosen[classified.hash] { outcomes[previous] = .existing(hash: classified.hash) }
                    chosen[classified.hash] = index
                }
            }

            // Second pass, in parallel: write image and rich text files.
            var made = [ClipNoteBuilder.Materialized?](repeating: nil, count: records.count)
            DispatchQueue.concurrentPerform(iterations: records.count) { index in
                guard case .new(let classified) = outcomes[index] else { return }
                let record = records[index]
                let result = autoreleasepool {
                    ClipNoteBuilder.materialize(classified, store: store, bundleID: record.sourceBundleID,
                                                appName: record.sourceAppName)
                }
                outcomesLock.withLock { made[index] = result }
            }

            // Store: one transaction, its files removed if it fails.
            var batch: [ImportedClip] = []
            var writtenFiles: [String] = []
            for (index, record) in records.enumerated() {
                let boardID = record.pinboard.flatMap { boardIDs[$0] }
                switch outcomes[index] {
                case .new:
                    guard let result = made[index] else {
                        progress.failed += 1
                        continue
                    }
                    writtenFiles += result.files
                    batch.append(ImportedClip(clip: result.clip, createdAt: record.createdAt, updatedAt: record.lastUsedAt,
                                              pinboardID: boardID, title: record.title))
                case .existing(let hash):
                    // Only fills in a pinboard or title: importClips never overwrites a known hash.
                    if boardID != nil || record.title != nil {
                        batch.append(ImportedClip(clip: NewClip(type: .text, content: "", searchText: "", hash: hash),
                                                  createdAt: record.createdAt, updatedAt: record.lastUsedAt,
                                                  pinboardID: boardID, title: record.title))
                    }
                    progress.existing += 1
                case .tooLarge: progress.skippedTooLarge += 1
                case .skippedImage: progress.skippedImages += 1
                case .unsupported: progress.unsupported += 1
                case .failed: progress.failed += 1
                }
            }
            do {
                let result = try store.importClips(batch, notify: false, recordSync: options.recordSync)
                progress.inserted += result.inserted
            } catch {
                store.removeFiles(writtenFiles)
                throw error
            }

            progress.processed += records.count
            progress.cursor = last.key
            report(progress)
            batchesSinceNotify += 1
            if batchesSinceNotify >= 5 {
                batchesSinceNotify = 0
                store.postChangeNotification()
            }
        }
        store.postChangeNotification()
        // Done when nothing is left after the cursor, even if a pause came right after the last batch.
        let completed = try library.count(after: progress.cursor) == 0
        return (progress, completed)
    }

    private func classify(_ record: PasteLibrary.Record) -> Outcome {
        let items: [[String: Data]]
        do {
            items = try library.decode(record.raw)
        } catch {
            return .failed
        }
        guard let snapshot = ClipNotePasteboardSnapshot.from(items: items) else { return .unsupported }
        guard let classified = ClipNoteBuilder.classify(snapshot, maxBytes: options.maxBytes) else { return .tooLarge }
        if classified.type == .image && !options.includeImages { return .skippedImage }
        if store.contains(hash: classified.hash) { return .existing(hash: classified.hash) }
        return .new(classified)
    }
}

/// "Import from Paste": find the library, confirm the options, import in the
/// background with a pausable progress window, then report. Every committed
/// batch saves a checkpoint, so a pause, quit or crash resumes where it was.
@MainActor
final class ClipNotePasteImportController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case pausing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = ClipNotePasteImportJob.Progress()
    @Published private(set) var startedAt = Date()

    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private var job: ClipNotePasteImportJob?
    private var window: NSWindow?
    private let closeHandler = ClipNoteImportWindowCloser()

    init(store: ClipStore, preferences: ClipNotePreferences) {
        self.store = store
        self.preferences = preferences
        closeHandler.onClose = { [weak self] in
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(L10n.shared.language) }

    // MARK: - Checkpoint

    private enum Checkpoint {
        static func load(storeID: String) -> Int64? {
            let defaults = UserDefaults.standard
            guard defaults.string(forKey: DefaultsKey.clipNotePasteImportStoreID) == storeID,
                  let cursors = defaults.array(forKey: DefaultsKey.clipNotePasteImportCursors) as? [NSNumber],
                  let first = cursors.first else { return nil }
            // Two batches back: a power cut may lose the last one or two.
            // Their items de-duplicate by content, so nothing doubles.
            return cursors.count >= 3 ? first.int64Value : 0
        }

        static func save(storeID: String, cursor: Int64) {
            let defaults = UserDefaults.standard
            let saved = defaults.string(forKey: DefaultsKey.clipNotePasteImportStoreID) == storeID
                ? defaults.array(forKey: DefaultsKey.clipNotePasteImportCursors) as? [NSNumber] : nil
            var cursors = saved ?? []
            cursors.append(NSNumber(value: cursor))
            defaults.set(storeID, forKey: DefaultsKey.clipNotePasteImportStoreID)
            defaults.set(Array(cursors.suffix(3)), forKey: DefaultsKey.clipNotePasteImportCursors)
        }

        static func clear() {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.clipNotePasteImportStoreID)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.clipNotePasteImportCursors)
        }
    }

    // MARK: - Flow

    func start() {
        if phase != .idle {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        open(directory: PasteLibrary.defaultDirectory)
    }

    private func open(directory: URL) {
        // Copying Paste's database takes a few hundred milliseconds.
        Task.detached(priority: .userInitiated) {
            let result = Result { try PasteLibrary(directory: directory) }
            await MainActor.run { self.opened(result, directory: directory) }
        }
    }

    private func opened(_ result: Result<PasteLibrary, Error>, directory: URL) {
        let strings = self.strings
        switch result {
        case .success(let library):
            confirm(library)
        case .failure(let error):
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = strings.pasteUnreadableTitle
            alert.informativeText = String(format: strings.pasteUnreadableDetailFormat, strings.describe(error))
            alert.addButton(withTitle: strings.chooseFolder)
            alert.addButton(withTitle: strings.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.showsHiddenFiles = true
            panel.directoryURL = FileManager.default.fileExists(atPath: directory.path) ? directory
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers")
            panel.message = strings.choosePasteFolderMessage
            guard panel.runModal() == .OK, let url = panel.url else { return }
            open(directory: url)
        }
    }

    private func confirm(_ library: PasteLibrary) {
        let strings = self.strings
        let summary: PasteLibrary.Summary
        do {
            summary = try library.summary()
        } catch {
            showAlert(strings.pasteUnreadableTitle, strings.describe(error))
            return
        }
        guard summary.itemCount > 0 else {
            showAlert(strings.pasteEmptyTitle, "")
            return
        }

        let resumeCursor = Checkpoint.load(storeID: summary.storeID)
        let remaining = resumeCursor.flatMap { try? library.count(after: $0) }
        let options = ClipNoteImportOptionsModel(
            canResume: resumeCursor != nil && (remaining ?? 0) > 0,
            resumeDescription: remaining.map { String(format: strings.pasteResumeFormat, $0, summary.itemCount) } ?? "",
            syncAvailable: preferences.syncEnabled,
            recordSync: preferences.syncEnabled)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(format: strings.pasteConfirmFormat, summary.itemCount)
        var info = ""
        if let earliest = summary.earliest, let latest = summary.latest {
            info += String(format: strings.pasteTimeRangeFormat, Self.day.string(from: earliest),
                           Self.day.string(from: latest))
        }
        if !summary.pinboards.isEmpty { info += String(format: strings.pastePinboardsFormat, summary.pinboards.count) }
        info += "\n\n" + strings.pasteMergeExplanation
        alert.informativeText = info
        let accessory = NSHostingView(rootView: ClipNoteImportOptionsView(model: options, strings: strings))
        accessory.frame = NSRect(x: 0, y: 0, width: 360, height: accessory.fittingSize.height)
        alert.accessoryView = accessory
        alert.addButton(withTitle: strings.startImport)
        alert.addButton(withTitle: strings.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let startAfter = options.canResume && options.resume ? (resumeCursor ?? 0) : 0
        if startAfter == 0 { Checkpoint.clear() }
        run(library: library, storeID: summary.storeID, options: .init(
            maxBytes: options.limitMB > 0 ? options.limitMB * 1024 * 1024 : Int.max,
            includeImages: options.includeImages, recordSync: options.syncAvailable && options.recordSync,
            startAfter: startAfter))
    }

    private func run(library: PasteLibrary, storeID: String, options: ClipNotePasteImportJob.Options) {
        let job = ClipNotePasteImportJob(library: library, store: store, options: options)
        self.job = job
        progress = ClipNotePasteImportJob.Progress()
        startedAt = Date()
        phase = .running
        showProgressWindow()

        Task.detached(priority: .userInitiated) {
            let result = Result {
                try job.run { progress in
                    // Only committed batches report, so the checkpoint is safe to save here.
                    Task { @MainActor in
                        self.progress = progress
                        if progress.cursor > 0 { Checkpoint.save(storeID: storeID, cursor: progress.cursor) }
                    }
                }
            }
            await MainActor.run { self.finished(result) }
        }
    }

    func pause() {
        guard phase == .running else { return }
        phase = .pausing
        job?.pause()
    }

    private func finished(_ result: Result<(ClipNotePasteImportJob.Progress, completed: Bool), Error>) {
        let strings = self.strings
        job = nil
        phase = .idle
        window?.close()
        window = nil
        switch result {
        case .success(let (progress, completed)):
            self.progress = progress
            if completed { Checkpoint.clear() }
            var lines = [String(format: strings.pasteResultFormat, progress.inserted, progress.existing)]
            var skipped: [String] = []
            if progress.skippedTooLarge > 0 {
                skipped.append(String(format: strings.pasteSkippedTooLargeFormat, progress.skippedTooLarge))
            }
            if progress.skippedImages > 0 {
                skipped.append(String(format: strings.pasteSkippedImagesFormat, progress.skippedImages))
            }
            if progress.unsupported > 0 {
                skipped.append(String(format: strings.pasteSkippedUnsupportedFormat, progress.unsupported))
            }
            if !skipped.isEmpty {
                lines.append(String(format: strings.pasteSkippedFormat, skipped.joined(separator: strings.listSeparator)))
            }
            if progress.failed > 0 { lines.append(String(format: strings.pasteFailedFormat, progress.failed)) }
            if !completed { lines.append("\n" + strings.pastePausedNote) }
            showAlert(completed ? strings.pasteDoneTitle : strings.pastePausedTitle, lines.joined(separator: "\n"))
        case .failure(let error):
            showAlert(strings.pasteInterruptedTitle,
                      String(format: strings.pasteInterruptedFormat, strings.describe(error)))
        }
    }

    // MARK: - Windows

    private func showProgressWindow() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = strings.importFromPaste
        window.contentView = NSHostingView(rootView: ClipNoteImportProgressView(controller: self))
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.delegate = closeHandler
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Closing the progress window pauses the import; the controller closes it
/// once the batch in hand has committed.
private final class ClipNoteImportWindowCloser: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false
    }
}

@MainActor
final class ClipNoteImportOptionsModel: ObservableObject {
    let canResume: Bool
    let resumeDescription: String
    let syncAvailable: Bool
    @Published var resume = true
    @Published var includeImages = true
    /// Size limit per item in MB, 0 for none. 100 MB covers almost everything in Paste.
    @Published var limitMB = 100
    @Published var recordSync: Bool

    init(canResume: Bool, resumeDescription: String, syncAvailable: Bool, recordSync: Bool) {
        self.canResume = canResume
        self.resumeDescription = resumeDescription
        self.syncAvailable = syncAvailable
        self.recordSync = recordSync
    }
}

private struct ClipNoteImportOptionsView: View {
    @ObservedObject var model: ClipNoteImportOptionsModel
    let strings: ClipNoteStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.canResume {
                Toggle(model.resumeDescription, isOn: $model.resume)
            }
            Toggle(strings.importImages, isOn: $model.includeImages)
            Picker(strings.itemSizeLimit, selection: $model.limitMB) {
                Text("50 MB").tag(50)
                Text("100 MB").tag(100)
                Text("200 MB").tag(200)
                Text(strings.unlimited).tag(0)
            }
            .fixedSize()
            if model.syncAvailable {
                Toggle(strings.syncImported, isOn: $model.recordSync)
                Text(strings.syncImportedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .frame(width: 360, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct ClipNoteImportProgressView: View {
    @ObservedObject var controller: ClipNotePasteImportController
    @ObservedObject private var l10n = L10n.shared

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }
    private var progress: ClipNotePasteImportJob.Progress { controller.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.phase == .pausing ? strings.pasteImportPausing : strings.pasteImportRunning)
                .font(.headline)
            ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
            HStack {
                Text("\(progress.processed) / \(progress.total)")
                    .monospacedDigit()
                Spacer()
                Text(speedText).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    stat(strings.statNew, progress.inserted)
                    stat(strings.statExisting, progress.existing)
                    stat(strings.statSkipped, progress.skippedTooLarge + progress.skippedImages + progress.unsupported)
                    stat(strings.statFailed, progress.failed)
                }
            }
            HStack {
                Text(strings.pasteImportKeepWorking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(strings.pause) { controller.pause() }
                    .disabled(controller.phase != .running)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(.title3, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var speedText: String {
        let elapsed = Date().timeIntervalSince(controller.startedAt)
        guard progress.processed > 0, elapsed > 0.5 else { return strings.preparing }
        let rate = Double(progress.processed) / elapsed
        let remaining = Double(progress.total - progress.processed) / rate
        let remainText = remaining < 60
            ? String(format: strings.secondsFormat, Int(remaining.rounded(.up)))
            : String(format: strings.minutesFormat, Int((remaining / 60).rounded(.up)))
        return String(format: strings.importSpeedFormat, Int(rate), remainText)
    }
}
