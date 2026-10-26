// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// One window per tool, so opening another tool never discards a draft.
final class CommandBarDeveloperToolsWindows: NSObject, NSWindowDelegate {
    static let shared = CommandBarDeveloperToolsWindows()
    private var windows: [String: NSWindow] = [:]

    func show(_ tool: CommandBarDeveloperTool) {
        guard AppFeature.commandBar.isAvailable,
              CommandBarDeveloperTools.enabled(disabledRaw: UserDefaults.standard.string(
                forKey: DefaultsKey.commandBarDisabledDeveloperTools) ?? "").contains(where: { $0.id == tool.id }) else { return }
        if let window = windows[tool.id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = tool.name
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: CommandBarDeveloperToolsView(tool: tool))
        window.minSize = NSSize(width: 560, height: 500)
        windows[tool.id] = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows.removeValue(forKey: id)
    }
}

struct CommandBarDeveloperToolsView: View {
    let tool: CommandBarDeveloperTool
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""
    @State private var output = ""
    @State private var operationID = ""
    @State private var error: String?
    @State private var hasResult = false
    @State private var copied = false
    @FocusState private var inputFocused: Bool

    private var chinese: Bool { l10n.language.rawValue.hasPrefix("zh") }
    private func label(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(chinese ? tool.chineseName : tool.name, systemImage: tool.symbol).font(.headline)
            Picker(label("Operation", "操作"), selection: $operationID) {
                ForEach(tool.operations) { operation in
                    Text(chinese ? operation.chineseName : operation.name).tag(operation.id)
                }
            }
            Text(label("Input · UTF-8", "输入 · UTF-8")).font(.caption)
            TextEditor(text: $input)
                .font(.system(size: 13, design: .monospaced))
                .focused($inputFocused)
                .accessibilityLabel(label("Input", "输入"))
                .border(Color.secondary.opacity(0.2))
            HStack {
                Text("\(input.utf8.count) / \(CommandBarDeveloperTools.maxInputBytes) bytes")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(label("Clear", "清空")) { input = ""; invalidate() }
                Button(label("Run ⌘↩", "执行 ⌘↩"), action: run)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(input.utf8.count > CommandBarDeveloperTools.maxInputBytes)
            }
            HStack {
                Text(label("Output", "结果")).font(.caption)
                Spacer()
                Button(label("Use as input", "用作输入")) { input = output }
                    .disabled(!hasResult)
                Button(copied ? label("Copied", "已复制") : label("Copy", "复制")) {
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.declareVorssaintSource()
                    copied = board.setString(output, forType: .string)
                }.disabled(!hasResult)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(output.isEmpty ? " " : output)
                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color.secondary.opacity(0.2))
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text(label("Local only · Nothing saved · Closing clears this draft · URL decoding keeps + unchanged",
                       "仅本地处理 · 不保存内容 · 关闭窗口清除草稿 · URL 解码保留 +"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear { operationID = tool.operations[0].id; inputFocused = true }
        .onChange(of: input) { invalidate() }
        .onChange(of: operationID) { invalidate() }
    }

    private func invalidate() { output = ""; error = nil; hasResult = false; copied = false }

    private func run() {
        invalidate()
        guard let operation = tool.operations.first(where: { $0.id == operationID }) else { return }
        do {
            output = try CommandBarDeveloperTools.run(operation, input: input)
            hasResult = true
        } catch let failure as CommandBarDeveloperTools.Failure {
            switch failure {
            case .outputTooLarge: error = label("Formatted output exceeds 2 MiB; use Minify instead.", "格式化结果超过 2 MiB，请改用压缩。")
            case .tooLarge: error = label("Input exceeds 256 KiB.", "输入超过 256 KiB。")
            case .invalidBase64: error = label("Invalid Base64.", "Base64 格式无效。")
            case .invalidUTF8: error = label("Decoded bytes are not UTF-8 text.", "解码结果不是 UTF-8 文本。")
            case .invalidURL: error = label("Invalid percent encoding or UTF-8.", "百分号编码或 UTF-8 无效。")
            case .invalidEscape: error = label("Expected a quoted JSON string.", "请输入带双引号的 JSON 字符串。")
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct CommandBarDeveloperToolsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.commandBarDisabledDeveloperTools) private var disabled = ""
    private var chinese: Bool { l10n.language.rawValue.hasPrefix("zh") }

    var body: some View {
        Section {
            ForEach(CommandBarDeveloperTools.all) { tool in
                Toggle(isOn: Binding {
                    CommandBarDeveloperTools.enabled(disabledRaw: disabled).contains { $0.id == tool.id }
                } set: { enabled in
                    disabled = CommandBarDeveloperTools.setting(tool.id, enabled: enabled, disabledRaw: disabled)
                    CommandBarService.shared.syncWithPreferences()
                }) {
                    Label(chinese ? tool.chineseName : tool.name, systemImage: tool.symbol)
                }
            }
            Text(chinese ? "独立启停；关闭后不再出现在命令栏。所有转换仅在本机执行。" : "Enable tools independently. Disabled tools leave the command bar. All conversions run locally.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(chinese ? "开发工具插件" : "Developer tool plugins") }
    }
}
