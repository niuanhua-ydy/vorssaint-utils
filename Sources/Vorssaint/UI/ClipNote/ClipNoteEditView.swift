// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

/// The editor window: header (item, length), the text, then Cancel and Save.
struct ClipNoteEditView: View {
    @ObservedObject var model: ClipNoteEditModel
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var textFocused: Bool

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextEditor(text: $model.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($textFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .background(ClipNoteVisualEffect(material: .popover))
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.08)))
        .onChange(of: model.focusRequest) { _, _ in
            DispatchQueue.main.async { textFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.editTitle)
                    .font(.headline)
                Text([model.item.map(strings.displayTitle(of:)), String(format: strings.charactersFormat, model.text.count)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { model.onCancel?() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.closeEscapeHelp)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.item?.type == .rich {
                Label(strings.editRichNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(strings.cancel) { model.onCancel?() }
                .help(strings.closeEscapeHelp)
            Button(strings.save) { model.onSave?() }
                .buttonStyle(.borderedProminent)
                .help(strings.editSaveHelp)
                .disabled(!model.hasChanges || !model.canSave)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}
