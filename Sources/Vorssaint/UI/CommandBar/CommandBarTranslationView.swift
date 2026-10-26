// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import Translation

struct CommandBarTranslationView: View {
    @ObservedObject var model: CommandBarTranslationModel
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var inputFocused: Bool
    @State private var copied = false

    private var text: CommandBarTranslationStrings { .strings(l10n.language) }
    private var common: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { CommandBarService.shared.stepBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .help(FeatureStrings.commandBar(l10n.language).pageTitle + " · Esc")
                Label(text.title, systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Picker(text.title, selection: $model.engine) {
                    Text(text.system).tag(CommandBarTranslationEngine.system)
                    Text("AI").tag(CommandBarTranslationEngine.ai)
                }
                .labelsHidden()
                .fixedSize()
                Button { CommandBarService.shared.openTranslationSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .help(common.settingsEllipsis)
            }
            HStack {
                languagePicker(text.source, selection: $model.source, includesAuto: true)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                languagePicker(text.target, selection: $model.target, includesAuto: false)
            }
            TextEditor(text: $model.input)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .focused($inputFocused)
                .accessibilityLabel(text.source)
            HStack {
                Text("\(model.input.count) / \(CommandBarTranslationModel.maxCharacters)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Button(common.stop) { model.invalidate() }
                } else {
                    Button(text.title + " ↩") { model.start() }
                        .disabled(!model.canTranslate)
                }
            }
            HStack {
                Text(text.result).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? common.copied : common.copy) {
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.declareVorssaintSource()
                    copied = board.setString(model.output, forType: .string)
                }
                .disabled(!model.canCopy)
            }
            ScrollView {
                Text(model.output.isEmpty ? " " : model.output)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 120)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(text.privacy).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("↩ \(text.title) · ⇧↩ ↵ · Esc")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .buttonStyle(.borderless)
        .background {
            if #available(macOS 15, *), model.engine == .system, let request = model.request {
                CommandBarSystemTranslationTask(model: model, request: request)
                    .id(request.id)
            }
        }
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
        .onChange(of: model.output) { _, _ in copied = false }
        .onChange(of: model.error) { _, _ in CommandBarService.shared.refreshPanelLayout() }
    }

    private func languagePicker(_ title: String, selection: Binding<CommandBarTranslationLanguage>, includesAuto: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(CommandBarTranslationLanguage.allCases.filter { includesAuto || $0 != .auto }, id: \.self) { language in
                Text(language == .auto ? text.auto : language.title(in: l10n.language.formattingLocale())).tag(language)
            }
        }
        .labelsHidden()
        .accessibilityLabel(title)
        .frame(maxWidth: .infinity)
    }
}

@available(macOS 15, *)
private struct CommandBarSystemTranslationTask: View {
    @ObservedObject var model: CommandBarTranslationModel
    let request: CommandBarTranslationRequest

    var body: some View {
        Color.clear
            .translationTask(source: request.source.localeLanguage, target: request.target.localeLanguage) { session in
                let strings = CommandBarTranslationStrings.strings(L10n.shared.language)
                do {
                    if let source = request.source.localeLanguage {
                        let status = await LanguageAvailability().status(from: source, to: request.target.localeLanguage)
                        try Task.checkCancellation()
                        guard status != .unsupported else {
                            await MainActor.run { model.finish(id: request.id, error: strings.unsupported) }
                            return
                        }
                    }
                    // Do not preflight auto-detection with status(for:): short
                    // text can throw before the session offers its language picker.
                    // This session belongs to a visible view so macOS can ask
                    // permission to download missing languages, rather than fail silently.
                    let response = try await session.translate(request.text)
                    try Task.checkCancellation()
                    await MainActor.run { model.finish(id: request.id, output: response.targetText) }
                } catch {
                    guard !Task.isCancelled else { return }
                    let detail = error as NSError
                    await MainActor.run {
                        model.finish(id: request.id, error: strings.failed + " (\(detail.domain): \(detail.code))")
                    }
                }
            }
    }
}
