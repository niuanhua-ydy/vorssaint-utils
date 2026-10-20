// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import UniformTypeIdentifiers

/// What the detail pane says about a row that is a real thing on disk: an
/// app, a folder, a file. Read from Spotlight, which already keeps all of it
/// and answers in one call; the file system fills in what it does not know.
struct CommandBarItemDetails: Equatable {
    let path: String
    let isApp: Bool
    /// The App Store category for an app, already in the Mac's language;
    /// the kind ("PDF document", "Folder") for anything else.
    let kind: String?
    let size: Int64?
    let version: String?
    let created: Date?
    let modified: Date?
    let lastOpened: Date?

    func withSize(_ size: Int64?) -> CommandBarItemDetails {
        CommandBarItemDetails(path: path, isApp: isApp, kind: kind, size: size, version: version,
                              created: created, modified: modified, lastOpened: lastOpened)
    }

    static func read(path: String) -> CommandBarItemDetails {
        let url = URL(fileURLWithPath: path)
        let item = MDItemCreate(kCFAllocatorDefault, path as CFString)
        func value<T>(_ key: CFString) -> T? {
            guard let item else { return nil }
            return MDItemCopyAttribute(item, key) as? T
        }
        let resources = try? url.resourceValues(forKeys: [
            .isApplicationKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey,
            .fileSizeKey, .localizedTypeDescriptionKey,
        ])
        let isApp = resources?.isApplication ?? (url.pathExtension == "app")
        let bundle = isApp ? Bundle(url: url) : nil

        let kind: String?
        if isApp {
            let category = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            kind = value("kMDItemAppStoreCategory" as CFString)
                ?? category.flatMap { UTType($0)?.localizedDescription }
        } else {
            kind = value(kMDItemKind) ?? resources?.localizedTypeDescription
        }

        // A folder's own size is the size of its entry, not of what is in
        // it; only an app bundle is worth adding up, and that comes later.
        let size: Int64?
        if resources?.isDirectory == true, !isApp {
            size = nil
        } else {
            let spotlight: NSNumber? = value("kMDItemPhysicalSize" as CFString) ?? value("kMDItemLogicalSize" as CFString)
                ?? value(kMDItemFSSize)
            size = spotlight?.int64Value ?? resources?.fileSize.map(Int64.init)
        }

        return CommandBarItemDetails(
            path: path,
            isApp: isApp,
            kind: kind,
            size: size,
            version: isApp
                ? (value(kMDItemVersion)
                   ?? bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                : nil,
            created: value(kMDItemContentCreationDate) ?? resources?.creationDate,
            modified: isApp ? nil : (value(kMDItemContentModificationDate) ?? resources?.contentModificationDate),
            lastOpened: value(kMDItemLastUsedDate))
    }

    /// Everything inside a bundle Spotlight did not measure, added up the way
    /// Finder's Get Info does. Slow for a big app, so it runs after the rest
    /// is already on screen.
    static func bundleSize(at path: String, isCancelled: () -> Bool) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: path),
                                                          includingPropertiesForKeys: keys) else { return nil }
        var total: Int64 = 0
        for case let file as URL in walker {
            if isCancelled() { return nil }
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Feeds the detail pane the selected row's details, off the main thread and
/// remembered for the session, so walking the list with the arrow keys never
/// waits on the disk twice for the same app.
final class CommandBarDetailLoader: ObservableObject {
    static let shared = CommandBarDetailLoader()

    @Published private(set) var details: CommandBarItemDetails?

    private let queue = DispatchQueue(label: "vorssaint.commandbar.details", qos: .userInitiated)
    private var cache: [String: CommandBarItemDetails] = [:]
    /// Read from the walk on the loader's queue as well, hence the lock.
    private let lock = NSLock()
    private var requestedPath: String?
    private var requested: String? {
        get { lock.withLock { requestedPath } }
        set { lock.withLock { requestedPath = newValue } }
    }

    func show(path: String?) {
        guard path != requested else { return }
        requested = path
        guard let path else {
            details = nil
            return
        }
        if let cached = cache[path] {
            details = cached
            return
        }
        details = nil
        queue.async { [weak self] in
            let read = CommandBarItemDetails.read(path: path)
            DispatchQueue.main.async { self?.deliver(read) }
            guard read.isApp, read.size == nil else { return }
            let size = CommandBarItemDetails.bundleSize(at: path) { [weak self] in
                // A walk nobody is looking at any more stops early; the next
                // look starts it again.
                self?.requested != path
            }
            guard let size else { return }
            DispatchQueue.main.async { self?.deliver(read.withSize(size)) }
        }
    }

    private func deliver(_ read: CommandBarItemDetails) {
        // Small enough to keep whole; a long session still stays bounded.
        if cache.count > 200 { cache.removeAll() }
        if read.size != nil || !read.isApp { cache[read.path] = read }
        if requested == read.path { details = read }
    }
}
