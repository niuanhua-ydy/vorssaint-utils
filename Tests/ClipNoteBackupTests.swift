// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// ClipNote's zip backups and its import from Paste. A backup must round-trip
/// times, use counts, pinboards, titles and files, and importing it twice
/// must add nothing. Paste's library is a Core Data store read in place, so
/// the fake one below follows its schema and the import must leave it as is.
enum ClipNoteBackupTests {
    static func run(_ suite: TestSuite) {
        backups(suite)
        pasteLibrary(suite)
    }

    private static func backups(_ suite: TestSuite) {
        suite.clipNoteCase("backup round trip") { scratch in
            let source = try scratch.store("source")
            let board = try clipNoteUnwrap(source.createPinboard(name: "服务器", color: "#30D158"), "the pinboard")
            let t0 = Date(timeIntervalSince1970: 1_700_000_000)

            let text = "ssh root@10.0.0.1 部署脚本"
            let textID = try source.insert(NewClip(type: .text, content: text, searchText: text,
                                                   sourceBundleID: "com.apple.Terminal", sourceAppName: "终端",
                                                   charCount: text.count, hash: ContentHash.forText(text)), date: t0)
            source.setPinboard(itemID: textID, pinboardID: board.id)
            source.markUsed(id: textID)

            try Data("{\\rtf1 hello}".utf8).write(to: source.url(forRelativePath: "Data/r.rtf"))
            try source.insert(NewClip(type: .rich, content: "hello 富文本", dataPath: "Data/r.rtf", dataType: "public.rtf",
                                      searchText: "hello 富文本", charCount: 9, hash: ContentHash.forText("hello 富文本")),
                              date: t0.addingTimeInterval(10))

            try Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).write(to: source.url(forRelativePath: "Images/i.png"))
            let imageID = try source.insert(NewClip(type: .image, content: "Images/i.png", searchText: "",
                                                    width: 10, height: 20, hash: "i:abc"), date: t0.addingTimeInterval(20))
            source.appendSearchText(id: imageID, text: "发票号码 12345")

            let archive = try scratch.file("archive.zip")
            suite.expectEqual(try BackupService.export(store: source, to: archive, appVersion: "0.1.0"), 3,
                              "every item is exported")
            let manifest = try BackupService.readManifest(from: archive)
            suite.expectEqual(manifest.itemCount, 3, "the manifest counts the items")
            suite.expectEqual(manifest.pinboards.map(\.name), ["服务器"], "the manifest lists the pinboards")

            let target = try scratch.store("target")
            let summary = try BackupService.importBackup(from: archive, into: target)
            suite.expectEqual(summary.inserted, 3, "every item is imported")
            suite.expectEqual(summary.skipped, 0, "nothing is skipped into an empty store")
            suite.expectEqual(summary.pinboardsCreated, 1, "the pinboard is created")

            let sourceItems = source.fetch(ClipQuery())
            let targetItems = target.fetch(ClipQuery())
            suite.expectEqual(targetItems.map(\.hash), sourceItems.map(\.hash), "the order survives")
            suite.expectEqual(targetItems.map(\.updatedAt), sourceItems.map(\.updatedAt), "the times survive")

            let importedText = try clipNoteUnwrap(targetItems.first { $0.type == .text }, "the imported text")
            suite.expectEqual(importedText.useCount, 1, "the use count survives")
            suite.expectEqual(importedText.sourceAppName, "终端", "the source app survives")
            suite.expectEqual(target.testPinboard(named: "服务器")?.id, importedText.pinboardID, "the pin survives")
            suite.expectEqual(target.fetch(ClipQuery(text: "部署")).count, 1, "imported text is indexed")

            let importedImage = try clipNoteUnwrap(targetItems.first { $0.type == .image }, "the imported image")
            suite.expect(importedImage.content != "Images/i.png", "an imported file is renamed to avoid collisions")
            suite.expectEqual(try Data(contentsOf: target.url(forRelativePath: importedImage.content)),
                              Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), "the image's bytes survive")
            suite.expectEqual(target.fetch(ClipQuery(text: "发票号码")).first?.id, importedImage.id,
                              "recognized image text survives")

            let richID = try clipNoteUnwrap(targetItems.first { $0.type == .rich }, "the imported rich text").id
            let importedRich = try clipNoteUnwrap(target.item(id: richID), "the imported rich item")
            let richPath = try clipNoteUnwrap(importedRich.dataPath, "the rich item's data")
            suite.expectEqual(try String(contentsOf: target.url(forRelativePath: richPath), encoding: .utf8),
                              "{\\rtf1 hello}", "rich text formatting survives")

            let again = try BackupService.importBackup(from: archive, into: target)
            suite.expectEqual(again.inserted, 0, "importing twice inserts nothing")
            suite.expectEqual(again.skipped, 3, "importing twice skips everything")
            suite.expectEqual(target.count(), 3, "importing twice leaves the count")
        }

        suite.clipNoteCase("backup merges by time") { scratch in
            let source = try scratch.store("source")
            try source.insert(NewClip(type: .text, content: "旧电脑上的内容", searchText: "旧电脑上的内容", hash: "a"),
                              date: Date(timeIntervalSinceNow: -86400))
            let archive = try scratch.file("archive.zip")
            try BackupService.export(store: source, to: archive)

            let target = try scratch.store("target")
            try target.insert(NewClip(type: .text, content: "新电脑上的内容", searchText: "新电脑上的内容", hash: "b"))
            _ = try BackupService.importBackup(from: archive, into: target)
            suite.expectEqual(target.fetch(ClipQuery()).map(\.content), ["新电脑上的内容", "旧电脑上的内容"],
                              "an imported item lands by its original time")
        }

        suite.clipNoteCase("backup of pinned items only") { scratch in
            let source = try scratch.store()
            let board = try clipNoteUnwrap(source.createPinboard(name: "AI", color: "#FF9F0A"), "the pinboard")
            let id = try source.insert(NewClip(type: .text, content: "pinned", searchText: "pinned", hash: "p"))
            try source.insert(NewClip(type: .text, content: "loose", searchText: "loose", hash: "l"))
            source.setPinboard(itemID: id, pinboardID: board.id)
            let archive = try scratch.file("archive.zip")
            suite.expectEqual(try BackupService.export(store: source, to: archive, onlyPinned: true), 1,
                              "only pinned items are exported")
        }

        suite.clipNoteCase("backup with a missing file") { scratch in
            let source = try scratch.store("source")
            try source.insert(NewClip(type: .image, content: "Images/gone.png", searchText: "", hash: "i:gone"))
            try source.insert(NewClip(type: .text, content: "ok", searchText: "ok", hash: "t"))
            let archive = try scratch.file("archive.zip")
            try BackupService.export(store: source, to: archive)
            let summary = try BackupService.importBackup(from: archive, into: try scratch.store("target"))
            suite.expectEqual(summary.inserted, 1, "the item with its file is imported")
            suite.expectEqual(summary.missingFiles, 1, "the missing file is reported")
        }

        suite.clipNoteCase("backup title") { scratch in
            let source = try scratch.store("source")
            let id = try source.insert(NewClip(type: .text, content: "x", searchText: "x", hash: "x"))
            source.setTitle(itemID: id, title: "备份里的标题")
            let archive = try scratch.file("archive.zip")
            try BackupService.export(store: source, to: archive)
            let target = try scratch.store("target")
            _ = try BackupService.importBackup(from: archive, into: target)
            suite.expectEqual(target.fetch(ClipQuery()).first?.title, "备份里的标题", "a title survives a backup")
        }

        suite.clipNoteCase("an invalid archive") { scratch in
            let store = try scratch.store()
            let bogus = try scratch.file("bogus.zip")
            try Data("not a zip".utf8).write(to: bogus)
            suite.expectThrows("importing a file that is not a backup fails") {
                _ = try BackupService.importBackup(from: bogus, into: store)
            }
        }
    }

    // MARK: Paste

    private static func plist(_ items: [[String: Data]]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: items.map { ["types": Array($0.keys), "dataByType": $0] },
                                           format: .binary, options: 0)
    }

    /// A library shaped like Paste's: one text item in a pinboard with a
    /// title, one LZFSE-compressed rich text item and one image kept as an
    /// external file.
    private static func makeFakePaste(in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".db_SUPPORT/_EXTERNAL_DATA"),
                                                withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: folder.appendingPathComponent("db.sqlite").path)
        try db.execute("""
            CREATE TABLE Z_METADATA (Z_VERSION INTEGER, Z_UUID VARCHAR, Z_PLIST BLOB);
            INSERT INTO Z_METADATA VALUES (1, 'FAKE-STORE-UUID', NULL);
            CREATE TABLE ZAPPLICATIONENTITY (Z_PK INTEGER PRIMARY KEY, ZBUNDLEIDENTIFIER VARCHAR, ZNAME VARCHAR);
            INSERT INTO ZAPPLICATIONENTITY VALUES (1, 'com.google.Chrome', 'Google Chrome');
            CREATE TABLE ZLISTENTITY (Z_PK INTEGER PRIMARY KEY, ZRAWTYPE INTEGER, ZNAME VARCHAR, ZRAWATTRIBUTES BLOB);
            CREATE TABLE ZITEMENTITY (Z_PK INTEGER PRIMARY KEY, ZRAWTYPE INTEGER, ZLIST INTEGER, ZSOURCEAPPLICATION INTEGER,
                                      ZCREATEDAT TIMESTAMP, ZTIMESTAMP TIMESTAMP, ZUPDATEDAT TIMESTAMP, ZTITLE VARCHAR);
            CREATE TABLE ZITEMDATAENTITY (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZRAWPASTEBOARDITEMS BLOB);
            """)
        try db.run("INSERT INTO ZLISTENTITY VALUES (1, 1, '剪贴板', ?)",
                   [.blob(Data(#"{"type":"clipboard","capacity":365}"#.utf8))])
        try db.run("INSERT INTO ZLISTENTITY VALUES (2, 2, 'AI', ?)",
                   [.blob(Data(#"{"type":"pinboard","colorCode":15750477}"#.utf8))])

        let text = try plist([["public.utf8-plain-text": Data("你好 Paste".utf8)]])
        let rich = try plist([["public.utf8-plain-text": Data("富文本内容".utf8), "public.rtf": Data("{\\rtf1 hi}".utf8)]])
        let compressed = try (rich as NSData).compressed(using: .lzfse) as Data
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        try plist([["public.png": png]]).write(to: folder.appendingPathComponent(".db_SUPPORT/_EXTERNAL_DATA/ABC-123"))

        let t0 = 800_000_000.0 // Core Data time, counted from 2001
        try db.run("INSERT INTO ZITEMENTITY VALUES (10, 5, 2, 1, ?, ?, ?, '我的标题')",
                   [.double(t0), .double(t0 + 100), .double(t0 + 50)])
        try db.run("INSERT INTO ZITEMENTITY VALUES (11, 5, 1, NULL, ?, ?, NULL, NULL)", [.double(t0 + 10), .double(t0 + 10)])
        try db.run("INSERT INTO ZITEMENTITY VALUES (12, 1, NULL, 1, ?, ?, NULL, '  ')", [.double(t0 + 20), .double(t0 + 30)])
        try db.run("INSERT INTO ZITEMDATAENTITY VALUES (1, 10, ?)", [.blob(Data([1]) + text)])
        try db.run("INSERT INTO ZITEMDATAENTITY VALUES (2, 11, ?)", [.blob(Data([1]) + compressed)])
        try db.run("INSERT INTO ZITEMDATAENTITY VALUES (3, 12, ?)", [.blob(Data([2]) + Data("ABC-123".utf8) + Data([0]))])
    }

    private static func pasteLibrary(_ suite: TestSuite) {
        suite.clipNoteCase("reading Paste") { scratch in
            let folder = scratch.folder("paste")
            try makeFakePaste(in: folder)
            let library = try PasteLibrary(directory: folder)
            let summary = try library.summary()
            suite.expectEqual(summary.storeID, "FAKE-STORE-UUID", "the store id is read")
            suite.expectEqual(summary.itemCount, 3, "the items are counted")
            suite.expectEqual(summary.pinboards.map(\.name), ["AI"], "only pinboards come over, not the history list")
            suite.expectEqual(summary.pinboards.first?.color, "#F0554D", "a pinboard's color code becomes hex")

            let records = try library.records(after: 0, limit: 10)
            suite.expectEqual(records.map(\.key), [10, 11, 12], "records come in key order")
            guard records.count == 3 else { return }
            suite.expectEqual(records[0].pinboard, "AI", "a record names its pinboard")
            suite.expectEqual(records[0].title, "我的标题", "a record carries its title")
            suite.expectEqual(records[0].sourceBundleID, "com.google.Chrome", "a record carries its source app")
            suite.expectEqual(records[0].createdAt, Date(timeIntervalSinceReferenceDate: 800_000_000),
                              "Core Data times convert")
            suite.expectEqual(records[0].lastUsedAt, Date(timeIntervalSinceReferenceDate: 800_000_100),
                              "the last use is the latest of the times")
            suite.expect(records[2].title == nil, "a blank title counts as none")

            suite.expectEqual(try library.decode(records[0].raw).first?["public.utf8-plain-text"],
                              Data("你好 Paste".utf8), "an inline plist decodes")
            suite.expectEqual(try library.decode(records[1].raw).first?["public.rtf"], Data("{\\rtf1 hi}".utf8),
                              "LZFSE-compressed data decodes")
            suite.expectEqual(try library.decode(records[2].raw).first?["public.png"]?.prefix(4),
                              Data([0x89, 0x50, 0x4E, 0x47]), "an external file is read")

            suite.expectEqual(try library.count(after: 10), 2, "counting resumes after a key")
            suite.expectEqual(try library.records(after: 10, limit: 1).map(\.key), [11], "reading resumes after a key")
        }

        suite.clipNoteCase("several data rows for one Paste item") { scratch in
            let folder = scratch.folder("paste")
            try makeFakePaste(in: folder)
            let db = try SQLiteDatabase(path: folder.appendingPathComponent("db.sqlite").path)
            let newer = try plist([["public.utf8-plain-text": Data("更新后的内容".utf8)]])
            try db.run("INSERT INTO ZITEMDATAENTITY VALUES (4, 10, ?)", [.blob(Data([1]) + newer)])
            let library = try PasteLibrary(directory: folder)
            suite.expectEqual(try library.summary().itemCount, 3, "an extra data row is not an extra item")
            var keys: [Int64] = []
            var cursor: Int64 = 0
            while true {
                let batch = try library.records(after: cursor, limit: 1)
                guard let last = batch.last else { break }
                keys += batch.map(\.key)
                cursor = last.key
            }
            suite.expectEqual(keys, [10, 11, 12], "paging neither skips nor repeats")
            let first = try clipNoteUnwrap(library.records(after: 0, limit: 1).first, "the first record")
            suite.expectEqual(try library.decode(first.raw).first?["public.utf8-plain-text"], Data("更新后的内容".utf8),
                              "the newest data row wins")
        }

        suite.clipNoteCase("reading Paste leaves it untouched") { scratch in
            let folder = scratch.folder("paste")
            try makeFakePaste(in: folder)
            let database = folder.appendingPathComponent("db.sqlite")
            let before = try Data(contentsOf: database)
            do {
                let library = try PasteLibrary(directory: folder)
                _ = try library.records(after: 0, limit: 10)
            }
            suite.expectEqual(try Data(contentsOf: database), before, "Paste's database is unchanged")
        }

        suite.clipNoteCase("no Paste library") { scratch in
            let missing = scratch.folder("nope")
            suite.expectThrows("a missing library fails to open") { _ = try PasteLibrary(directory: missing) }
        }
    }
}
