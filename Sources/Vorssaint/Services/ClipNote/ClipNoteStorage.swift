// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where Vorssaint keeps ClipNote's history: one fixed folder, whichever
/// build runs and whatever its version. A history there is opened; without
/// one a new history starts. Nothing is brought in from anywhere else.
enum ClipNoteStorage {
    static let folderName = "ClipNote"

    /// `~/Library/Application Support/Vorssaint`.
    static var container: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// `~/Library/Application Support/Vorssaint/ClipNote`.
    static var directory: URL? {
        container?.appendingPathComponent(folderName, isDirectory: true)
    }
}
