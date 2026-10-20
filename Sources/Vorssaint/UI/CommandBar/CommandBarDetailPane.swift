// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The column beside the list: the selected row, large, with what is worth
/// knowing about it before pressing Return. An app shows where it lives,
/// its version and when it was last opened; a row Tab steps into shows what
/// is in there; anything else shows its name in full and the alias and
/// shortcut it answers to.
struct CommandBarDetailPane: View {
    let entry: CommandBarEntry?

    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var loader = CommandBarDetailLoader.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: CommandBarDetailStrings { FeatureStrings.commandBarDetail(l10n.language) }

    /// The file a row stands for, when it stands for one. A running app's
    /// row is about that app too; a window's row is not, though it wears the
    /// app's icon.
    private var path: String? {
        guard let entry else { return nil }
        if let path = entry.revealPath { return path }
        if case .appIcon(let path) = entry.icon, !entry.id.hasPrefix("window.") { return path }
        return nil
    }

    private var details: CommandBarItemDetails? {
        guard let path, loader.details?.path == path else { return nil }
        return loader.details
    }

    var body: some View {
        VStack(spacing: 0) {
            if let entry {
                if let source = service.enteredCategory(for: entry),
                   case let rows = service.previewRows(in: source, limit: Self.previewLimit),
                   !rows.isEmpty {
                    preview(source, rows: rows)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            hero(entry)
                            info(entry)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                        .padding(.bottom, 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { loader.show(path: path) }
        .onChange(of: path) { _, path in loader.show(path: path) }
    }

    // MARK: - Hero

    private func hero(_ entry: CommandBarEntry) -> some View {
        VStack(spacing: 6) {
            artwork(entry)
                .padding(.bottom, 10)
            Text(entry.title)
                .font(.system(size: entry.isAnswer ? 20 : 15, weight: .semibold,
                              design: entry.isAnswer ? .rounded : .default))
                .multilineTextAlignment(.center)
                // A clipboard row's title is the copied text itself, so the
                // pane is where it can finally be read past the first line.
                .lineLimit(8)
                .textSelection(.enabled)
            if let caption = caption(entry) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if let value = entry.answerValue {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            if let trouble = troubleText(entry) {
                Text(trouble)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func artwork(_ entry: CommandBarEntry) -> some View {
        switch entry.icon {
        case .symbol(let name):
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(entry.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(entry.isActive ? Color.accentColor : Color.primary.opacity(0.85))
                )
        case .appIcon(let path), .filePath(let path):
            Image(nsImage: Self.largeIcon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
        case .clipboardImage(let name):
            ClipboardThumbnailImage(source: .stored(name: name), contentMode: .fit)
                .frame(maxWidth: 260, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .imageFile(let path):
            ClipboardThumbnailImage(source: .file(path: path), contentMode: .fit)
                .frame(maxWidth: 260, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .color(let color):
            ColorSwatch(color: color, size: 72)
        }
    }

    /// "Utilities · 133.9 MB" for an app, the kind and size for a file, and
    /// the row's own caption for everything else.
    private func caption(_ entry: CommandBarEntry) -> String? {
        if path != nil {
            let parts = [details?.kind, details?.size.map(Self.byteString)].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return entry.subtitle.isEmpty ? nil : entry.subtitle
    }

    private func troubleText(_ entry: CommandBarEntry) -> String? {
        let bar = FeatureStrings.commandBar(l10n.language)
        switch entry.trouble {
        case .needsSetup(let feature, _): return String(format: bar.needsSetupFormat, feature)
        case .needsPermission: return bar.needsPermissionHint
        case nil: return nil
        }
    }

    // MARK: - Facts

    private func info(_ entry: CommandBarEntry) -> some View {
        let rows = facts(entry)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Spacer(minLength: 0)
                    Text(row.value)
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, rows.isEmpty ? 0 : 22)
    }

    private func facts(_ entry: CommandBarEntry) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let path {
            rows.append((text.path, (path as NSString).abbreviatingWithTildeInPath))
        }
        if let details {
            if let version = details.version { rows.append((text.version, version)) }
            if !details.isApp, details.kind != nil, let size = details.size {
                // The caption already carries it for an app.
                rows.append((text.size, Self.byteString(size)))
            }
            if let created = details.created { rows.append((text.created, date(created))) }
            if let modified = details.modified { rows.append((text.modified, date(modified))) }
            if let opened = details.lastOpened { rows.append((text.lastOpened, date(opened))) }
        }
        if let alias = service.alias(for: entry) {
            rows.append((text.alias, alias))
        }
        if let shortcut = service.rowShortcut(for: entry)?.displayString
            ?? entry.shortcut?.displayString ?? entry.menuShortcut {
            rows.append((text.shortcut, shortcut))
        }
        return rows
    }

    // MARK: - Preview

    /// As many as the column holds without scrolling.
    private static let previewLimit = 12

    /// What stepping into the row will show, a glance ahead of the step.
    private func preview(_ source: CommandBarSource, rows: [CommandBarEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text(service.categoryTitle(source).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            ForEach(rows) { row in
                HStack(spacing: 9) {
                    smallIcon(row)
                        .frame(width: 22, height: 22)
                    Text(row.title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let detail = row.answerValue ?? (row.subtitle.isEmpty ? nil : row.subtitle) {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func smallIcon(_ entry: CommandBarEntry) -> some View {
        switch entry.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
        case .appIcon(let path), .filePath(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .clipboardImage(let name):
            ClipboardThumbnailImage(source: .stored(name: name), contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .imageFile(let path):
            ClipboardThumbnailImage(source: .file(path: path), contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .color(let color):
            ColorSwatch(color: color, size: 16)
        }
    }

    private func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .shortened,
                                        locale: l10n.language.formattingLocale()))
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// The selected row's icon at the pane's size. The list's cache keeps a
    /// small bitmap on purpose; this keeps one full icon, the one on screen.
    private static var lastIcon: (path: String, image: NSImage)?

    private static func largeIcon(forPath path: String) -> NSImage {
        if let lastIcon, lastIcon.path == path { return lastIcon.image }
        let image = NSWorkspace.shared.icon(forFile: path)
        lastIcon = (path, image)
        return image
    }
}
