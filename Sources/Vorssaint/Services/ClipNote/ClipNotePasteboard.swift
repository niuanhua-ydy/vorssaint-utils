// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import ClipNoteCore

enum ClipNotePasteMode {
    case original
    case plainText
    /// Text that was cleaned up or produced by an AI action.
    case transformed(String)
}

/// Puts items back on the clipboard and pastes them into the app in front.
/// Writes go through the app's pasteboard lane like every other pasteboard
/// access, and tell the monitor on that same lane, so ClipNote never records
/// what it wrote itself.
enum ClipNotePasteboard {
    /// `completion` runs on the main thread once the item is on the clipboard.
    static func write(_ item: ClipItem, mode: ClipNotePasteMode, store: ClipStore, monitor: ClipNoteMonitor?,
                      completion: @escaping () -> Void = {}) {
        GeneralPasteboardAccess.shared.async({
            let pasteboard = NSPasteboard.general
            fill(pasteboard, with: item, mode: mode, store: store)
            monitor?.ignoreChanges(upTo: pasteboard.changeCount)
        }) { _ in completion() }
    }

    static func write(text: String, monitor: ClipNoteMonitor?, completion: @escaping () -> Void = {}) {
        GeneralPasteboardAccess.shared.async({
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            monitor?.ignoreChanges(upTo: pasteboard.changeCount)
        }) { _ in completion() }
    }

    private static func fill(_ pasteboard: NSPasteboard, with item: ClipItem, mode: ClipNotePasteMode,
                             store: ClipStore) {
        pasteboard.clearContents()
        if case .transformed(let text) = mode {
            pasteboard.setString(text, forType: .string)
            return
        }
        let plain = if case .plainText = mode { true } else { false }

        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)

        case .rich:
            if !plain, let path = item.dataPath, let type = item.dataType,
               let data = try? Data(contentsOf: store.url(forRelativePath: path)) {
                pasteboard.declareTypes([NSPasteboard.PasteboardType(type), .string], owner: nil)
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            pasteboard.setString(item.content, forType: .string)

        case .link:
            if !plain, let url = URL(string: item.content) {
                pasteboard.writeObjects([url as NSURL])
            }
            pasteboard.setString(item.content, forType: .string)

        case .image:
            let url = store.url(forRelativePath: item.content)
            if let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
                if let png = try? Data(contentsOf: url) { pasteboard.setData(png, forType: .png) }
            }

        case .file:
            if plain {
                pasteboard.setString(item.filePaths.joined(separator: "\n"), forType: .string)
            } else {
                pasteboard.writeObjects(item.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
            }
        }
    }

    /// The item as plain text, for cleaning, merging and previews.
    static func plainText(of item: ClipItem) -> String? {
        switch item.type {
        case .text, .rich, .link: return item.content
        case .file: return item.filePaths.joined(separator: "\n")
        case .image: return nil
        }
    }

    /// Presses ⌘V in the app in front, once the keys that summoned ClipNote
    /// are let go. Without Accessibility the system drops the keystroke, so
    /// it asks for the permission instead and leaves the item on the
    /// clipboard to paste by hand.
    static func pasteIntoFrontApp() {
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            return
        }
        AppUsageRecorder.note(.clipNotePaste)
        TransientPaste.shared.pasteCurrentContents(didFail: { NSSound.beep() })
    }
}

/// Built-in cleanups that paste a reworked copy of an item's text. The AI
/// actions are separate, in `ClipNoteAIAction`.
struct ClipNoteTextAction: Identifiable {
    let id: String
    let systemImage: String
    let isAvailable: (ClipItem) -> Bool
    /// The reworked text; nil when the item has none to work on.
    let transform: @MainActor (ClipItem, ClipStore) -> String?

    func title(_ strings: ClipNoteStrings) -> String {
        switch id {
        case "trim": return strings.cleanTrim
        case "collapse": return strings.cleanCollapseBlankLines
        case "join": return strings.cleanJoinLines
        default: return strings.cleanMarkdown
        }
    }

    static let textCleaning: [ClipNoteTextAction] = [
        ClipNoteTextAction(id: "trim", systemImage: "scissors",
                           isAvailable: { $0.type.isTextual },
                           transform: { item, _ in TextCleaner.trim(item.content) }),
        ClipNoteTextAction(id: "collapse", systemImage: "text.alignleft",
                           isAvailable: { $0.type.isTextual },
                           transform: { item, _ in TextCleaner.collapseBlankLines(item.content) }),
        ClipNoteTextAction(id: "join", systemImage: "arrow.right.to.line",
                           isAvailable: { $0.type.isTextual },
                           transform: { item, _ in TextCleaner.joinLines(item.content) }),
        ClipNoteTextAction(id: "markdown", systemImage: "number",
                           isAvailable: { $0.type == .rich || $0.type == .link },
                           transform: { item, store in ClipNoteMarkdown.markdown(for: item, store: store) }),
    ]
}

/// Rich text to Markdown, keeping bold, italic, inline code, links and lists.
@MainActor
enum ClipNoteMarkdown {
    static func markdown(for item: ClipItem, store: ClipStore) -> String? {
        if item.type == .link {
            return "[\(item.content)](\(item.content))"
        }
        guard let path = item.dataPath, let type = item.dataType,
              let data = try? Data(contentsOf: store.url(forRelativePath: path)) else { return item.content }
        let docType: NSAttributedString.DocumentType = type == NSPasteboard.PasteboardType.rtf.rawValue ? .rtf : .html
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
        if docType == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue }
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return item.content
        }
        return markdown(from: attributed)
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        var output = ""
        let full = NSRange(location: 0, length: attributed.length)
        let string = attributed.string as NSString
        attributed.enumerateAttributes(in: full) { attrs, range, _ in
            let text = string.substring(with: range)
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var prefix = "", suffix = ""
            if traits.contains(.monoSpace) {
                prefix = "`"; suffix = "`"
            } else {
                if traits.contains(.bold) { prefix += "**"; suffix = "**" + suffix }
                if traits.contains(.italic) { prefix += "*"; suffix = "*" + suffix }
            }
            var link: String?
            if let url = attrs[.link] as? URL { link = url.absoluteString } else if let s = attrs[.link] as? String { link = s }

            // Wrapped line by line, so no mark spans a line break.
            let lines = text.components(separatedBy: "\n").map { line -> String in
                let core = line.trimmingCharacters(in: .whitespaces)
                guard !core.isEmpty else { return line }
                var wrapped = prefix + core + suffix
                if let link { wrapped = "[\(wrapped)](\(link))" }
                let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                let trailing = String(line.reversed().prefix(while: { $0 == " " || $0 == "\t" }))
                return leading + wrapped + trailing
            }
            output += lines.joined(separator: "\n")
        }
        // Bullets of every kind become Markdown list items.
        let lines = output.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for bullet in ["•", "◦", "▪", "●", "‣", "–"] where trimmed.hasPrefix(bullet) {
                let rest = trimmed.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces)
                let indent = String(repeating: "  ", count: line.prefix(while: { $0 == "\t" }).count)
                return indent + "- " + rest
            }
            return line.replacingOccurrences(of: "\t", with: " ")
        }
        return TextCleaner.collapseBlankLines(lines.joined(separator: "\n"))
    }
}
