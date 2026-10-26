// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Detached tool pages (⌘D in the bar), for a long piece of text that needs
/// more room or has to stay beside something else. Each one is independent.
final class CommandBarDeveloperToolsWindows: NSObject, NSWindowDelegate {
    static let shared = CommandBarDeveloperToolsWindows()
    private var windows: [NSWindow] = []

    func show(toolID: String, operationID: String, input: String) {
        let model = CommandBarDeveloperToolModel()
        model.open(toolID: toolID, operationID: operationID, input: input)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = model.tool.name
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: CommandBarDeveloperToolView(model: model, detached: true))
        window.minSize = NSSize(width: 560, height: 460)
        windows.append(window)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}

/// One tool page: input above, the result below, following every keystroke.
/// Inside the bar the bar's own key monitor owns ⌘↩, ⌥1…9, ⌘D and Esc; a
/// detached window answers to the same keys through its buttons.
struct CommandBarDeveloperToolView: View {
    @ObservedObject var model: CommandBarDeveloperToolModel
    var detached = false
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var inputFocused: Bool
    @State private var copied = false

    /// SwiftUI text slows to a crawl on megabytes; the copy is always whole.
    private static let displayLimit = 200_000

    private var chinese: Bool { l10n.language.rawValue.hasPrefix("zh") }
    private func label(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.input)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .accessibilityLabel(label("Input", "输入"))
                if model.input.isEmpty {
                    Text(label("Paste or type here", "粘贴或输入内容"))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .frame(height: detached ? nil : 130)
            .frame(maxHeight: detached ? .infinity : nil)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else {
                    Text(label("Result", "结果")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(copied ? label("Copied", "已复制") : label("Copy ⌘↩", "复制 ⌘↩"), action: copy)
                    .keyboardShortcut(detached ? KeyboardShortcut(.return, modifiers: .command) : nil)
                    .disabled(!model.canCopy)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(displayedOutput)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: detached ? nil : 210)
            .frame(maxHeight: detached ? .infinity : nil)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text(hints).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .buttonStyle(.borderless)
        .background {
            // The bar reads ⌥1…9 itself; a window needs the keys on something.
            if detached {
                ForEach(Array(model.tool.operations.prefix(9).enumerated()), id: \.element.id) { index, _ in
                    Button("") { model.selectOperation(at: index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
        }
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
        .onChange(of: model.output) { _, _ in copied = false }
        .onChange(of: model.error) { _, _ in if !detached { CommandBarService.shared.refreshPanelLayout() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !detached {
                Button { CommandBarService.shared.stepBack() } label: { Image(systemName: "chevron.left") }
                    .help(FeatureStrings.commandBar(l10n.language).pageTitle + " · Esc")
            }
            Picker(label("Tool", "工具"), selection: $model.toolID) {
                ForEach(CommandBarDeveloperTools.all) { tool in
                    Label(chinese ? tool.chineseName : tool.name, systemImage: tool.symbol).tag(tool.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            if model.tool.operations.count > 1 {
                Picker(label("Operation", "操作"), selection: $model.operationID) {
                    ForEach(model.tool.operations) { operation in
                        Text(chinese ? operation.chineseName : operation.name).tag(operation.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if !detached {
                Button { CommandBarService.shared.detachDeveloperTool() } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .help(label("Open in a window · ⌘D", "在窗口中打开 · ⌘D"))
            }
        }
    }

    private var displayedOutput: String {
        if model.output.isEmpty { return " " }
        guard model.output.count > Self.displayLimit else { return model.output }
        return String(model.output.prefix(Self.displayLimit)) + "\n…"
    }

    private var hints: String {
        let count = model.tool.operations.count
        var parts = [detached ? label("⌘↩ Copy", "⌘↩ 复制") : label("⌘↩ Copy and close", "⌘↩ 复制并关闭")]
        if count > 1 { parts.append(label("⌥1–\(count) Switch", "⌥1–\(count) 切换")) }
        if !detached { parts += [label("⌘D Window", "⌘D 窗口"), label("Esc Back", "Esc 返回")] }
        return parts.joined(separator: " · ")
    }

    private func copy() {
        guard model.canCopy else { return }
        if detached {
            let board = NSPasteboard.general
            board.clearContents()
            board.declareVorssaintSource()
            copied = board.setString(model.output, forType: .string)
        } else {
            CommandBarService.shared.copyDeveloperToolResult()
        }
    }
}

struct CommandBarDeveloperToolsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.commandBarDeveloperToolsEnabled) private var enabled = true
    private var chinese: Bool { l10n.language.rawValue.hasPrefix("zh") }

    var body: some View {
        Section {
            Toggle(chinese ? "开发工具" : "Developer tools", isOn: Binding {
                enabled
            } set: { value in
                enabled = value
                CommandBarService.shared.syncWithPreferences()
            })
            Text(chinese
                 ? "JSON、Base64、URL、Unicode、时间戳、JWT、哈希。输入、选中或刚复制的内容会自动识别，回车复制结果，Tab 进入工具页编辑。全部在本机处理。"
                 : "JSON, Base64, URL, Unicode, timestamps, JWT and hashes. Typed, selected or just-copied text is recognized; Return copies the result, Tab opens the tool to edit. Everything runs locally.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(chinese ? "开发工具" : "Developer tools") }
    }
}
