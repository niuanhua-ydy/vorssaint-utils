// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

/// The Paste Stack window, after Paste's: close at the left, the title in the
/// middle, the order at the right; one line per row with dotted dividers. The
/// list is in paste order, the first row pasting next. ⌘ or ⇧ click picks
/// rows to merge; the context menu removes rows or clears the list.
struct ClipNoteStackView: View {
    @ObservedObject var model: ClipNoteStackModel
    @ObservedObject var preferences: ClipNotePreferences
    @ObservedObject private var l10n = L10n.shared
    let store: ClipStore

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.entries.isEmpty {
                emptyRow
            } else {
                list
            }
            if !model.selected.isEmpty {
                mergeBar
            }
            if !model.canAutoPaste {
                Text(strings.stackNeedsAccessibility)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: ClipNoteStackController.noteHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ClipNoteVisualEffect(material: .popover))
        .clipShape(Self.shape)
        .opacity(model.isPresented ? 1 : 0)
        .scaleEffect(model.isPresented ? 1 : 0.96)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(strings.stackTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .help(strings.stackHelp)
            HStack {
                Button { model.onClose?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.closeStack)
                Spacer()
                ClipNoteOrderButton(lifo: model.lifo, strings: strings) { model.onToggleOrder?() }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: ClipNoteStackController.headerHeight)
    }

    // MARK: - List

    private var list: some View {
        let visible = min(model.entries.count, ClipNoteStackController.maxVisibleRows)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.ordered.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { ClipNoteDashedSeparator() }
                    ClipNoteStackRow(entry: entry, isSelected: model.selected.contains(entry.id), store: store,
                                     strings: strings)
                        .onTapGesture { model.onTap?(entry) }
                        .contextMenu {
                            Button(strings.paste) { model.onPaste?(entry) }
                            Button(model.selected.contains(entry.id) ? strings.deselect : strings.selectWithCommand) {
                                model.onToggleSelection?(entry)
                            }
                            Button(strings.selectAll) { model.selected = Set(model.entries.map(\.id)) }
                            Divider()
                            Button(strings.removeFromList) { model.onRemove?(entry) }
                            Button(strings.clearList) { model.onClear?() }
                        }
                        .transition(.opacity)
                }
            }
        }
        .scrollIndicators(model.entries.count > ClipNoteStackController.maxVisibleRows ? .automatic : .never)
        .frame(height: CGFloat(visible) * ClipNoteStackController.rowHeight)
    }

    private var emptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(width: 22)
            Text(strings.stackEmpty)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: ClipNoteStackController.rowHeight)
    }

    // MARK: - Merge bar

    private var mergeBar: some View {
        HStack(spacing: 8) {
            Text(String(format: strings.selectedCountFormat, model.selected.count))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Picker(strings.separator, selection: $preferences.stackSeparator) {
                ForEach(ClipNoteStackSeparator.allCases) { Text($0.title(strings)).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(strings.separatorHelp)
            Button(strings.merge) { model.onMerge?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.selected.count < 2)
                .help(strings.mergeHelp)
            Button {
                model.selected = []
                model.selectionAnchor = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(strings.deselect)
        }
        .padding(.horizontal, 12)
        .frame(height: ClipNoteStackController.mergeBarHeight)
        .background(Color.primary.opacity(0.04))
    }
}

/// Two arrows, the darker one the current direction, as in Paste.
private struct ClipNoteOrderButton: View {
    let lifo: Bool
    let strings: ClipNoteStrings
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: -3) {
                Image(systemName: "arrow.up").foregroundStyle(lifo ? .tertiary : .primary)
                Image(systemName: "arrow.down").foregroundStyle(lifo ? .primary : .tertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lifo ? strings.orderLastFirstHelp : strings.orderFirstFirstHelp)
    }
}

private struct ClipNoteDashedSeparator: View {
    var body: some View {
        Line()
            .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

private struct ClipNoteStackRow: View {
    let entry: ClipNoteStackEntry
    let isSelected: Bool
    let store: ClipStore
    let strings: ClipNoteStrings
    @State private var isHovered = false

    private var item: ClipItem { entry.item }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22, height: 22)
            Text(summary)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: ClipNoteStackController.rowHeight - 1)
        .background(
            isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(isHovered ? 0.05 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(item.sourceAppName.map { String(format: strings.fromAppFormat, $0) } ?? "")
    }

    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .image:
            ClipNoteThumbnailView(url: store.url(forRelativePath: item.content), maxPixel: 80)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .file:
            Image(nsImage: ClipNoteFileIcons.icon(for: item.filePaths.first ?? "")).resizable()
        default:
            Image(systemName: item.type.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch item.type {
        case .image: return item.title ?? "\(strings.typeName(.image)) \(item.width) × \(item.height)"
        case .file:
            return item.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: strings.listSeparator)
        default:
            // One line: newlines fold into spaces.
            return item.content.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
