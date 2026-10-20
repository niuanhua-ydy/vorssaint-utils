// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
@testable import ClipNoteCore

/// What the ClipNote core tests share. They came over from XCTest, so a case
/// is a throwing body: a thrown error or a missing value fails that case and
/// the run goes on. Async cases wait on a detached task, since the core's sync
/// engine is an actor and nothing in it needs the main thread.
struct ClipNoteTestFailure: Error, CustomStringConvertible {
    let description: String
}

extension TestSuite {
    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected, "\(label): got \(actual), expected \(expected)", file: file, line: line)
    }

    /// Whether the body throws, handing back the error to look at.
    @discardableResult
    func expectThrows(_ label: String, file: StaticString = #filePath, line: UInt = #line,
                      _ body: () throws -> Void) -> Error? {
        do {
            try body()
            expect(false, "\(label): did not throw", file: file, line: line)
            return nil
        } catch {
            expect(true, label)
            return error
        }
    }

    func clipNoteCase(_ name: String, file: StaticString = #filePath, line: UInt = #line,
                      _ body: (ClipNoteScratch) throws -> Void) {
        let scratch = ClipNoteScratch()
        defer { scratch.removeAll() }
        do {
            try body(scratch)
        } catch {
            expect(false, "\(name) threw \(error)", file: file, line: line)
        }
    }

    func clipNoteAsyncCase(_ name: String, file: StaticString = #filePath, line: UInt = #line,
                           _ body: @escaping (ClipNoteScratch) async throws -> Void) {
        let scratch = ClipNoteScratch()
        defer { scratch.removeAll() }
        let outcome = ClipNoteAsyncOutcome()
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await body(scratch)
            } catch {
                outcome.error = error
            }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 60) == .success else {
            expect(false, "\(name) did not finish within 60 s", file: file, line: line)
            return
        }
        if let error = outcome.error {
            expect(false, "\(name) threw \(error)", file: file, line: line)
        }
    }
}

private final class ClipNoteAsyncOutcome: @unchecked Sendable {
    var error: Error?
}

/// Throwaway folders for one case, removed when it ends.
final class ClipNoteScratch: @unchecked Sendable {
    private let lock = NSLock()
    private var folders: [URL] = []

    func folder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipNoteTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        lock.withLock { folders.append(url) }
        return url
    }

    /// A path for one file, inside a folder of its own that already exists.
    func file(_ name: String) throws -> URL {
        let parent = folder((name as NSString).deletingPathExtension)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent.appendingPathComponent(name)
    }

    func store(_ name: String = "store") throws -> ClipStore {
        try ClipStore(directory: folder(name), postsNotifications: false)
    }

    func removeAll() {
        lock.withLock { folders }.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

func clipNoteUnwrap<T>(_ value: T?, _ label: String) throws -> T {
    guard let value else { throw ClipNoteTestFailure(description: "\(label) is missing") }
    return value
}

extension ClipStore {
    @discardableResult
    func addTestText(_ text: String, date: Date = Date(), app: String? = nil) throws -> Int64 {
        try insert(NewClip(type: .text, content: text, searchText: text, sourceBundleID: app,
                           sourceAppName: app, charCount: text.count, hash: ContentHash.forText(text)), date: date)
    }

    func testPinboard(named name: String) -> Pinboard? { pinboards().first { $0.name == name } }
}
