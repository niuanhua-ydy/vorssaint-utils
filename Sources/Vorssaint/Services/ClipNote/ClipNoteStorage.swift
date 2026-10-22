// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Where Vorssaint keeps ClipNote's history: in its own Application Support
/// container, apart from the standalone ClipNote app's folder. Removing that
/// app, with any uninstaller, then never takes Vorssaint's history with it.
enum ClipNoteStorage {
    static let folderName = "ClipNote"
    static let databaseName = "clipnote.sqlite"
    private static let stagingPrefix = ".ClipNote-moving-"

    /// `~/Library/Application Support/<bundle id>/ClipNote`, nil outside a
    /// real bundle.
    static var directory: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The standalone app's folder, read once to bring its history over.
    static var standaloneDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    enum Outcome: Equatable {
        /// The directory holds a history, or a fresh one may start there.
        case ready
        /// The standalone app's history was copied in.
        case copied
        case failed(String)
    }

    /// Makes `directory` ready before the store opens it. A history already
    /// there is left alone. Otherwise the standalone app's history is copied
    /// in, never moved, so that app keeps working until it is removed and
    /// its folder stays a backup. The copy is assembled beside the target and
    /// renamed into place, so an interrupted one never reads as a history.
    static func prepare(directory: URL, standalone: URL, container: URL?) -> Outcome {
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        removeStaleStaging(in: parent)
        if fm.fileExists(atPath: directory.appendingPathComponent(databaseName).path) { return .ready }

        let source = standalone.appendingPathComponent(databaseName)
        let standaloneIsLink = (try? standalone.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        guard fm.fileExists(atPath: source.path), !standaloneIsLink else {
            PrivateFileStore.createDirectory(at: directory, container: container)
            return .ready
        }
        // A store that failed to open may have left its empty folders; any
        // file in there is someone's data and is never replaced.
        if fm.fileExists(atPath: directory.path) {
            guard holdsNoFiles(directory) else { return .ready }
            guard (try? fm.removeItem(at: directory)) != nil else {
                return .failed("could not clear \(directory.path)")
            }
        }

        let staging = parent.appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: staging, container: container) else {
            return .failed("could not create \(staging.path)")
        }
        func abandon(_ reason: String) -> Outcome {
            try? fm.removeItem(at: staging)
            return .failed(reason)
        }
        // The database first: its snapshot names only files written before
        // it, which the folder copy below then still finds.
        if let error = backupDatabase(from: source, to: staging.appendingPathComponent(databaseName)) {
            return abandon(error)
        }
        let entries = (try? fm.contentsOfDirectory(atPath: standalone.path)) ?? []
        for name in entries where !name.hasPrefix(".") && !name.hasPrefix(databaseName) {
            do {
                // APFS clones each file, so the copy takes no extra space.
                try fm.copyItem(at: standalone.appendingPathComponent(name),
                                to: staging.appendingPathComponent(name))
            } catch {
                return abandon("could not copy \(name): \(error.localizedDescription)")
            }
        }
        do {
            try fm.moveItem(at: staging, to: directory)
        } catch {
            return abandon("could not move the history into place: \(error.localizedDescription)")
        }
        PrivateFileStore.createDirectory(at: directory, container: container)
        return .copied
    }

    /// SQLite's online backup copies a consistent snapshot of the pages, the
    /// write-ahead log included, even while the standalone app is writing.
    /// A plain file copy could catch the database and its log mid-write.
    private static func backupDatabase(from source: URL, to destination: URL) -> String? {
        var from: OpaquePointer?
        var to: OpaquePointer?
        defer {
            sqlite3_close(from)
            sqlite3_close(to)
        }
        guard sqlite3_open_v2(source.path, &from, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return "could not open \(source.path)"
        }
        guard sqlite3_open_v2(destination.path, &to, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK
        else { return "could not create \(destination.path)" }
        guard let backup = sqlite3_backup_init(to, "main", from, "main") else {
            return "could not start the copy: \(String(cString: sqlite3_errmsg(to)))"
        }
        // A writer holding the database a moment makes a step busy; the copy
        // waits for it instead of giving up.
        var rc = sqlite3_backup_step(backup, -1)
        var attempts = 0
        while (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) && attempts < 50 {
            attempts += 1
            sqlite3_sleep(100)
            rc = sqlite3_backup_step(backup, -1)
        }
        sqlite3_backup_finish(backup)
        guard rc == SQLITE_DONE else { return "could not copy the history (SQLite \(rc))" }
        return nil
    }

    private static func holdsNoFiles(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return false }
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            return false
        }
        return true
    }

    /// A copy a crash cut short is only ever half a history.
    private static func removeStaleStaging(in parent: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(stagingPrefix) {
            try? fm.removeItem(at: parent.appendingPathComponent(name))
        }
    }
}
