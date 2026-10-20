// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

/// The AI window: header (action, source, state), the custom instruction,
/// the streamed answer, then the actions.
struct ClipNoteAIResultView: View {
    @ObservedObject var model: ClipNoteAIResultModel
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var instructionFocused: Bool

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isCustom {
                instructionField
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .background(ClipNoteVisualEffect(material: .popover))
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.08)))
        .onChange(of: model.focusRequest) { _, _ in
            DispatchQueue.main.async { instructionFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.action?.systemImage ?? "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.action.map { String(format: strings.aiTitleFormat, $0.title(strings)) } ?? "AI")
                    .font(.headline)
                Text([model.item.map(strings.displayTitle(of:)), model.serviceLabel].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.phase == .running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(strings.aiGenerating).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { model.onClose?() } label: {
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

    private var instructionField: some View {
        HStack(spacing: 8) {
            TextField(strings.aiCustomPlaceholder, text: $model.customInstruction)
                .textFieldStyle(.roundedBorder)
                .focused($instructionFocused)
                .onSubmit { model.onRunCustom?() }
            Button(strings.aiRun) { model.onRunCustom?() }
                .disabled(model.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || model.phase == .running)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Answer

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = model.phase {
            failure(message)
        } else if model.output.isEmpty {
            placeholder
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Self.rendered(model.output))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        notes
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                // Follows the end while it streams.
                .onChange(of: model.output) { _, _ in
                    if model.phase == .running { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    /// Inline Markdown (bold, italic, code, links) with line breaks kept;
    /// copying and pasting use the raw text.
    private static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
    }

    @ViewBuilder
    private var notes: some View {
        if model.inputTruncated {
            Label(String(format: strings.aiInputTruncatedFormat, ClipNoteAIAction.maxInputCharacters),
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        if model.outputTruncated {
            Label(strings.aiOutputTruncated, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            if model.phase == .running {
                ProgressView()
                Text(strings.aiThinking).foregroundStyle(.secondary)
            } else if model.isCustom {
                Image(systemName: "text.bubble").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                Text(strings.aiCustomHint).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 520)
            HStack {
                Button(strings.retry) { model.onRegenerate?() }
                Button(strings.openAISettings) { model.onOpenSettings?() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private var footer: some View {
        HStack(spacing: 8) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else {
                Text(strings.aiDisclaimer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if model.phase == .running {
                Button(strings.stop) { model.onStop?() }
                    .help(strings.aiStopHelp)
            } else {
                Button(strings.regenerate) { model.onRegenerate?() }
                    .help("⌘R")
                    .disabled(model.item == nil || (model.isCustom && model.action?.instruction.isEmpty != false))
            }
            Button(strings.saveAsNewItem) { model.onSave?() }
                .help(strings.aiSaveHelp)
                .disabled(!model.canUseOutput)
            Button(strings.copy) { model.onCopy?() }
                .help("⇧⌘C")
                .disabled(!model.canUseOutput)
            Button(strings.paste) { model.onPaste?() }
                .buttonStyle(.borderedProminent)
                .help(strings.aiPasteHelp)
                .disabled(!model.canUseOutput)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .animation(.easeOut(duration: 0.15), value: model.toast)
    }
}
