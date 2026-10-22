// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarLauncherTests {
    static func run(_ suite: TestSuite) {
        let ids = ["settings.screen", "menu.screen", "app.screen", "action.screen",
                   "port.browse", "file.screen", "toggle.screen", "window.screen"]
        let candidates = ids.enumerated().map { index, _ in
            CommandBarCandidate(index: index, title: index < 2 ? "screen" : "screen tools",
                                priority: index == 1 ? 1000 : 0)
        }
        let ranked = CommandBarSearch.rankedIndexes(candidates: candidates, matching: "screen")
        suite.expect(ranked.prefix(2) == [1, 0], "the fixture starts with a learned menu and an exact settings match")
        let ordered = CommandBarSearch.launcherOrdered(ranked, id: { ids[$0] })
        suite.expect(ordered == [2, 3, 4, 6, 1, 0, 5, 7],
                     "apps and quick actions lead even exact or learned discovery matches, with stable order inside each group")
        suite.expect(CommandBarSearch.launcherOrdered([6, 3, 2, 4], id: { ids[$0] }) == [6, 3, 2, 4],
                     "relevance and learned choices among launcher rows keep their order")
        suite.expect(CommandBarSearch.launcherOrdered([], id: { ids[$0] }).isEmpty,
                     "an empty match list stays empty")
        let noMatch = CommandBarSearch.rankedIndexes(candidates: candidates, matching: "zzzzzz")
        suite.expect(CommandBarSearch.launcherOrdered(noMatch, id: { ids[$0] }).isEmpty,
                     "launcher preference does not introduce unmatched apps or actions")
        let manyIDs = (0..<20).map { "file.\($0)" } + ["app.target", "action.target"]
        let capped = CommandBarSearch.launcherOrdered(Array(manyIDs.indices), id: { manyIDs[$0] }).prefix(12)
        suite.expect(Array(capped.prefix(2)) == [20, 21],
                     "launcher rows move ahead before the result limit is applied")

        func code(_ name: String) -> String {
            ((try? String(contentsOfFile: "Sources/Vorssaint/Services/CommandBar/\(name).swift",
                          encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        let service = code("CommandBarService")
        let search = service.components(separatedBy: "private func searchRows(for trimmed: String)").last ?? ""
        let ordinary = search.components(separatedBy: "let answer = isEnabled(.calculator)").last?
            .components(separatedBy: "// MARK:").first ?? ""
        suite.expect(!ordinary.contains("CommandBarCatalog.clipboardEntries(")
                     && !ordinary.contains("CommandBarCatalog.clipNoteEntries("),
                     "ordinary search never queries either clipboard backend")
        let browse = service.components(separatedBy: "private func suggestionRows(").last?
            .components(separatedBy: "private func browseGroup(").first ?? ""
        suite.expect(!browse.isEmpty && !browse.contains("clipboardBrowseEntries(")
                     && !browse.contains("clipNoteBrowseEntries("),
                     "the home browse list does not expose clipboard contents")
        suite.expect(search.contains("category == .clipboard")
                     && search.contains("CommandBarCatalog.clipboardEntries(matching: trimmed, bar: bar, limit: 40)")
                     && search.contains("CommandBarCatalog.clipNoteEntries(matching: trimmed, bar: bar, limit: 40)")
                     && search.contains("CommandBarSearch.launcherOrdered("),
                     "category search retains both history backends and ordinary search uses launcher ordering")

        for query in ["clipboard", "history", "粘贴板", "粘贴板历史", "剪贴板历史"] {
            suite.expect(CommandBarSearch.matches(
                title: FeatureStrings.commandBar(.zhHans).sourceClipboard,
                keywords: "clipboard history 粘贴板历史", query: query),
                "the history entrance answers to \(query)")
        }
        let clipNote = code("CommandBarClipNote")
        let entry = clipNote.components(separatedBy: "id: \"action.clipNote\"").last?
            .components(separatedBy: "id: \"action.clipNoteStack\"").first ?? ""
        suite.expect(entry.contains(".sourceClipboard") && entry.contains("keepsBarOpen: true")
                     && entry.contains("service.query = \"\"") && entry.contains("service.setCategory(.clipboard)"),
                     "Return on ClipNote history clears the field and enters clipboard search without closing the bar")
        let catalog = code("CommandBarCatalog")
        let legacy = catalog.components(separatedBy: "if !AppFeature.clipNote.isAvailable {").last?
            .components(separatedBy: "let recentIDs =").first ?? ""
        suite.expect(legacy.contains("id: \"action.clipboardWindow\"")
                     && legacy.contains("title: bar.sourceClipboard") && legacy.contains("keepsBarOpen: true")
                     && legacy.contains("service.query = \"\"") && legacy.contains("service.setCategory(.clipboard)"),
                     "legacy builds have the same history entrance, without duplicating it when ClipNote is available")
    }
}
