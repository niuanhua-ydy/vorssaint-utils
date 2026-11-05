// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// New tools follow the existing developer tools' Chinese/English fallback.
enum CommandBarSystemText {
    static func text(_ chinese: String, _ english: String, language: AppLanguage = L10n.shared.language) -> String {
        switch language {
        case .zhHans: return chinese
        case .zhTW, .zhHK:
            return chinese.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? chinese
        default: return english
        }
    }
}

extension CommandBarCatalog {
    static func systemCommandEntries(language: AppLanguage) -> [CommandBarEntry] {
        func text(_ zh: String, _ en: String) -> String { CommandBarSystemText.text(zh, en, language: language) }
        var entries = [CommandBarEntry(
            id: "answer.ip.browse", title: text("本机 IP 地址", "Local IP addresses"),
            subtitle: text("读取网络接口；公网 IP 按需查询", "Local interfaces; public IP on request"),
            keywords: "ip publicip 本机 局域网 内网 外网 公网 网络 地址",
            icon: .symbol("network"), keepsBarOpen: true,
            run: { _ in CommandBarService.shared.showIPAddresses() })]
        if AppFeature.quickToggles.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.showTrash", title: text("打开废纸篓", "Open Trash"),
                subtitle: text("在 Finder 中打开", "Open in Finder"), keywords: "trash 废纸篓",
                icon: .symbol("trash"), run: { _ in
                    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
                    if !NSWorkspace.shared.open(url) { NSSound.beep() }
                }))
        }
        if AppFeature.mixer.isAvailable {
            for (id, delta, zh, en) in [("volumeUp", 0.0625, "调高音量", "Volume Up"),
                                        ("volumeDown", -0.0625, "调低音量", "Volume Down")] {
                entries.append(CommandBarEntry(
                    id: "action.\(id)", title: text(zh, en),
                    subtitle: text("系统输出音量 · 一格", "System output volume · one step"),
                    keywords: delta > 0 ? "volup volume up 音量 加" : "voldown volume down 音量 减",
                    icon: .symbol(delta > 0 ? "speaker.wave.3" : "speaker.wave.1"), run: { _ in
                        guard let current = AppVolumeMixer.systemOutputLevel() else { NSSound.beep(); return }
                        let level = min(1, max(0, current + delta))
                        guard AppVolumeMixer.setSystemOutputVolume(level) else { NSSound.beep(); return }
                        if NotchSupport.routes(.volume), NotchService.shared.showVolume(level) { return }
                        QuickToolHUD.show(icon: "speaker.wave.2", message: "\(Int((level * 100).rounded()))%")
                    }))
            }
        }
        return entries
    }
}
