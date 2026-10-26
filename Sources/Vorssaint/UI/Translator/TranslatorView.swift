// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import Translation

/// The translation window's content: the text on top, its languages under
/// it, then one card per service, each copyable and readable aloud.
struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    @ObservedObject var service: TranslatorService
    @ObservedObject private var l10n = L10n.shared
    @State private var collapsed: Set<TranslatorEngine> = []
    @State private var copied: TranslatorEngine?

    private var text: TranslatorStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var resultsLimit: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) * 0.55 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            inputBox
            languageBar
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.visibleEngines.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.visibleEngines) { engine in
                            if let result = model.results[engine] { card(engine, result) }
                        }
                    }
                }
                // As tall as the cards, up to a limit, then scrolling.
                .frame(maxHeight: resultsLimit)
                .fixedSize(horizontal: false, vertical: true)
            }
            if model.aiMissing {
                Button { service.openSettings() } label: {
                    Label(text.aiMissing, systemImage: "sparkles").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Text(text.keysHint).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 460)
        .buttonStyle(.borderless)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .background {
            if #available(macOS 15, *), let request = model.appleRequest {
                TranslatorAppleTask(model: model, request: request).id(request.id)
            }
        }
        .onChange(of: model.request) { _, _ in copied = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(text.title, systemImage: "character.bubble").font(.headline)
            Spacer()
            Button { service.togglePin() } label: {
                Image(systemName: service.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(service.isPinned ? Color.accentColor : .secondary)
            }
            .help((service.isPinned ? text.unpin : text.pin) + " · ⌘P")
            Button { service.openSettings() } label: { Image(systemName: "gearshape") }
                .help(text.settings + " · ⌘,")
            Button { service.close() } label: { Image(systemName: "xmark") }
                .help(text.close + " · Esc")
        }
        .foregroundStyle(.secondary)
    }

    private var inputBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text.placeholder, text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...8)
                .accessibilityLabel(text.placeholder)
            HStack(spacing: 10) {
                if let detected = model.detected, model.source == .auto {
                    Text(String(format: text.detectedFormat, detected.title(in: locale)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.hasText {
                    Button { service.speak(model.input, language: model.effectiveSource) } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .help(text.speak)
                    Button { service.copy(model.input) } label: { Image(systemName: "doc.on.doc") }
                        .help(text.copy)
                    Button { model.input = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .help(text.close)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var languageBar: some View {
        HStack(spacing: 8) {
            Picker(text.auto, selection: $model.source) {
                ForEach(TranslatorLanguage.allCases, id: \.self) { language in
                    Text(language == .auto ? text.auto : language.title(in: locale)).tag(language)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Button { model.swap() } label: { Image(systemName: "arrow.left.arrow.right") }
                .help(text.swap + " · ⌘S")
                .disabled(model.effectiveSource == nil)
            Picker(text.swap, selection: $model.target) {
                ForEach(TranslatorLanguage.allCases, id: \.self) { language in
                    Text(language == .auto
                         ? String(format: text.autoTargetFormat, model.effectiveTarget.title(in: locale))
                         : language.title(in: locale)).tag(language)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private func card(_ engine: TranslatorEngine, _ result: TranslatorResult) -> some View {
        let isCollapsed = collapsed.contains(engine)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(title(engine), systemImage: symbol(engine))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if result.isRunning { ProgressView().controlSize(.mini) }
                Spacer()
                if result.isComplete {
                    if engine != .dictionary {
                        Button { service.speak(result.text, language: model.request?.target) } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .help(text.speak)
                    }
                    Button {
                        service.copy(result.text)
                        copied = engine
                    } label: {
                        Image(systemName: copied == engine ? "checkmark" : "doc.on.doc")
                    }
                    .help(copied == engine ? text.copied : text.copy)
                }
                Button {
                    if isCollapsed { collapsed.remove(engine) } else { collapsed.insert(engine) }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                }
            }
            .foregroundStyle(.secondary)
            if !isCollapsed {
                if result.isPending {
                    Text(text.pending).font(.callout).foregroundStyle(.secondary)
                } else if !result.text.isEmpty {
                    Text(result.text)
                        .font(.system(size: engine == .dictionary ? 13 : 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = result.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func title(_ engine: TranslatorEngine) -> String {
        switch engine {
        case .apple: return text.apple
        case .ai: return text.ai
        case .dictionary: return text.dictionary
        }
    }

    private func symbol(_ engine: TranslatorEngine) -> String {
        switch engine {
        case .apple: return "apple.logo"
        case .ai: return "sparkles"
        case .dictionary: return "book.closed"
        }
    }
}

/// Apple's session belongs to a visible view so macOS can ask permission to
/// download a missing language, rather than fail silently.
@available(macOS 15, *)
private struct TranslatorAppleTask: View {
    @ObservedObject var model: TranslatorModel
    let request: TranslatorRequest

    var body: some View {
        Color.clear
            .translationTask(source: request.source?.localeLanguage, target: request.target.localeLanguage) { session in
                let strings = TranslatorStrings.strings(L10n.shared.language)
                do {
                    if let source = request.source?.localeLanguage {
                        let status = await LanguageAvailability().status(from: source, to: request.target.localeLanguage)
                        try Task.checkCancellation()
                        guard status != .unsupported else {
                            await MainActor.run { model.finish(.apple, id: request.id, error: strings.unsupported) }
                            return
                        }
                    }
                    let response = try await session.translate(request.text)
                    try Task.checkCancellation()
                    await MainActor.run { model.finish(.apple, id: request.id, output: response.targetText) }
                } catch {
                    guard !Task.isCancelled else { return }
                    let detail = error as NSError
                    await MainActor.run {
                        model.finish(.apple, id: request.id, error: strings.failed + " (\(detail.domain): \(detail.code))")
                    }
                }
            }
    }
}
