// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// Vorssaint's ClipNote history lives in its own folder: the standalone app's
/// history is copied in once, while that app may still be writing, and its
/// folder is left untouched. Every folder here is a scratch one.
enum ClipNoteStorageTests {
    static func run(_ suite: TestSuite) {
        suite.clipNoteCase("history copied from a running standalone app") { scratch in
            let standalone = scratch.folder("standalone")
            let container = scratch.folder("container")
            let target = container.appendingPathComponent(ClipNoteStorage.folderName, isDirectory: true)
            // Left open on purpose: its connection keeps recent writes in the
            // write-ahead log, as a running standalone app would.
            let writer = try ClipStore(directory: standalone, postsNotifications: false)
            try writer.insert(NewClip(type: .text, content: "部署脚本", searchText: "部署脚本", hash: "a"))
            try writer.insert(NewClip(type: .image, content: "Images/one.png", searchText: "",
                                      hash: "img"))
            try Data("png".utf8).write(to: standalone.appendingPathComponent("Images/one.png"))
            try Data("html".utf8).write(to: standalone.appendingPathComponent("Data/rich.html"))

            let outcome = ClipNoteStorage.prepare(directory: target, standalone: standalone, container: container)
            suite.expectEqual(outcome, .copied, "a history in the standalone folder is copied in")

            try writer.insert(NewClip(type: .text, content: "later", searchText: "later", hash: "later"))
            let copy = try ClipStore(directory: target, postsNotifications: false)
            var search = ClipQuery()
            search.text = "部署"
            suite.expectEqual(copy.count(), 2, "the copy holds the snapshot, not writes made after it")
            suite.expectEqual(copy.fetch(search).map(\.content), ["部署脚本"],
                              "the copied history searches, recent log writes included")
            let fm = FileManager.default
            suite.expect(fm.fileExists(atPath: target.appendingPathComponent("Images/one.png").path)
                         && fm.fileExists(atPath: target.appendingPathComponent("Data/rich.html").path),
                         "images and attachments come along under the same relative paths")
            suite.expectEqual(writer.count(), 3, "the standalone history keeps working after the copy")
            let mode = (try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int) ?? 0
            suite.expectEqual(mode & 0o777, 0o700, "the copied history is readable by its owner only")
            let leftovers = try fm.contentsOfDirectory(atPath: container.path).filter { $0.hasPrefix(".") }
            suite.expect(leftovers.isEmpty, "no staging folder stays behind")

            try copy.insert(NewClip(type: .text, content: "mine", searchText: "mine", hash: "mine"))
            suite.expectEqual(ClipNoteStorage.prepare(directory: target, standalone: standalone,
                                                      container: container), .ready,
                              "a history already in place is never copied over")
            suite.expectEqual(copy.count(), 3, "and keeps what was added since")
        }

        suite.clipNoteCase("fresh start without a standalone history") { scratch in
            let container = scratch.folder("container")
            let target = container.appendingPathComponent(ClipNoteStorage.folderName, isDirectory: true)
            let outcome = ClipNoteStorage.prepare(directory: target, standalone: scratch.folder("missing"),
                                                  container: container)
            suite.expectEqual(outcome, .ready, "nothing to bring over starts a new history")
            suite.expect(FileManager.default.fileExists(atPath: target.path),
                         "the folder exists for the store to open")
        }

        suite.clipNoteCase("folders a failed start left behind") { scratch in
            let standalone = scratch.folder("standalone")
            _ = try ClipStore(directory: standalone, postsNotifications: false)
            let container = scratch.folder("container")
            let target = container.appendingPathComponent(ClipNoteStorage.folderName, isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: target.appendingPathComponent("Images"), withIntermediateDirectories: true)
            let stale = container.appendingPathComponent(".ClipNote-moving-stale")
            try fm.createDirectory(at: stale, withIntermediateDirectories: true)
            suite.expectEqual(ClipNoteStorage.prepare(directory: target, standalone: standalone,
                                                      container: container), .copied,
                              "empty folders from a failed start give way to the copy")
            suite.expect(!fm.fileExists(atPath: stale.path), "a copy a crash cut short is cleared")

            let kept = scratch.folder("kept")
            let keptTarget = kept.appendingPathComponent(ClipNoteStorage.folderName, isDirectory: true)
            try fm.createDirectory(at: keptTarget.appendingPathComponent("Images"), withIntermediateDirectories: true)
            let file = keptTarget.appendingPathComponent("Images/own.png")
            try Data("own".utf8).write(to: file)
            suite.expectEqual(ClipNoteStorage.prepare(directory: keptTarget, standalone: standalone,
                                                      container: kept), .ready,
                              "a folder holding files is never replaced")
            suite.expect(fm.fileExists(atPath: file.path), "and its files stay")
        }
    }
}
