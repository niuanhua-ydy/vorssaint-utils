// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// ClipNote's multi-device sync: a local folder stands in for the cloud and
/// one store per device for each Mac. Merging must converge in any order,
/// deletions must not be undone by stale updates, and encryption must keep
/// plain text out of the uploaded batches.
enum ClipNoteSyncTests {
    static func run(_ suite: TestSuite) {
        convergence(suite)
        conflicts(suite)
        encryption(suite)
        uploads(suite)
        reduction(suite)
    }

    private struct Device {
        let store: ClipStore
        let engine: SyncEngine

        func sync() async throws -> SyncReport { try await engine.syncOnce() }
    }

    private final class Cloud: @unchecked Sendable {
        let scratch: ClipNoteScratch
        let root: URL

        init(_ scratch: ClipNoteScratch) {
            self.scratch = scratch
            root = scratch.folder("remote")
        }

        func device(_ name: String, passphrase: String? = nil, compaction: Int = 64,
                    maxFileBytes: Int? = nil) throws -> Device {
            let store = try scratch.store(name)
            store.isSyncRecording = true
            var config = SyncConfiguration(deviceName: name, passphrase: passphrase, includeImages: true, target: "test",
                                           compactionThreshold: compaction)
            if let maxFileBytes { config.maxFileBytes = maxFileBytes }
            return Device(store: store, engine: SyncEngine(store: store, remote: LocalDirectoryRemote(root: root),
                                                           configuration: config))
        }
    }

    @discardableResult
    private static func addImage(_ store: ClipStore, bytes: [UInt8]) throws -> Int64 {
        let path = "Images/\(UUID().uuidString).png"
        let data = Data([0x89, 0x50, 0x4E, 0x47] + bytes)
        try data.write(to: store.url(forRelativePath: path))
        return try store.insert(NewClip(type: .image, content: path, searchText: "", width: 10, height: 10,
                                        hash: ContentHash.forImage(data)))
    }

    /// Each item as hash, type and pinboard name, comparable across devices.
    private static func snapshot(_ store: ClipStore) -> [String] {
        store.fetch(ClipQuery(limit: 10_000)).map { item in
            let board = store.pinboards().first { $0.id == item.pinboardID }?.name ?? "-"
            return "\(item.hash.prefix(8))|\(item.type.rawValue)|\(board)"
        }.sorted()
    }

    private static func pause() async throws { try await Task.sleep(nanoseconds: 20_000_000) }

    private static func convergence(_ suite: TestSuite) {
        suite.clipNoteAsyncCase("two devices converge") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            let board = try clipNoteUnwrap(a.store.createPinboard(name: "服务器", color: "#30D158"), "A's pinboard")
            let textID = try a.store.addTestText("ssh root@10.0.0.1 部署")
            a.store.setPinboard(itemID: textID, pinboardID: board.id)
            let imageID = try addImage(a.store, bytes: [1, 2, 3])
            a.store.appendSearchText(id: imageID, text: "发票号码")
            try b.store.addTestText("B 上原有的内容")

            _ = try await a.sync()
            let report = try await b.sync()
            suite.expectEqual(report.otherDevices, 1, "B sees one other device")
            _ = try await a.sync()

            suite.expectEqual(snapshot(a.store), snapshot(b.store), "both devices hold the same items")
            suite.expectEqual(b.store.count(), 3, "B holds A's items and its own")
            suite.expectEqual(b.store.pinboards().first?.color, "#30D158", "a pinboard's color syncs")
            suite.expectEqual(b.store.fetch(ClipQuery(text: "部署")).count, 1, "synced text is indexed")
            suite.expectEqual(b.store.fetch(ClipQuery(text: "发票号码")).count, 1, "recognized image text syncs")
            let image = try clipNoteUnwrap(b.store.fetch(ClipQuery(type: .image)).first, "B's synced image")
            suite.expectEqual(try Data(contentsOf: b.store.url(forRelativePath: image.content)),
                              Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), "an image's file syncs")
            suite.expectEqual(a.store.fetch(ClipQuery(text: "原有")).count, 1, "B's items reach A too")
        }

        suite.clipNoteAsyncCase("deletes, pins and renames propagate") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            let x = try a.store.addTestText("会被删除的条目")
            let y = try a.store.addTestText("会被固定的条目")
            _ = try await a.sync()
            _ = try await b.sync()

            let bx = try clipNoteUnwrap(b.store.fetch(ClipQuery(text: "被删除")).first, "B's copy of x")
            b.store.delete(ids: [bx.id])
            let board = try clipNoteUnwrap(b.store.createPinboard(name: "AI", color: "#FF9F0A"), "B's pinboard")
            let by = try clipNoteUnwrap(b.store.fetch(ClipQuery(text: "被固定")).first, "B's copy of y")
            b.store.setPinboard(itemID: by.id, pinboardID: board.id)
            _ = try await b.sync()
            _ = try await a.sync()
            suite.expect(a.store.item(id: x) == nil, "a deletion on B reaches A")
            suite.expectEqual(a.store.pinboards().map(\.name), ["AI"], "a pinboard made on B reaches A")
            suite.expectEqual(a.store.item(id: y)?.pinboardID, a.store.pinboards().first?.id, "a pin on B reaches A")

            var renamed = try clipNoteUnwrap(a.store.pinboards().first, "A's pinboard")
            renamed.name = "人工智能"
            a.store.updatePinboard(renamed)
            _ = try await a.sync()
            _ = try await b.sync()
            suite.expectEqual(b.store.pinboards().map(\.name), ["人工智能"], "a rename on A reaches B")
            suite.expectEqual(b.store.item(id: by.id)?.pinboardID, b.store.pinboards().first?.id,
                              "a renamed pinboard keeps its items")
            suite.expectEqual(snapshot(a.store), snapshot(b.store), "both devices end the same")
        }

        suite.clipNoteAsyncCase("compaction keeps state for new devices") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A", compaction: 5)
            var ids: [Int64] = []
            for i in 0..<8 {
                ids.append(try a.store.addTestText("条目 \(i)"))
                if i == 3 { ids.append(try addImage(a.store, bytes: [9, 9])) }
                _ = try await a.sync()
            }
            a.store.delete(ids: [ids[0]])
            _ = try await a.sync()
            let deviceFolder = cloud.root.appendingPathComponent("devices/\(await a.engine.deviceID)")
            let segments = try FileManager.default.contentsOfDirectory(atPath: deviceFolder.path)
                .filter { $0.hasSuffix(".jsonl") }
            suite.expect(segments.count < 5, "batches past the threshold are merged, found \(segments.count)")

            let c = try cloud.device("C")
            _ = try await c.sync()
            suite.expectEqual(snapshot(c.store), snapshot(a.store), "a new device gets the merged state")
            suite.expectEqual(c.store.fetch(ClipQuery(type: .image)).count, 1, "merged batches still carry the image")
        }
    }

    private static func conflicts(_ suite: TestSuite) {
        suite.clipNoteAsyncCase("a stale update does not undo a deletion") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            let id = try a.store.addTestText("旧内容")
            // C stays offline the whole time, holding an older copy of the same text.
            let c = try cloud.device("C")
            try c.store.addTestText("旧内容", date: Date(timeIntervalSinceNow: -3600))
            _ = try await a.sync()
            _ = try await b.sync()

            // A uses the item without syncing, then B deletes it.
            a.store.markUsed(id: id)
            try await pause()
            let bItem = try clipNoteUnwrap(b.store.fetch(ClipQuery()).first, "B's copy")
            b.store.delete(ids: [bItem.id])
            _ = try await b.sync()
            _ = try await a.sync()
            _ = try await b.sync()
            suite.expect(a.store.item(id: id) == nil, "the deletion reaches A")
            suite.expectEqual(b.store.count(), 0, "an earlier use does not bring a deleted item back")

            // C comes online and uploads a full snapshot holding the old copy.
            _ = try await c.sync()
            _ = try await a.sync()
            _ = try await b.sync()
            suite.expectEqual(a.store.count(), 0, "C's old copy does not reach A")
            suite.expectEqual(b.store.count(), 0, "C's old copy does not reach B")
            suite.expectEqual(c.store.count(), 0, "C drops its old copy on seeing the deletion")

            // Copying the same text again, after the deletion, brings it back.
            try a.store.addTestText("旧内容")
            _ = try await a.sync()
            _ = try await b.sync()
            suite.expectEqual(b.store.count(), 1, "a copy newer than the deletion syncs")
        }

        suite.clipNoteAsyncCase("concurrent pins converge to the latest") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            let id = try a.store.addTestText("冲突测试")
            let boardA = try clipNoteUnwrap(a.store.createPinboard(name: "工作", color: "#0A84FF"), "A's pinboard")
            _ = try await a.sync()
            _ = try await b.sync()
            let boardB = try clipNoteUnwrap(b.store.createPinboard(name: "生活", color: "#30D158"), "B's pinboard")
            let bItem = try clipNoteUnwrap(b.store.fetch(ClipQuery()).first, "B's copy")

            a.store.setPinboard(itemID: id, pinboardID: boardA.id)
            try await pause()
            b.store.setPinboard(itemID: bItem.id, pinboardID: boardB.id)
            _ = try await a.sync()
            _ = try await b.sync()
            _ = try await a.sync()
            suite.expectEqual(snapshot(a.store), snapshot(b.store), "both devices end the same")
            suite.expectEqual(a.store.pinboards().first { $0.id == a.store.item(id: id)?.pinboardID }?.name, "生活",
                              "the later pin wins")
        }

        suite.clipNoteAsyncCase("titles sync, latest wins") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            let id = try a.store.addTestText("带标题的条目")
            _ = try await a.sync()
            _ = try await b.sync()
            let bItem = try clipNoteUnwrap(b.store.fetch(ClipQuery()).first, "B's copy")

            a.store.setTitle(itemID: id, title: "A 的标题")
            try await pause()
            b.store.setTitle(itemID: bItem.id, title: "B 的标题（更晚）")
            _ = try await a.sync()
            _ = try await b.sync()
            _ = try await a.sync()
            suite.expectEqual(a.store.item(id: id)?.title, "B 的标题（更晚）", "the later title reaches A")
            suite.expectEqual(b.store.item(id: bItem.id)?.title, "B 的标题（更晚）", "the later title stays on B")

            a.store.setTitle(itemID: id, title: nil)
            _ = try await a.sync()
            _ = try await b.sync()
            suite.expect(b.store.item(id: bItem.id)?.title == nil, "clearing a title syncs")

            b.store.setTitle(itemID: bItem.id, title: "最终标题")
            _ = try await b.sync()
            let c = try cloud.device("C")
            _ = try await c.sync()
            suite.expectEqual(c.store.fetch(ClipQuery()).first?.title, "最终标题", "a new device gets titles from the snapshot")
        }

        suite.clipNoteCase("an update arriving before its item is kept") { scratch in
            let store = try scratch.store()
            _ = store.createPinboard(name: "AI", color: "#FF9F0A")

            var meta = SyncOp(op: .meta, at: 300)
            meta.hash = "h1"
            meta.updatedAt = 300
            meta.useCount = 5
            meta.title = "最终标题"
            meta.titledAt = 300
            meta.pinboard = "AI"
            meta.pinnedAt = 300
            try store.applySyncOps([meta], files: [:])
            suite.expectEqual(store.count(), 0, "an update alone creates no item")

            var item = SyncOp(op: .item, at: 100)
            item.hash = "h1"
            item.type = "text"
            item.content = "正文来自另一台设备"
            item.createdAt = 100
            item.updatedAt = 100
            item.title = "旧标题"
            item.titledAt = 100
            try store.applySyncOps([item], files: [:])

            let result = try clipNoteUnwrap(store.fetch(ClipQuery()).first, "the merged item")
            suite.expectEqual(result.title, "最终标题", "the earlier-arriving title wins over the item's older one")
            suite.expectEqual(result.useCount, 5, "the earlier-arriving use count is kept")
            suite.expectClose(result.updatedAt.timeIntervalSince1970, 300, "the later update time is kept", tol: 0.01)
            suite.expectEqual(store.pinboards().first { $0.id == result.pinboardID }?.name, "AI",
                              "the earlier-arriving pin is kept")
        }
    }

    private static func encryption(_ suite: TestSuite) {
        suite.clipNoteAsyncCase("encryption") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A", passphrase: "correct horse")
            try a.store.addTestText("机密：数据库密码 hunter2")
            _ = try await a.sync()

            let uploaded = try FileManager.default.subpathsOfDirectory(atPath: cloud.root.path)
                .filter { $0.hasSuffix(".jsonl") }
            suite.expect(!uploaded.isEmpty, "the sync uploaded batches to look into")
            for path in uploaded {
                let data = try Data(contentsOf: cloud.root.appendingPathComponent(path))
                suite.expect(data.range(of: Data("hunter2".utf8)) == nil, "\(path) holds no plain text")
            }

            func syncError(_ device: Device) async -> SyncError? {
                do {
                    _ = try await device.sync()
                    return nil
                } catch {
                    return error as? SyncError
                }
            }
            let withoutPassphrase = try cloud.device("B")
            let wrongPassphrase = try cloud.device("C", passphrase: "wrong")
            suite.expectEqual(await syncError(withoutPassphrase), .passphraseRequired,
                              "a device without the passphrase is asked for it")
            suite.expectEqual(await syncError(wrongPassphrase), .wrongPassphrase, "a wrong passphrase is reported")
            let right = try cloud.device("D", passphrase: "correct horse")
            _ = try await right.sync()
            suite.expectEqual(right.store.fetch(ClipQuery(text: "hunter2")).count, 1, "the right passphrase decrypts")
        }
    }

    private static func uploads(_ suite: TestSuite) {
        suite.clipNoteAsyncCase("incremental upload") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A"), b = try cloud.device("B")
            _ = try await a.sync()
            _ = try await b.sync()
            let id = try a.store.addTestText("新复制的内容")
            suite.expectEqual(a.store.pendingSyncChangeCount, 1, "a new item is queued")
            let report = try await a.sync()
            suite.expectEqual(report.uploadedOps, 1, "only the new item uploads")
            suite.expectEqual(a.store.pendingSyncChangeCount, 0, "the queue empties after upload")
            a.store.markUsed(id: id)
            let metaReport = try await a.sync()
            suite.expectEqual(metaReport.uploadedOps, 1, "a use uploads as one change")
            _ = try await b.sync()
            suite.expectEqual(b.store.fetch(ClipQuery()).first?.useCount, 1, "the use count reaches B")
            suite.expectEqual(b.store.pendingSyncChangeCount, 0, "received changes are not uploaded again")
        }

        suite.clipNoteAsyncCase("large items stay local") { scratch in
            let cloud = Cloud(scratch)
            let a = try cloud.device("A", maxFileBytes: 1024), b = try cloud.device("B", maxFileBytes: 1024)
            let big = String(repeating: "大", count: 1000) // 3000 bytes, over the 1 KB limit
            try a.store.addTestText(big)
            try a.store.addTestText("小条目")
            // Rich text whose formatting is too large syncs as plain text.
            try Data(repeating: 0x41, count: 4096).write(to: a.store.url(forRelativePath: "Data/big.rtf"))
            try a.store.insert(NewClip(type: .rich, content: "带格式的短文字", dataPath: "Data/big.rtf",
                                       dataType: "public.rtf", searchText: "带格式的短文字",
                                       hash: ContentHash.forText("带格式的短文字")))
            // A file item syncs only its path.
            try a.store.insert(NewClip(type: .file, content: "/Users/x/很大的视频.mov", searchText: "很大的视频.mov",
                                       hash: ContentHash.forFiles(["/Users/x/很大的视频.mov"])))
            _ = try await a.sync()
            _ = try await b.sync()

            suite.expectEqual(a.store.count(), 4, "this Mac keeps everything")
            let received = b.store.fetch(ClipQuery(limit: 100))
            suite.expectEqual(received.count, 3, "text over the limit is not uploaded")
            suite.expect(!received.contains { $0.charCount == 1000 }, "the large text is not on B")
            let rich = try clipNoteUnwrap(received.first { $0.content == "带格式的短文字" }, "the rich item on B")
            suite.expectEqual(rich.type, .text, "rich text with oversized formatting arrives as plain text")
            suite.expect(rich.dataPath == nil, "oversized formatting data is not uploaded")
            suite.expectEqual(received.first { $0.type == .file }?.content, "/Users/x/很大的视频.mov",
                              "a file item arrives as its path")
        }
    }

    private static func reduction(_ suite: TestSuite) {
        var item = SyncOp(op: .item, at: 1)
        item.hash = "h"
        item.content = "x"
        item.updatedAt = 1
        var meta = SyncOp(op: .meta, at: 2)
        meta.hash = "h"
        meta.updatedAt = 2
        meta.useCount = 3
        meta.pinboard = "AI"
        meta.pinnedAt = 2
        var board = SyncOp(op: .board, at: 1)
        board.name = "AI"
        let reduced = SyncEngine.reduce([board, item, meta])
        suite.expectEqual(reduced.count, 2, "an update folds into its item")
        guard reduced.count == 2 else { return }
        suite.expectEqual(reduced[1].op, .item, "the folded change is the item")
        suite.expectEqual(reduced[1].content, "x", "folding keeps the content")
        suite.expectEqual(reduced[1].useCount, 3, "folding takes the update's use count")
        suite.expectEqual(reduced[1].pinboard, "AI", "folding takes the update's pin")
    }
}
