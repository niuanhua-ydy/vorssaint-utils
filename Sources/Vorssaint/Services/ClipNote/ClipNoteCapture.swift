// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import UniformTypeIdentifiers

/// What was on the clipboard: read from the general pasteboard, or rebuilt
/// from another clipboard tool's library during an import.
enum ClipNotePasteboardSnapshot: @unchecked Sendable {
    case files([URL])
    case text(String, rich: (data: Data, type: String)?)
    case image(Data)

    static func read(from pasteboard: NSPasteboard) -> ClipNotePasteboardSnapshot? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let rtf = pasteboard.data(forType: .rtf) {
                return .text(string, rich: (rtf, NSPasteboard.PasteboardType.rtf.rawValue))
            }
            if let html = pasteboard.data(forType: .html) {
                return .text(string, rich: (html, NSPasteboard.PasteboardType.html.rawValue))
            }
            return .text(string, rich: nil)
        }
        if let png = pasteboard.data(forType: .png) { return .image(png) }
        if let tiff = pasteboard.data(forType: .tiff) { return .image(tiff) }
        return nil
    }

    /// Rebuilt from each pasteboard item's type-to-data map, in the same order
    /// of preference as `read(from:)`, so an imported item is the very item a
    /// copy would have made, down to the hash that de-duplicates it.
    static func from(items: [[String: Data]]) -> ClipNotePasteboardSnapshot? {
        let urls = items.compactMap { item -> URL? in
            guard let data = item[UTType.fileURL.identifier], let string = String(data: data, encoding: .utf8),
                  let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.isFileURL else { return nil }
            return url
        }
        if !urls.isEmpty { return .files(urls) }

        guard let first = items.first else { return nil }
        if let string = Self.string(in: first), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let rtf = first[NSPasteboard.PasteboardType.rtf.rawValue] {
                return .text(string, rich: (rtf, NSPasteboard.PasteboardType.rtf.rawValue))
            }
            if let html = first[NSPasteboard.PasteboardType.html.rawValue] {
                return .text(string, rich: (html, NSPasteboard.PasteboardType.html.rawValue))
            }
            return .text(string, rich: nil)
        }
        for type in [UTType.png, .tiff, .jpeg, .heic] {
            if let data = first[type.identifier], !data.isEmpty { return .image(data) }
        }
        return nil
    }

    private static func string(in item: [String: Data]) -> String? {
        if let data = item[UTType.utf8PlainText.identifier], let s = String(data: data, encoding: .utf8) { return s }
        if let data = item[UTType.utf16PlainText.identifier] {
            // UTF-16 on the pasteboard is usually little-endian without a BOM.
            let hasBOM = data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE])
            return String(data: data, encoding: hasBOM ? .utf16 : .utf16LittleEndian)
        }
        if let data = item[UTType.plainText.identifier], let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

/// A snapshot with its type and de-duplication hash settled, before any file
/// is written.
struct ClipNoteClassifiedClip: @unchecked Sendable {
    enum Content {
        case files([URL])
        case link(String)
        case text(String, rich: (data: Data, type: String)?)
        case image(Data)
    }

    var content: Content
    var hash: String

    var type: ClipType {
        switch content {
        case .files: return .file
        case .link: return .link
        case .text(_, let rich): return rich == nil ? .text : .rich
        case .image: return .image
        }
    }
}

/// Turns pasteboard content into an item in two steps: `classify` settles the
/// type and hash without touching disk (safe to run in parallel), then
/// `materialize` writes the image or rich text file the item points at.
enum ClipNoteBuilder {
    /// Nil when the content is over the size limit.
    static func classify(_ snapshot: ClipNotePasteboardSnapshot, maxBytes: Int) -> ClipNoteClassifiedClip? {
        switch snapshot {
        case .files(let urls):
            return ClipNoteClassifiedClip(content: .files(urls), hash: ContentHash.forFiles(urls.map(\.path)))
        case .text(let string, let rich):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = linkURL(trimmed) {
                return ClipNoteClassifiedClip(content: .link(url), hash: ContentHash.forLink(url))
            }
            guard string.utf8.count <= maxBytes else { return nil }
            // Formatting too large to keep (rich text with images) leaves the plain text.
            let keptRich = rich.flatMap { $0.data.count <= maxBytes ? $0 : nil }
            return ClipNoteClassifiedClip(content: .text(string, rich: keptRich), hash: ContentHash.forText(string))
        case .image(let data):
            guard data.count <= maxBytes else { return nil }
            return ClipNoteClassifiedClip(content: .image(data), hash: ContentHash.forImage(data))
        }
    }

    struct Materialized {
        var clip: NewClip
        /// Files written for the item (relative paths), removed if storing it fails.
        var files: [String]
        /// An image to recognize text in.
        var ocrURL: URL?
    }

    /// Nil when a file could not be written; anything written is removed then.
    static func materialize(_ classified: ClipNoteClassifiedClip, store: ClipStore,
                            bundleID: String?, appName: String?) -> Materialized? {
        let hash = classified.hash
        switch classified.content {
        case .files(let urls):
            let paths = urls.map(\.path)
            let names = urls.map(\.lastPathComponent).joined(separator: "\n")
            let clip = NewClip(type: .file, content: paths.joined(separator: "\n"),
                               searchText: names + "\n" + paths.joined(separator: "\n"),
                               sourceBundleID: bundleID, sourceAppName: appName, charCount: paths.count, hash: hash)
            let ocrURL = urls.count == 1 && isRecognizableImageFile(urls[0]) ? urls[0] : nil
            return Materialized(clip: clip, files: [], ocrURL: ocrURL)

        case .link(let url):
            return Materialized(clip: NewClip(type: .link, content: url, searchText: url, sourceBundleID: bundleID,
                                              sourceAppName: appName, charCount: url.count, hash: hash), files: [])

        case .text(let string, let rich):
            var dataPath: String?
            if let rich {
                let ext = rich.type == NSPasteboard.PasteboardType.rtf.rawValue ? "rtf" : "html"
                let path = "Data/\(UUID().uuidString).\(ext)"
                if (try? rich.data.write(to: store.url(forRelativePath: path))) != nil { dataPath = path }
            }
            let clip = NewClip(type: dataPath == nil ? .text : .rich, content: string, dataPath: dataPath,
                               dataType: dataPath == nil ? nil : rich?.type, searchText: string,
                               sourceBundleID: bundleID, sourceAppName: appName, charCount: string.count, hash: hash)
            return Materialized(clip: clip, files: dataPath.map { [$0] } ?? [])

        case .image(let data):
            guard let rep = NSBitmapImageRep(data: data) else { return nil }
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : rep.representation(using: .png, properties: [:])
            guard let png else { return nil }
            let path = "Images/\(UUID().uuidString).png"
            guard (try? png.write(to: store.url(forRelativePath: path))) != nil else { return nil }
            let clip = NewClip(type: .image, content: path, searchText: "", sourceBundleID: bundleID,
                               sourceAppName: appName, width: rep.pixelsWide, height: rep.pixelsHigh, hash: hash)
            return Materialized(clip: clip, files: [path], ocrURL: store.url(forRelativePath: path))
        }
    }

    /// Image files larger than this are not read for text.
    static let maxRecognizedBytes = 50 * 1024 * 1024

    static func isRecognizableImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        else { return false }
        return size <= maxRecognizedBytes
    }

    /// A single http(s) link with no whitespace becomes a link item.
    static func linkURL(_ text: String) -> String? {
        guard text.count < 2048, !text.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = text.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return text
    }
}

/// Watches the general pasteboard by polling its change count (macOS posts no
/// notification). Every read goes through the app's shared pasteboard lane,
/// so a provider that hangs never stalls the main thread.
@MainActor
final class ClipNoteMonitor {
    /// Types password managers and other tools put on content that must not
    /// be kept; see nspasteboard.org.
    nonisolated static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("org.nspasteboard.AutoGeneratedType"),
        .init("com.agilebits.onepassword"),
        .init("de.petermaurer.TransientPasteboardType"),
    ]

    private let store: ClipStore
    private let preferences: ClipNotePreferences
    private let changes = ClipNoteChangeLedger()
    private var timer: Timer?
    private var isReading = false
    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.clipnote.capture", qos: .utility)
    private var insertsSinceCleanup = 0
    /// Each recorded copy, new or already known, for Paste Stack.
    var onCapture: ((Int64) -> Void)?

    init(store: ClipStore, preferences: ClipNotePreferences) {
        self.store = store
        self.preferences = preferences
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // Whatever is on the clipboard now was copied before ClipNote ran.
        let changes = changes
        GeneralPasteboardAccess.shared.async { changes.skip(upTo: NSPasteboard.general.changeCount) }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Changes up to this count are not recorded. Safe from any thread; the
    /// writers call it on the pasteboard lane right after their own write.
    nonisolated func ignoreChanges(upTo changeCount: Int) {
        changes.ignore(upTo: changeCount)
    }

    private struct Read {
        var snapshot: ClipNotePasteboardSnapshot
        var bundleID: String?
        var appName: String?
    }

    private func poll() {
        guard !isReading else { return }
        isReading = true
        let changes = changes
        let skipConcealed = preferences.skipConcealed
        let paused = preferences.isPaused
        let ignored = preferences.ignoredBundleIDs
        // The app in front when the change is seen is where the copy came from.
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier, appName = app?.localizedName
        GeneralPasteboardAccess.shared.async({ () -> Read? in
            let pasteboard = NSPasteboard.general
            guard changes.claim(pasteboard.changeCount), !paused else { return nil }
            if let bundleID, ignored.contains(bundleID) { return nil }
            let types = Set(pasteboard.types ?? [])
            if skipConcealed && !types.isDisjoint(with: Self.concealedTypes) { return nil }
            guard let snapshot = ClipNotePasteboardSnapshot.read(from: pasteboard) else { return nil }
            return Read(snapshot: snapshot, bundleID: bundleID, appName: appName)
        }) { [weak self] read in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isReading = false
                if let read { self.record(read) }
            }
        }
    }

    private func record(_ read: Read) {
        let store = self.store
        let ocr = preferences.ocrEnabled
        let maxBytes = preferences.maxCaptureMB > 0 ? preferences.maxCaptureMB * 1024 * 1024 : Int.max
        let retention = (preferences.retentionDays, preferences.maxItems)
        workQueue.async { [weak self] in
            guard let captured = Self.process(read.snapshot, store: store, bundleID: read.bundleID,
                                              appName: read.appName, ocr: ocr, maxBytes: maxBytes) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onCapture?(captured.id)
                    guard captured.isNew else { return }
                    self?.didInsert(retention: retention)
                }
            }
        }
    }

    private func didInsert(retention: (days: Int, maxItems: Int)) {
        insertsSinceCleanup += 1
        guard insertsSinceCleanup >= 20 else { return }
        insertsSinceCleanup = 0
        let store = self.store
        workQueue.async { store.applyRetention(maxAgeDays: retention.days, maxItems: retention.maxItems) }
    }

    /// Classifies, de-duplicates, writes files and stores, off the main
    /// thread. Returns the item's id; known content returns the existing item.
    nonisolated private static func process(_ snapshot: ClipNotePasteboardSnapshot, store: ClipStore,
                                            bundleID: String?, appName: String?, ocr: Bool,
                                            maxBytes: Int) -> (id: Int64, isNew: Bool)? {
        guard let classified = ClipNoteBuilder.classify(snapshot, maxBytes: maxBytes) else { return nil }
        // Known content moves to the front with its new source; no file is written.
        if store.touch(hash: classified.hash, sourceBundleID: bundleID, sourceAppName: appName) {
            return store.itemID(hash: classified.hash).map { ($0, false) }
        }
        guard let made = ClipNoteBuilder.materialize(classified, store: store, bundleID: bundleID,
                                                     appName: appName) else { return nil }
        guard let id = try? store.insert(made.clip) else {
            store.removeFiles(made.files)
            return nil
        }
        if ocr, let ocrURL = made.ocrURL {
            // A failed recognition is marked too, so the backfill never retries it.
            store.completeOCR(id: id, text: ClipNoteOCR.recognizeText(at: ocrURL))
        }
        return (id, true)
    }
}

/// The last change count looked at and the highest one to skip, shared by
/// the main thread and the pasteboard lane.
final class ClipNoteChangeLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSeen = -1
    private var ignoredUpTo = -1

    func skip(upTo changeCount: Int) {
        lock.withLock {
            lastSeen = max(lastSeen, changeCount)
            ignoredUpTo = max(ignoredUpTo, changeCount)
        }
    }

    func ignore(upTo changeCount: Int) {
        lock.withLock { ignoredUpTo = max(ignoredUpTo, changeCount) }
    }

    /// Whether this count is a change to record: new since the last look and
    /// not one of the app's own writes.
    func claim(_ changeCount: Int) -> Bool {
        lock.withLock {
            guard changeCount != lastSeen else { return false }
            lastSeen = changeCount
            return changeCount > ignoredUpTo
        }
    }
}
