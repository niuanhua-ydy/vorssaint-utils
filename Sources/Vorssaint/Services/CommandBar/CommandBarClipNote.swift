// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore

/// The Command Bar's clipboard rows, read from ClipNote. Kept beside the
/// upstream history rows rather than in place of them: those go quiet on
/// their own while that feature is left out of this build, so the catalog
/// keeps merging cleanly.
extension CommandBarCatalog {
    /// Items matching the query, capped so pasted text never crowds out the
    /// bar's actions. Never on an empty query, never counted as usage.
    static func clipNoteEntries(matching query: String,
                                bar: CommandBarFeatureStrings,
                                limit: Int = 4,
                                paste: @escaping (Int64) -> Void) -> [CommandBarEntry] {
        guard AppFeature.clipNote.isAvailable, !query.isEmpty else { return [] }
        return ClipNoteService.shared.search(query, limit: limit)
            .map { clipNoteRow($0, query: query, bar: bar, paste: paste) }
    }

    /// The latest items, for the browse list and the Clipboard category.
    static func clipNoteBrowseEntries(limit: Int,
                                      bar: CommandBarFeatureStrings,
                                      paste: @escaping (Int64) -> Void) -> [CommandBarEntry] {
        guard AppFeature.clipNote.isAvailable else { return [] }
        return ClipNoteService.shared.recent(limit: limit)
            .map { clipNoteRow($0, query: nil, bar: bar, paste: paste) }
    }

    /// Browsing clipboard history and opening Paste Stack among the bar's actions.
    static func clipNoteActionEntries(subtitle: String,
                                      panelShortcut: GlobalShortcut?,
                                      stackShortcut: GlobalShortcut?) -> [CommandBarEntry] {
        guard AppFeature.clipNote.isAvailable else { return [] }
        let strings = FeatureStrings.clipNote(L10n.shared.language)
        let running = ClipNoteService.shared.isRunning
        let trouble: CommandBarEntry.Trouble? = running ? nil
            : .needsSetup(featureTitle: strings.title, page: .clipNote)
        return [
            CommandBarEntry(
                id: "action.clipNote",
                title: FeatureStrings.commandBar(L10n.shared.language).sourceClipboard,
                subtitle: subtitle,
                keywords: ["ClipNote", "clipboard", "history", "pinboard", "粘贴板历史",
                           strings.title, ClipNoteStrings.enUS.title]
                    .joined(separator: " "),
                icon: .symbol("list.clipboard"),
                shortcut: panelShortcut,
                keepsBarOpen: true,
                run: { _ in
                    let service = CommandBarService.shared
                    service.query = ""
                    service.setCategory(.clipboard)
                }),
            CommandBarEntry(
                id: "action.clipNoteStack",
                title: strings.stackTitle,
                subtitle: subtitle,
                keywords: ["ClipNote", "stack", "sequential paste", strings.title].joined(separator: " "),
                icon: .symbol("square.stack.3d.up"),
                shortcut: stackShortcut,
                isActive: running && ClipNoteService.shared.isStackVisible,
                trouble: trouble,
                run: { _ in afterClipNoteBeat { ClipNoteService.shared.toggleStack() } }),
        ]
    }

    private static func clipNoteRow(_ item: ClipItem,
                                    query: String?,
                                    bar: CommandBarFeatureStrings,
                                    paste: @escaping (Int64) -> Void) -> CommandBarEntry {
        let strings = FeatureStrings.clipNote(L10n.shared.language)
        let icon: CommandBarEntry.Icon
        let title: String
        switch item.type {
        case .image:
            icon = ClipNoteService.shared.imageURL(of: item).map { .imageFile(path: $0.path) } ?? .symbol("photo")
            title = item.title ?? "\(strings.typeName(.image)) \(item.width) × \(item.height)"
        case .file:
            icon = item.filePaths.first.map { .filePath($0) } ?? .symbol("folder")
            title = item.title
                ?? item.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: strings.listSeparator)
        case .text, .rich, .link:
            icon = .symbol(item.type.systemImage)
            title = item.title ?? oneLine(item.content)
        }
        let subtitle = [bar.kindClipboard, item.sourceAppName].compactMap { $0 }.joined(separator: " · ")
        // ClipNote's own index decided this item matches (Chinese word pairs,
        // text read out of an image, a hit deep in a long text), which the
        // bar's matcher cannot see from the title alone; the query and the
        // text around the hit ride along as keywords so the ranking keeps it.
        let keywords = [query, item.type == .image ? item.searchText : item.content]
            .compactMap { $0 }.joined(separator: " ")
        return CommandBarEntry(
            id: "clipboard.clipnote.\(item.id)",
            title: title,
            subtitle: subtitle,
            keywords: String(keywords.prefix(600)),
            icon: icon,
            trouble: Permissions.shared.accessibility ? nil : .needsPermission,
            countsUsage: false,
            run: { _ in paste(item.id) })
    }

    /// The text on one line, as far as a row shows it.
    private static func oneLine(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(160))
    }

    /// The same pause the catalog's own actions give the panel to leave the screen.
    private static func afterClipNoteBeat(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
