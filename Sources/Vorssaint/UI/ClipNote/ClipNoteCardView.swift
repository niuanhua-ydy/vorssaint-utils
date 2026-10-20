// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

/// A card after Paste's: a header band in the source app's color with its
/// icon enlarged at the top right, the content on white, details below.
struct ClipNoteCardView: View {
    // Paste's measurements: 232 × 232 cards, a 49 pt band, a 60 pt icon.
    static let size = CGSize(width: 232, height: 232)
    static let headerHeight: CGFloat = 49
    private static let corner: CGFloat = 14
    private static let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let isEditingTitle: Bool
    /// Holding ⌘ shows the number shortcut.
    let showsShortcut: Bool
    let now: Date
    let content: ClipNoteCardContent
    let terms: [String]
    let pinboard: Pinboard?
    let store: ClipStore
    let strings: ClipNoteStrings
    var onBeginEditTitle: () -> Void = {}
    var onCommitTitle: (String) -> Void = { _ in }

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            body(for: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(Self.shape)
        .background(
            Self.shape
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.2 : 0.12), radius: isHovered ? 8 : 5, y: 2)
        )
        // Selected: a thick accent border; hovered: a grey one. Drawn outside the card, over nothing.
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner + 3, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 4)
                .padding(-3)
        )
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isHovered { return Color.primary.opacity(0.22) }
        return .clear
    }

    private var headerColor: Color {
        ClipNoteAppColors.color(for: item.sourceBundleID) ?? item.type.tint
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            headerColor
            VStack(alignment: .leading, spacing: 1) {
                // A click on the title edits it, as in Paste.
                Group {
                    if isEditingTitle {
                        ClipNoteTitleEditor(initial: strings.displayTitle(of: item), onCommit: onCommitTitle)
                    } else {
                        Text(strings.displayTitle(of: item))
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onBeginEditTitle)
                            .help(strings.editTitleHelp)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: Self.size.width - 80, alignment: .leading)
                Text(ClipNoteFormatters.relativeTime(item.updatedAt, now: now, strings: strings))
                    .font(.system(size: 11))
                    .opacity(0.88)
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .frame(height: Self.headerHeight)
        .overlay(alignment: .topTrailing) {
            // The enlarged app icon, cut off at the band's edge.
            if let icon = ClipNoteAppIcons.icon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 60, height: 60)
                    .offset(x: 7, y: -6)
                    .help(item.sourceAppName ?? "")
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func body(for item: ClipItem) -> some View {
        switch item.type {
        case .text, .rich:
            Text(content.text ?? AttributedString(item.content))
                .font(.system(size: 12))
                .lineSpacing(2)
                .lineLimit(8)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 10)

        case .link:
            VStack(alignment: .leading, spacing: 8) {
                Text(URL(string: item.content)?.host ?? item.content)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(content.text ?? AttributedString(item.content))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

        case .image:
            ClipNoteThumbnailView(url: store.url(forRelativePath: item.content), maxPixel: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

        case .file:
            ClipNoteFileContent(paths: item.filePaths, terms: terms, strings: strings)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let pinboard {
                Circle().fill(Color(clipNoteHex: pinboard.color)).frame(width: 7, height: 7)
                    .help(pinboard.name)
            }
            Text(content.meta).lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .overlay(alignment: .trailing) {
            if showsShortcut && index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    .padding(.trailing, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: showsShortcut)
    }
}

/// The title edited in place: the caret starts at the end; Return or losing
/// focus saves (the panel turns Escape into cancel).
private struct ClipNoteTitleEditor: View {
    let initial: String
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .tint(.white)
            .focused($focused)
            .onSubmit { onCommit(text) }
            .onAppear {
                text = initial
                DispatchQueue.main.async {
                    focused = true
                    // Focusing selects everything; move the caret to the end instead.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApp.sendAction(#selector(NSResponder.moveToEndOfDocument(_:)), to: nil, from: nil)
                    }
                }
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused && !isFocused { onCommit(text) }
            }
    }
}

private struct ClipNoteFileContent: View {
    let paths: [String]
    let terms: [String]
    let strings: ClipNoteStrings

    var body: some View {
        if paths.count == 1, let path = paths.first {
            VStack(spacing: 8) {
                if FileManager.default.fileExists(atPath: path) {
                    // Images, PDFs and videos show their content; other files their icon.
                    ClipNoteFileThumbnailView(path: path, size: CGSize(width: 208, height: 100))
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else {
                    Image(nsImage: ClipNoteFileIcons.icon(for: path)).resizable().frame(width: 56, height: 56)
                        .opacity(0.5)
                    Text(strings.fileMissing).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(ClipNoteHighlighter.attributed((path as NSString).lastPathComponent, terms: terms))
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(paths.prefix(5), id: \.self) { path in
                    HStack(spacing: 7) {
                        Image(nsImage: ClipNoteFileIcons.icon(for: path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }
                if paths.count > 5 {
                    Text(String(format: strings.moreFilesFormat, paths.count - 5))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The search field as an NSTextField, so the panel can move focus to it directly.
struct ClipNoteSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onRegister: (NSTextField) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = placeholder
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        onRegister(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderString = placeholder
        // Never overwrite the field mid-composition; that breaks the input method.
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // While pinyin and the like are still composing, wait for the committed text.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            text.wrappedValue = field.stringValue
        }
    }
}
