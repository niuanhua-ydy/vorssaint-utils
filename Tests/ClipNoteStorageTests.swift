// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// Vorssaint's ClipNote history lives in one fixed folder, whichever build
/// runs: a history there is opened, and without one a new history starts.
enum ClipNoteStorageTests {
    static func run(_ suite: TestSuite) {
        suite.clipNoteCase("one history for every build") { _ in
            let directory = try clipNoteUnwrap(ClipNoteStorage.directory, "the history folder")
            suite.expectEqual(Array(directory.pathComponents.suffix(3)), ["Application Support", "Vorssaint", "ClipNote"],
                              "the history lives in a folder no bundle id or version names")
        }

        suite.clipNoteCase("a missing history starts empty") { scratch in
            let container = scratch.folder("container")
            let directory = container.appendingPathComponent(ClipNoteStorage.folderName, isDirectory: true)
            suite.expect(PrivateFileStore.createDirectory(at: directory, container: container),
                         "the history folder is created")
            let mode = (try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int) ?? 0
            suite.expectEqual(mode & 0o777, 0o700, "the history folder is readable by its owner only")
            let store = try ClipStore(directory: directory, postsNotifications: false)
            suite.expectEqual(store.count(), 0, "nothing is brought in from anywhere else")
        }
    }
}
