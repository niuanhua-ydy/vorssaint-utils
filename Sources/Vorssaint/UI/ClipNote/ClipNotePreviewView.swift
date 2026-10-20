// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import Quartz
import SwiftUI

@MainActor
final class ClipNotePreviewModel: ObservableObject {
    @Published var item: ClipItem?
}

/// The larger preview Space or ⌘Y opens, for long text and big images.
struct ClipNotePreviewView: View {
    @ObservedObject var model: ClipNotePreviewModel
    @ObservedObject private var l10n = L10n.shared
    let store: ClipStore

    /// Very long text renders only its beginning; SwiftUI's Text stutters past this.
    static let maxPreviewCharacters = 60_000

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        ZStack {
            ClipNoteVisualEffect(material: .popover)
            if let item = model.item {
                VStack(alignment: .leading, spacing: 0) {
                    header(item)
                    Divider()
                    content(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .id(item.id)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .animation(.easeOut(duration: 0.15), value: model.item?.id)
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            if let icon = ClipNoteAppIcons.icon(for: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.displayTitle(of: item)).font(.headline)
                Text([item.sourceAppName, ClipNoteFormatters.absolute.string(from: item.updatedAt),
                      ClipNoteFormatters.meta(for: item, strings: strings)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(strings.previewCloseHint).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.type {
        case .text, .rich, .link:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(item.content.prefix(Self.maxPreviewCharacters)))
                        .font(.system(size: 13, design: looksLikeCode(item.content) ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item.content.count > Self.maxPreviewCharacters {
                        Text(String(format: strings.previewTruncatedFormat, Self.maxPreviewCharacters))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }

        case .image:
            ClipNoteThumbnailView(url: store.url(forRelativePath: item.content), maxPixel: 2400)
                .padding(16)

        case .file:
            if item.filePaths.count == 1, let path = item.filePaths.first {
                singleFile(path)
            } else {
                fileList(item.filePaths)
            }
        }
    }

    /// One file: the system's Quick Look preview (images, PDFs, video, text, documents).
    @ViewBuilder
    private func singleFile(_ path: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button(strings.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if FileManager.default.fileExists(atPath: path) {
                ClipNoteQuickLookPreview(url: URL(fileURLWithPath: path))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder").font(.system(size: 40, weight: .light))
                    Text(strings.previewFileMissing).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fileList(_ paths: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(paths, id: \.self) { path in
                    HStack(spacing: 10) {
                        ClipNoteFileThumbnailView(path: path, size: CGSize(width: 64, height: 64))
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .medium))
                            Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if let size = ClipNoteFormatters.fileSize(path) {
                            Text(size).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let sample = text.prefix(2000)
        let codeChars = sample.filter { "{}();=<>$|/\\".contains($0) }.count
        return sample.contains("\n") && Double(codeChars) / Double(max(sample.count, 1)) > 0.04
    }
}

/// The system Quick Look preview.
struct ClipNoteQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
