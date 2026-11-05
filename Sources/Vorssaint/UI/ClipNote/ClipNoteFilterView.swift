// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import SwiftUI

/// The filter popover above the search field, like Paste's: the types, the
/// apps items were copied from, and the pinboards, each a grid of chips. A
/// choice is shown as a token in the search field and closes the popover.
struct ClipNoteFilterPopover: View {
    @ObservedObject var model: ClipNotePanelModel
    @ObservedObject private var l10n = L10n.shared

    static let width: CGFloat = 400
    static let arrowSize = CGSize(width: 18, height: 9)
    private static let columns = 3
    private static let chipHeight: CGFloat = 30
    private static let spacing: CGFloat = 8
    /// The apps shown before "More"; the ninth slot holds "More" itself.
    private static let collapsedApps = 8
    /// Rows of apps shown at once when every app is listed; more scroll.
    private static let expandedRows = 6

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(strings.typeFilter) {
                grid(ClipNoteTypeFilter.allCases.map { filter in
                    AnyView(ClipNoteFilterChip(title: strings.typeName(filter.displayType),
                                               isSelected: model.typeFilter == filter) {
                        Image(systemName: filter.displayType.systemImage)
                    } action: { model.toggle(filter) })
                })
            }
            if !model.sourceApps.isEmpty {
                section(strings.sourceAppFilter) { apps }
            }
            if !model.pinboards.isEmpty {
                section(strings.pinboardsFilter) {
                    grid(model.pinboards.map { board in
                        AnyView(ClipNoteFilterChip(title: board.name, isSelected: model.tab == .pinboard(board.id)) {
                            Circle().fill(Color(clipNoteHex: board.color)).frame(width: 12, height: 12)
                        } action: { model.togglePinboard(board) })
                    })
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: Self.width, alignment: .leading)
        // The arrow hangs below the content, toward the filter button.
        .padding(.bottom, Self.arrowSize.height)
        .background(ClipNotePopoverBackground(arrowX: model.filterArrowX, arrowSize: Self.arrowSize))
    }

    @ViewBuilder
    private var apps: some View {
        let all = model.sourceApps
        let fits = all.count <= Self.collapsedApps + 1
        if fits || !model.showsAllApps {
            let shown = fits ? all : Array(all.prefix(Self.collapsedApps))
            grid(shown.map(appChip) + (fits ? [] : [moreChip(expand: true)]))
        } else {
            let chips = all.map(appChip) + [moreChip(expand: false)]
            let rows = (chips.count + Self.columns - 1) / Self.columns
            let visibleRows = min(rows, Self.expandedRows)
            ScrollView(.vertical, showsIndicators: rows > Self.expandedRows) {
                grid(chips)
            }
            .frame(height: CGFloat(visibleRows) * (Self.chipHeight + Self.spacing) - Self.spacing)
        }
    }

    private func appChip(_ app: SourceApp) -> AnyView {
        AnyView(ClipNoteFilterChip(title: app.name, isSelected: model.appFilter == app.bundleID) {
            ClipNoteAppIcon(bundleID: app.bundleID, size: 18)
        } action: { model.toggleApp(app.bundleID) })
    }

    private func moreChip(expand: Bool) -> AnyView {
        AnyView(ClipNoteFilterChip(title: expand ? strings.moreApps : strings.fewerApps, isSelected: false) {
            Image(systemName: expand ? "chevron.down.circle" : "chevron.up.circle")
        } action: { model.showsAllApps = expand })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content()
        }
    }

    /// Rows of three equal chips; plain stacks rather than a lazy grid, so
    /// the popover's fitting size is exact.
    private func grid(_ chips: [AnyView]) -> some View {
        let rows = stride(from: 0, to: chips.count, by: Self.columns).map { start in
            Array(chips[start..<min(start + Self.columns, chips.count)])
        }
        return VStack(spacing: Self.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        if column < rows[row].count {
                            rows[row][column]
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: Self.chipHeight)
                        }
                    }
                }
                .frame(height: Self.chipHeight)
            }
        }
    }
}

private struct ClipNoteFilterChip<Icon: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                icon()
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .background(Capsule().fill(fill))
            .overlay {
                if isSelected { Capsule().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.2) }
        return Color.primary.opacity(isHovered ? 0.11 : 0.06)
    }
}

/// A rounded rectangle with an arrow under it, pointing down at the filter button.
struct ClipNotePopoverBubble: Shape {
    var arrowX: CGFloat
    var arrowSize: CGSize
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - arrowSize.height)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let inset = cornerRadius + arrowSize.width / 2
        let x = min(max(rect.minX + arrowX, rect.minX + inset), rect.maxX - inset)
        path.move(to: CGPoint(x: x - arrowSize.width / 2, y: body.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + arrowSize.width / 2, y: body.maxY))
        path.closeSubpath()
        return path
    }
}

/// The popover's glass (or blur before macOS 26) in the bubble's shape, with a hairline edge.
private struct ClipNotePopoverBackground: View {
    let arrowX: CGFloat
    let arrowSize: CGSize

    var body: some View {
        let shape = ClipNotePopoverBubble(arrowX: arrowX, arrowSize: arrowSize)
        Group {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                ClipNoteVisualEffect(material: .popover).clipShape(shape)
            }
        }
        .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// An active filter inside the search field, removed by its ×.
struct ClipNoteFilterToken<Icon: View>: View {
    let title: String
    let removeHelp: String
    @ViewBuilder let icon: () -> Icon
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            icon().font(.system(size: 11, weight: .medium)).frame(width: 14, height: 14)
            Text(title).lineLimit(1).truncationMode(.tail).frame(maxWidth: 110)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(removeHelp)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(height: 22)
        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
        .fixedSize()
    }
}

/// An app's icon by bundle ID, looked up once; a generic app symbol when it is gone.
struct ClipNoteAppIcon: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        if let image = ClipNoteAppIcons.icon(for: bundleID) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "app").frame(width: size, height: size)
        }
    }
}
