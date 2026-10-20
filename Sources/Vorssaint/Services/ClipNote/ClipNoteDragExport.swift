// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore

/// What a card offers when dragged into another app (Finder, a browser's
/// upload area, a chat, an editor), and the image that follows the pointer.
@MainActor
enum ClipNoteDragExport {
    /// Images are copied here first, named after their title or time rather
    /// than the internal UUID file name.
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipNoteDrag", isDirectory: true)

    /// Nil when the item has nothing to drag (its file was deleted, say).
    static func writers(for item: ClipItem, store: ClipStore, strings: ClipNoteStrings) -> [NSPasteboardWriting]? {
        switch item.type {
        case .image:
            guard let url = exportImage(item, store: store, strings: strings) else { return nil }
            return [url as NSURL]

        case .file:
            let urls = item.filePaths.filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) as NSURL }
            return urls.isEmpty ? nil : urls

        case .link:
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.content, forType: .URL)
            pasteboardItem.setString(item.content, forType: .string)
            return [pasteboardItem]

        case .text, .rich:
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.content, forType: .string)
            if item.type == .rich, let path = item.dataPath, let type = item.dataType,
               let data = try? Data(contentsOf: store.url(forRelativePath: path)) {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return [pasteboardItem]
        }
    }

    private static func exportImage(_ item: ClipItem, store: ClipStore, strings: ClipNoteStrings) -> URL? {
        let source = store.url(forRelativePath: item.content)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        removeStaleExports()
        // A folder per drag, so equal names never collide. On APFS the copy is
        // a clone and takes no extra space.
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(fileName(for: item, strings: strings) + ".png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            NSLog("[ClipNote] drag export: \(error)")
            return source
        }
    }

    private static func fileName(for item: ClipItem, strings: ClipNoteStrings) -> String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let cleaned = title.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
            return String(String(cleaned).prefix(80))
        }
        return strings.typeName(.image) + " " + fileDateFormatter.string(from: item.createdAt)
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// A web upload may read the file after the drop, so copies stay a day.
    private static func removeStaleExports() {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? manager.removeItem(at: folder) }
        }
    }

    // MARK: - Drag image

    static func dragImage(for item: ClipItem, store: ClipStore, strings: ClipNoteStrings) -> NSImage {
        switch item.type {
        case .image:
            if let image = NSImage(contentsOf: store.url(forRelativePath: item.content)) {
                return scaled(image, maxSide: 180)
            }
        case .file:
            let paths = item.filePaths
            let icon = paths.count == 1
                ? NSWorkspace.shared.icon(forFile: paths[0])
                : NSWorkspace.shared.icon(for: .folder)
            return badged(scaled(icon, maxSide: 96), count: paths.count)
        case .text, .rich, .link:
            break
        }
        return textImage(item.type == .image ? strings.displayTitle(of: item) : item.content)
    }

    private static func scaled(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        return NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    /// Several files show their count at the icon's top right.
    private static func badged(_ icon: NSImage, count: Int) -> NSImage {
        guard count > 1 else { return icon }
        let size = NSSize(width: icon.size.width + 12, height: icon.size.height + 12)
        return NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: 0, width: icon.size.width, height: icon.size.height))
            let text = "\(count)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attributes)
            let badge = NSRect(x: size.width - max(22, textSize.width + 12), y: size.height - 22,
                               width: max(22, textSize.width + 12), height: 22)
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 11, yRadius: 11).fill()
            text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2),
                      withAttributes: attributes)
            return true
        }
    }

    /// Text: a small rounded card with its first lines.
    private static func textImage(_ text: String) -> NSImage {
        let size = NSSize(width: 200, height: 96)
        let snippet = String(text.prefix(300))
        return NSImage(size: size, flipped: false) { rect in
            let card = rect.insetBy(dx: 1, dy: 1)
            NSColor.textBackgroundColor.withAlphaComponent(0.95).setFill()
            let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            (snippet as NSString).draw(with: card.insetBy(dx: 10, dy: 8),
                                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: [.font: NSFont.systemFont(ofSize: 12),
                                                    .foregroundColor: NSColor.textColor,
                                                    .paragraphStyle: style])
            return true
        }
    }
}
