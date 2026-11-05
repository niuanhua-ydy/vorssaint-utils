// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// ClipNote's store: ordering, de-duplication, the two full-text indexes
/// (trigram for longer words, adjacent pairs for one or two characters, so
/// Chinese works), schema migration, pinboards, retention and titles.
enum ClipNoteStoreTests {
    static func run(_ suite: TestSuite) {
        ordering(suite)
        search(suite)
        migration(suite)
        pinboardsAndFiles(suite)
        titles(suite)
        editing(suite)
        ocrBackfill(suite)
        mergeImport(suite)
        textUtilities(suite)
    }

    private static func ordering(_ suite: TestSuite) {
        suite.clipNoteCase("insert and fetch") { scratch in
            let store = try scratch.store()
            try store.addTestText("first", date: Date(timeIntervalSinceNow: -100))
            try store.addTestText("second", date: Date(timeIntervalSinceNow: -10))
            suite.expectEqual(store.fetch(ClipQuery()).map(\.content), ["second", "first"],
                              "the newest item comes first")
        }

        suite.clipNoteCase("de-duplication") { scratch in
            let store = try scratch.store()
            let id = try store.addTestText("same", date: Date(timeIntervalSinceNow: -100))
            try store.addTestText("other", date: Date(timeIntervalSinceNow: -50))
            suite.expect(store.contains(hash: ContentHash.forText("same")), "the store finds an item by its hash")
            suite.expect(store.touch(hash: ContentHash.forText("same"), sourceBundleID: "com.test", sourceAppName: "Test"),
                         "touching a known hash succeeds")
            let items = store.fetch(ClipQuery())
            suite.expectEqual(items.count, 2, "touching adds no item")
            suite.expectEqual(items.first?.id, id, "a touched item moves to the front")
            suite.expectEqual(items.first?.sourceBundleID, "com.test", "a touched item takes the new source app")
            try store.addTestText("same")
            suite.expectEqual(store.count(), 2, "inserting a known hash again adds no item")
        }

        suite.clipNoteCase("renewing keeps the index") { scratch in
            let store = try scratch.store()
            let text = "很久以前复制的 kubernetes 配置"
            let old = try store.addTestText(text, date: Date(timeIntervalSinceNow: -3600))
            try store.addTestText("最近的内容")
            suite.expect(store.touch(hash: ContentHash.forText(text), sourceBundleID: nil, sourceAppName: nil),
                         "an old item can be touched")
            suite.expectEqual(store.fetch(ClipQuery()).first?.id, old, "a renewed item moves to the front")
            suite.expectEqual(store.fetch(ClipQuery(text: "kubernetes")).first?.id, old,
                              "the trigram index still finds a renewed item")
            suite.expectEqual(store.fetch(ClipQuery(text: "配置")).first?.id, old,
                              "the short-word index still finds a renewed item")
            store.markUsed(id: old)
            suite.expectEqual(store.item(id: old)?.useCount, 1, "using an item counts it")
            suite.expectEqual(store.item(id: old)?.content, text, "a renewed item keeps its content")
        }

        suite.clipNoteCase("a just-used item outranks imported history") { scratch in
            let store = try scratch.store()
            let t0 = Date(timeIntervalSince1970: 1_700_000_000)
            let id = try store.insert(NewClip(type: .text, content: "a", searchText: "a", hash: "a"), date: t0)
            store.markUsed(id: id)
            try store.insert(NewClip(type: .text, content: "b", searchText: "b", hash: "b"), date: t0.addingTimeInterval(10))
            suite.expectEqual(store.fetch(ClipQuery()).map(\.content), ["a", "b"],
                              "an item used now sorts ahead of one dated later in the past")
        }

        suite.clipNoteCase("duplicates within one batch") { scratch in
            let store = try scratch.store()
            let t0 = Date(timeIntervalSince1970: 1_700_000_000)
            let a = NewClip(type: .text, content: "重复的部署脚本", searchText: "重复的部署脚本", hash: "dup")
            let b = NewClip(type: .text, content: "另一条", searchText: "另一条", hash: "other")
            try store.insertBatch([a, b, a], dates: [t0, t0.addingTimeInterval(1), t0.addingTimeInterval(2)])
            let items = store.fetch(ClipQuery())
            suite.expectEqual(items.map(\.content), ["重复的部署脚本", "另一条"],
                              "a repeat within a batch moves to the front once")
            suite.expectEqual(store.item(id: items[0].id)?.content, "重复的部署脚本",
                              "the content follows the renewed sequence number")
            suite.expectEqual(store.fetch(ClipQuery(text: "部署脚本")).count, 1, "the trigram index has the repeat once")
            suite.expectEqual(store.fetch(ClipQuery(text: "部署")).count, 1, "the short-word index has the repeat once")
        }

        suite.clipNoteCase("sequence numbers for colliding past times") { scratch in
            let store = try scratch.store()
            let t = Date(timeIntervalSince1970: 1_700_000_000)
            // Two at the same instant (the second takes the next number), then
            // one 0.1 s later, landing exactly on the number the second took.
            let clips = ["a", "b", "c"].map { NewClip(type: .text, content: $0, searchText: $0, hash: $0) }
            try store.insertBatch(clips, dates: [t, t, t.addingTimeInterval(0.1)])
            suite.expectEqual(store.count(), 3, "colliding times in a batch keep every item")
            try store.insert(NewClip(type: .text, content: "d", searchText: "d", hash: "d"), date: t)
            try store.insert(NewClip(type: .text, content: "e", searchText: "e", hash: "e"), date: t.addingTimeInterval(0.2))
            suite.expectEqual(store.count(), 5, "single inserts at taken times keep every item")
        }

        suite.clipNoteCase("reopening") { scratch in
            let folder = scratch.folder("reopen")
            try ClipStore(directory: folder, postsNotifications: false).addTestText("persisted")
            let reopened = try ClipStore(directory: folder, postsNotifications: false)
            suite.expectEqual(reopened.fetch(ClipQuery(text: "persisted")).count, 1, "items survive reopening the store")
        }
    }

    private static func search(_ suite: TestSuite) {
        suite.clipNoteCase("Chinese full-text search") { scratch in
            let store = try scratch.store()
            try store.addTestText("今天学习了 SQLite 的全文检索功能")
            try store.addTestText("服务器部署命令 docker compose up -d")
            try store.addTestText("无关内容")
            suite.expectEqual(store.fetch(ClipQuery(text: "全文检索")).count, 1, "a four-character Chinese word")
            suite.expectEqual(store.fetch(ClipQuery(text: "sqlite")).count, 1, "search ignores case")
            suite.expectEqual(store.fetch(ClipQuery(text: "部署")).count, 1, "a two-character Chinese word")
            suite.expectEqual(store.fetch(ClipQuery(text: "docker 部署")).count, 1, "several words must all match")
            suite.expectEqual(store.fetch(ClipQuery(text: "docker 学习")).count, 0, "words from different items match none")
            suite.expectEqual(store.fetch(ClipQuery(text: "\"quoted")).count, 0, "a stray quote is not a syntax error")
            suite.expectEqual(store.fetch(ClipQuery(text: "100%")).count, 0, "a percent sign is not a wildcard")
        }

        suite.clipNoteCase("one- and two-character search") { scratch in
            let store = try scratch.store()
            try store.addTestText("部署服务器")
            try store.addTestText("返回 json 数据")
            try store.addTestText("写一段 c# 代码")
            try store.addTestText("全部完成")
            suite.expectEqual(store.fetch(ClipQuery(text: "部")).count, 2, "one character at a word's start or end")
            suite.expectEqual(store.fetch(ClipQuery(text: "署")).count, 1, "one character inside a word")
            suite.expectEqual(store.fetch(ClipQuery(text: "器")).count, 1, "one character ending the text")
            suite.expectEqual(store.fetch(ClipQuery(text: "服务")).count, 1, "two characters at a word's start")
            suite.expectEqual(store.fetch(ClipQuery(text: "务器")).count, 1, "two characters at a word's end")
            suite.expectEqual(store.fetch(ClipQuery(text: "部成")).count, 0, "two characters must be adjacent")
            suite.expectEqual(store.fetch(ClipQuery(text: "js")).count, 1, "a short English word matches as a prefix")
            suite.expectEqual(store.fetch(ClipQuery(text: "JS")).count, 1, "short words ignore case")
            suite.expectEqual(store.fetch(ClipQuery(text: "c#")).count, 1, "an unusual short word falls back to LIKE")
            suite.expectEqual(store.fetch(ClipQuery(text: "部署 服务器")).count, 1, "short and long words combine")
        }

        suite.clipNoteCase("search pages across candidate windows") { scratch in
            let store = try scratch.store()
            let total = ClipStore.candidateWindow * 2 + 37
            let base = Date(timeIntervalSinceNow: -100_000)
            let clips = (0..<total).map { i -> NewClip in
                let t = "common keyword \(i)"
                return NewClip(type: .text, content: t, searchText: t, charCount: t.count, hash: ContentHash.forText(t))
            }
            try store.insertBatch(clips, dates: (0..<total).map { base.addingTimeInterval(Double($0)) })
            var seen = Set<Int64>()
            var offset = 0
            while true {
                let page = store.fetch(ClipQuery(text: "keyword", limit: 200, offset: offset))
                if page.isEmpty { break }
                seen.formUnion(page.map(\.id))
                offset += page.count
            }
            suite.expectEqual(offset, total, "paging returns no item twice")
            suite.expectEqual(seen.count, total, "paging misses no item")
        }

        suite.clipNoteCase("long text shows the hit") { scratch in
            let store = try scratch.store()
            let long = String(repeating: "无关的填充内容。", count: 1000) + "这里有目标关键字" + String(repeating: "尾部。", count: 100)
            try store.addTestText(long)
            let result = try clipNoteUnwrap(store.fetch(ClipQuery(text: "目标关键字")).first, "the long text's hit")
            suite.expect(result.content.contains("目标关键字"), "the preview of a long hit includes the match")
            suite.expect(result.content.hasPrefix("…"), "the preview of a long hit marks the cut before it")
        }

        suite.clipNoteCase("filters") { scratch in
            let store = try scratch.store()
            try store.addTestText("hello world", app: "com.apple.Terminal")
            try store.insert(NewClip(type: .link, content: "https://example.com/hello",
                                     searchText: "https://example.com/hello",
                                     hash: ContentHash.forLink("https://example.com/hello")))
            suite.expectEqual(store.fetch(ClipQuery(text: "hello", type: .link)).map(\.type), [.link],
                              "a type filter narrows a search")
            suite.expectEqual(store.fetch(ClipQuery(sourceBundleID: "com.apple.Terminal")).count, 1,
                              "a source app filter narrows the list")
            suite.expectEqual(store.sourceApps().map(\.bundleID), ["com.apple.Terminal"],
                              "source apps list only apps that were recorded")
        }

        suite.clipNoteCase("long content is cut in lists") { scratch in
            let store = try scratch.store()
            let id = try store.addTestText(String(repeating: "a", count: 10_000))
            suite.expectEqual(store.fetch(ClipQuery()).first?.content.count, ClipStore.previewLimit,
                              "a list carries only the preview")
            suite.expectEqual(store.item(id: id)?.content.count, 10_000, "the item itself keeps its full content")
        }
    }

    private static func migration(_ suite: TestSuite) {
        suite.clipNoteCase("v1 migration") { scratch in
            let folder = scratch.folder("v1")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let long = String(repeating: "长", count: 500) + "部署脚本"
            do {
                let db = try SQLiteDatabase(path: folder.appendingPathComponent("clipnote.sqlite").path)
                try db.execute(Migrator.v1Schema)
                try db.execute("PRAGMA user_version = 1")
                try db.run("INSERT INTO pinboard (name, color) VALUES ('AI', '#FF9F0A')")
                try db.run("""
                    INSERT INTO clip_item (type, content, search_text, source_bundle_id, source_app_name, char_count, hash,
                                           created_at, updated_at, pinboard_id)
                    VALUES ('text', ?, ?, 'com.apple.Terminal', '终端', ?, 'h1', 100, 100, 1),
                           ('image', 'Images/a.png', '截图里的文字', NULL, NULL, 0, 'h2', 200, 200, NULL)
                    """, [.text(long), .text(long), .int(Int64(long.count))])
            }
            let migrated = try ClipStore(directory: folder, postsNotifications: false)
            let items = migrated.fetch(ClipQuery())
            suite.expectEqual(items.map(\.type), [.image, .text], "migrated items keep their order by update time")
            guard items.count == 2 else { return }
            suite.expectEqual(items[0].content, "Images/a.png", "an image keeps its path")
            suite.expectEqual(items[1].content.count, ClipStore.previewLimit, "a migrated list carries only the preview")
            suite.expectEqual(migrated.item(id: items[1].id)?.content.count, 504, "the full content survives migration")
            suite.expectEqual(items[1].pinboardID, migrated.pinboards().first?.id, "pinboard membership survives migration")
            suite.expectEqual(migrated.fetch(ClipQuery(text: "部署脚本")).count, 1, "the trigram index is built")
            suite.expectEqual(migrated.fetch(ClipQuery(text: "部署")).count, 1, "the short-word index is built")
            suite.expectEqual(migrated.fetch(ClipQuery(text: "截图")).count, 1, "recognized image text is indexed")
            suite.expectEqual(migrated.sourceApps().map(\.name), ["终端"], "source apps are counted")
            try migrated.insert(NewClip(type: .text, content: "新内容", searchText: "新内容", hash: "h3"))
            suite.expectEqual(migrated.fetch(ClipQuery()).first?.content, "新内容", "a migrated store takes new items")
        }
    }

    private static func pinboardsAndFiles(_ suite: TestSuite) {
        suite.clipNoteCase("pinboards and retention") { scratch in
            let store = try scratch.store()
            let board = try clipNoteUnwrap(store.createPinboard(name: "AI", color: "#FF9F0A"), "the new pinboard")
            let old = try store.addTestText("old pinned", date: Date(timeIntervalSinceNow: -40 * 86400))
            try store.addTestText("old unpinned", date: Date(timeIntervalSinceNow: -40 * 86400))
            try store.addTestText("recent")
            store.setPinboard(itemID: old, pinboardID: board.id)

            suite.expectEqual(store.fetch(ClipQuery(scope: .pinboard(board.id))).map(\.id), [old],
                              "a pinboard lists its own items")
            store.applyRetention(maxAgeDays: 30, maxItems: 0)
            suite.expectEqual(Set(store.fetch(ClipQuery()).map(\.content)), ["old pinned", "recent"],
                              "retention by age spares pinned items")
            try store.addTestText("newer")
            store.applyRetention(maxAgeDays: 0, maxItems: 1)
            suite.expectEqual(Set(store.fetch(ClipQuery()).map(\.content)), ["old pinned", "newer"],
                              "retention by count spares pinned items")

            store.deletePinboard(id: board.id)
            suite.expect(store.item(id: old)?.pinboardID == nil, "deleting a pinboard returns its items to history")
            suite.expect(store.pinboards().isEmpty, "a deleted pinboard is gone")
        }

        suite.clipNoteCase("filtering by several types") { scratch in
            let store = try scratch.store()
            try store.addTestText("plain report")
            try store.insert(NewClip(type: .rich, content: "rich report", searchText: "rich report", hash: "r"))
            try store.insert(NewClip(type: .link, content: "https://report.example", searchText: "https://report.example",
                                     hash: "l"))
            suite.expectEqual(Set(store.fetch(ClipQuery(types: [.text, .rich])).map(\.content)),
                              ["plain report", "rich report"], "several types list each of them")
            suite.expectEqual(Set(store.fetch(ClipQuery(text: "report", types: [.text, .rich])).map(\.content)),
                              ["plain report", "rich report"], "a search keeps to the chosen types")
            suite.expectEqual(store.fetch(ClipQuery(text: "report", types: [.link])).map(\.content),
                              ["https://report.example"], "a search with another type is cached apart")
            suite.expectEqual(store.fetch(ClipQuery(type: .rich)).map(\.content), ["rich report"],
                              "one type still filters alone")
        }

        suite.clipNoteCase("deleting removes files") { scratch in
            let store = try scratch.store()
            let path = "Images/x.png"
            try Data([1, 2, 3]).write(to: store.url(forRelativePath: path))
            let id = try store.insert(NewClip(type: .image, content: path, searchText: "", hash: "img-x"))
            store.delete(ids: [id])
            suite.expect(!FileManager.default.fileExists(atPath: store.url(forRelativePath: path).path),
                         "deleting an image removes its file")
            suite.expectEqual(store.count(), 0, "a deleted item is gone")
        }

        suite.clipNoteCase("recognized text becomes searchable") { scratch in
            let store = try scratch.store()
            let id = try store.insert(NewClip(type: .image, content: "Images/a.png", searchText: "",
                                              width: 10, height: 10, hash: "img1"))
            suite.expectEqual(store.fetch(ClipQuery(text: "发票号码")).count, 0, "an image starts with no text")
            store.appendSearchText(id: id, text: "增值税发票号码 12345")
            suite.expectEqual(store.fetch(ClipQuery(text: "发票号码")).first?.id, id, "appended text is searchable")
        }

        suite.clipNoteCase("orphan files") { scratch in
            let store = try scratch.store()
            try Data([1]).write(to: store.url(forRelativePath: "Images/used.png"))
            try store.insert(NewClip(type: .image, content: "Images/used.png", searchText: "", hash: "i"))
            let orphan = store.url(forRelativePath: "Images/orphan.png")
            let fresh = store.url(forRelativePath: "Images/fresh.png")
            try Data([2]).write(to: orphan)
            try Data([3]).write(to: fresh)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                                  ofItemAtPath: orphan.path)
            suite.expectEqual(store.removeOrphanFiles(), 1, "one orphan file is removed")
            suite.expect(!FileManager.default.fileExists(atPath: orphan.path), "an old leftover file is removed")
            suite.expect(FileManager.default.fileExists(atPath: fresh.path),
                         "a file just written, perhaps not yet stored, is kept")
            suite.expect(FileManager.default.fileExists(atPath: store.url(forRelativePath: "Images/used.png").path),
                         "a file an item uses is kept")
        }
    }

    private static func titles(_ suite: TestSuite) {
        suite.clipNoteCase("titles") { scratch in
            let store = try scratch.store()
            let id = try store.insert(NewClip(type: .text, content: "ssh root@10.0.0.1", searchText: "ssh root@10.0.0.1",
                                              hash: "a"))
            try store.insert(NewClip(type: .text, content: "生产服务器的另一条记录", searchText: "生产服务器的另一条记录",
                                     hash: "b"))
            suite.expectEqual(store.item(id: id)?.displayTitle, ClipType.text.displayName, "an untitled item shows its type")

            store.setTitle(itemID: id, title: "  生产服务器登录  ")
            suite.expectEqual(store.item(id: id)?.title, "生产服务器登录", "a title is trimmed")
            suite.expectEqual(store.fetch(ClipQuery()).first { $0.id == id }?.displayTitle, "生产服务器登录",
                              "a list shows the title")

            let results = store.fetch(ClipQuery(text: "生产服务器"))
            suite.expectEqual(results.first?.id, id, "a title hit ranks first")
            suite.expectEqual(results.count, 2, "title and content hits both appear, once each")
            suite.expectEqual(store.fetch(ClipQuery(text: "登录")).map(\.id), [id], "a two-character word finds a title")

            store.setTitle(itemID: id, title: "")
            suite.expect(store.item(id: id)?.title == nil, "an empty title clears it")
            suite.expectEqual(store.item(id: id)?.displayTitle, ClipType.text.displayName, "a cleared title shows the type again")
        }
    }

    private static func editing(_ suite: TestSuite) {
        suite.clipNoteCase("editing content") { scratch in
            let store = try scratch.store()
            store.isSyncRecording = true
            func clip(_ text: String) -> NewClip {
                NewClip(type: .text, content: text, searchText: text, charCount: text.count, hash: ContentHash.forText(text))
            }
            let t = Date(timeIntervalSince1970: 1_700_000_000)
            let id = try store.insert(clip("部署到测试环境"), date: t)
            store.markUsed(id: id)
            let board = try clipNoteUnwrap(store.createPinboard(name: "常用", color: "#FF9F0A"), "pinboard")
            store.setPinboard(itemID: id, pinboardID: board.id)
            store.setTitle(itemID: id, title: "部署")
            try store.addTestText("更新的另一条")

            let edited = try clipNoteUnwrap(store.replaceContent(itemID: id, with: clip("部署到生产环境")), "edited id")
            suite.expect(store.item(id: id) == nil, "the old item is gone")
            let item = try clipNoteUnwrap(store.item(id: edited), "edited item")
            suite.expectEqual(item.content, "部署到生产环境", "an edit replaces the content")
            suite.expectEqual(item.title, "部署", "an edit keeps the title")
            suite.expectEqual(item.pinboardID, board.id, "an edit keeps the pinboard")
            suite.expectEqual(item.useCount, 1, "an edit keeps the use count")
            suite.expectEqual(item.createdAt, t, "an edit keeps the creation date")
            suite.expectEqual(store.fetch(ClipQuery()).first?.id, edited, "an edited item moves to the front")
            suite.expectEqual(store.fetch(ClipQuery(text: "生产")).map(\.id), [edited], "the index finds the new text")
            suite.expect(store.fetch(ClipQuery(text: "测试环境")).isEmpty, "the index forgets the old text")
            let keys = Dictionary(uniqueKeysWithValues: store.pendingSyncChanges().map { ($0.key, $0.kind) })
            suite.expectEqual(keys["item:" + ContentHash.forText("部署到测试环境")], .delete, "the old content syncs as deleted")
            suite.expectEqual(keys["item:" + ContentHash.forText("部署到生产环境")], .upsert, "the new content syncs as added")

            suite.expectEqual(try store.replaceContent(itemID: edited, with: clip("部署到生产环境")), edited,
                              "saving unchanged text keeps the item")
            let other = try clipNoteUnwrap(store.itemID(hash: ContentHash.forText("更新的另一条")), "other id")
            suite.expectEqual(try store.replaceContent(itemID: edited, with: clip("更新的另一条")), other,
                              "editing into existing text merges with that item")
            suite.expectEqual(store.count(), 1, "the merge leaves one item")
            suite.expectEqual(store.item(id: other)?.title, "部署", "the merged item takes the missing title")
            suite.expectEqual(store.item(id: other)?.pinboardID, board.id, "the merged item takes the missing pinboard")
            suite.expect(try store.replaceContent(itemID: id, with: clip("x")) == nil, "a missing item edits nothing")
        }
    }

    private static func ocrBackfill(_ suite: TestSuite) {
        suite.clipNoteCase("background recognition") { scratch in
            let store = try scratch.store()
            store.isSyncRecording = true
            let t = Date(timeIntervalSince1970: 1_700_000_000)
            let old = try store.insert(NewClip(type: .image, content: "Images/old.png", searchText: "", hash: "i1"), date: t)
            let new = try store.insert(NewClip(type: .image, content: "Images/new.png", searchText: "", hash: "i2"),
                                       date: t.addingTimeInterval(60))
            let broken = try store.insert(NewClip(type: .image, content: "Images/broken.png", searchText: "", hash: "i3"),
                                          date: t.addingTimeInterval(30))
            try store.insert(NewClip(type: .image, content: "Images/synced.png", searchText: "同步来的识别文字", hash: "i4"),
                             date: t)
            try store.insert(NewClip(type: .text, content: "文本不参与", searchText: "文本不参与", hash: "t"), date: t)
            let pendingBefore = store.pendingSyncChangeCount

            suite.expectEqual(store.ocrStats().total, 4, "only images count")
            suite.expectEqual(store.ocrStats().done, 1, "an image that came with text counts as recognized")
            suite.expectEqual(store.pendingOCRImages(limit: 10).map(\.id), [new, broken, old], "the newest goes first")
            suite.expectEqual(store.pendingOCRImages(limit: 10).first?.url.lastPathComponent, "new.png",
                              "a pending image points at its file")

            store.completeOCR(id: new, text: "发票号码 12345", recordSync: false)
            store.completeOCR(id: broken, text: nil, recordSync: false)
            store.completeOCR(id: old, text: "", recordSync: false)
            let stats = store.ocrStats()
            suite.expectEqual([stats.done, stats.failed, stats.pending], [3, 1, 0], "outcomes are counted")
            suite.expect(store.pendingOCRImages(limit: 10).isEmpty, "an image that failed is not retried")
            suite.expectEqual(store.fetch(ClipQuery(text: "发票号码")).first?.id, new, "recognized text is searchable")
            suite.expectEqual(store.pendingSyncChangeCount, pendingBefore, "background recognition uploads nothing")
        }

        suite.clipNoteCase("migration marks recognized images") { scratch in
            let folder = scratch.folder("ocr-migration")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                let db = try SQLiteDatabase(path: folder.appendingPathComponent("clipnote.sqlite").path)
                try db.execute(Migrator.v1Schema)
                try db.execute("PRAGMA user_version = 1")
                try db.execute("""
                    INSERT INTO clip_item (type, content, search_text, hash, created_at, updated_at)
                    VALUES ('image', 'Images/a.png', '截图里的文字', 'h1', 100, 100),
                           ('image', 'Images/b.png', '', 'h2', 200, 200)
                    """)
            }
            let store = try ClipStore(directory: folder, postsNotifications: false)
            suite.expectEqual(store.ocrStats().done, 1, "an image with text before migration counts as recognized")
            suite.expectEqual(store.pendingOCRImages(limit: 10).map(\.url.lastPathComponent), ["b.png"],
                              "only the image without text waits")
        }
    }

    private static func mergeImport(_ suite: TestSuite) {
        suite.clipNoteCase("merge import") { scratch in
            let store = try scratch.store()
            let localBoard = try clipNoteUnwrap(store.createPinboard(name: "本地分类", color: "#000000"), "local pinboard")
            let importBoard = try clipNoteUnwrap(store.createPinboard(name: "导入分类", color: "#FFFFFF"), "import pinboard")
            let now = Date()
            let a = try store.insert(NewClip(type: .text, content: "两边都有，本地已分类", searchText: "x", hash: "a"), date: now)
            store.setPinboard(itemID: a, pinboardID: localBoard.id)
            store.setTitle(itemID: a, title: "本地标题")
            let b = try store.insert(NewClip(type: .text, content: "两边都有，本地未分类", searchText: "x", hash: "b"), date: now)
            store.markUsed(id: b)

            let old = now.addingTimeInterval(-86400)
            func imported(_ hash: String, _ content: String) -> ImportedClip {
                ImportedClip(clip: NewClip(type: .text, content: content, searchText: content, hash: hash),
                             createdAt: old, updatedAt: old, useCount: 9, pinboardID: importBoard.id, title: "导入标题")
            }
            let result = try store.importClips([imported("a", "被忽略"), imported("b", "被忽略"), imported("c", "只在导入方")])
            suite.expectEqual(result.inserted, 1, "only the new item is inserted")
            suite.expectEqual(result.skipped, 2, "items already here are skipped")

            let itemA = try clipNoteUnwrap(store.item(id: a), "item a")
            suite.expectEqual(itemA.content, "两边都有，本地已分类", "local content is not overwritten")
            suite.expectEqual(itemA.pinboardID, localBoard.id, "a local pinboard is not overwritten")
            suite.expectEqual(itemA.title, "本地标题", "a local title is not overwritten")
            let itemB = try clipNoteUnwrap(store.item(id: b), "item b")
            suite.expectEqual(itemB.pinboardID, importBoard.id, "a missing pinboard is filled in")
            suite.expectEqual(itemB.title, "导入标题", "a missing title is filled in")
            suite.expectEqual(itemB.useCount, 1, "the local use count stays")
            suite.expect(itemB.updatedAt > old, "the local time stays")
            let itemC = try clipNoteUnwrap(store.fetch(ClipQuery(text: "只在导入方")).first, "item c")
            suite.expectClose(itemC.updatedAt.timeIntervalSince1970, old.timeIntervalSince1970,
                              "a new item keeps its original time", tol: 0.2)
            suite.expectEqual(itemC.useCount, 9, "a new item keeps its use count")
            suite.expectEqual(store.count(), 3, "nothing is deleted")
        }

        suite.clipNoteCase("import without sync recording") { scratch in
            let store = try scratch.store()
            store.isSyncRecording = true
            _ = try store.importClips([ImportedClip(clip: NewClip(type: .text, content: "x", searchText: "x", hash: "x"),
                                                    createdAt: Date(), updatedAt: Date())], recordSync: false)
            suite.expectEqual(store.pendingSyncChangeCount, 0, "an import chosen not to sync is not queued for upload")
            try store.insert(NewClip(type: .text, content: "y", searchText: "y", hash: "y"))
            suite.expectEqual(store.pendingSyncChangeCount, 1, "recording resumes after the import")
        }
    }

    private static func textUtilities(_ suite: TestSuite) {
        suite.expectEqual(TextCleaner.collapseBlankLines("a  \n\n\n\nb\n \n"), "a\n\nb", "blank lines collapse")
        suite.expectEqual(TextCleaner.joinLines("你好\n世界\nhello\nworld"), "你好世界 hello world",
                          "joining lines spaces only between Latin words")

        let text = String(repeating: "x", count: 100) + "目标词" + "尾巴"
        suite.expect(Snippet.make(text, terms: ["目标"], maxLength: 40, leading: 5).hasPrefix("…xxxxx目标词"),
                     "a snippet starts a little before the hit")
        suite.expectEqual(Snippet.make("abc", terms: []), "abc", "a short text is its own snippet")

        let query = SearchQuery("ab  docker \"x\"y 部署 部 c#")
        suite.expectEqual(query.trigramExpression, "\"docker\" \"\"\"x\"\"y\"", "long words go to the trigram index")
        suite.expectEqual(query.wordExpression, "\"ab\"* \"部署\" \"部\"*", "short words go to the word index")
        suite.expectEqual(query.likeTerms, ["c#"], "unusual short words fall back to LIKE")

        suite.expectEqual(Segmenter.segment("部署docker服务器"), " 部署 署 docker 服务 务器 器 ",
                          "Chinese splits into adjacent pairs, Latin stays whole")
        suite.expectEqual(Segmenter.segment("a 中 b"), "a  中  b", "a lone character stays a word")
    }
}
