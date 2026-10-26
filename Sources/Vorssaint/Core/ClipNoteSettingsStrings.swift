// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import Foundation

/// The words of ClipNote's Settings page.
struct ClipNoteSettingsStrings {
    let enable: String
    let caption: String
    let localNote: String
    let active: String
    let storeErrorFormat: String
    let turnOnFirst: String

    // Tabs
    let tabGeneral: String
    let tabPrivacy: String
    let tabStorage: String
    let tabAI: String
    let tabSync: String
    let tabBackup: String

    // General
    let shortcutsHeader: String
    let stackShortcut: String
    let stackCaption: String
    let autoPasteCaption: String
    let accessibilityCaption: String
    let deleteNeedsCommand: String
    let deleteNeedsCommandCaption: String
    let panelKeysHeader: String
    let keyMove: String
    let keyPaste: String
    let keyHoldCommand: String
    let keyNumbers: String
    let keySpace: String
    let keyPreview: String
    let keyTab: String
    let keyCopyDelete: String
    let keySync: String
    let keyEscape: String

    // Privacy
    let pauseCaption: String
    let skipConcealed: String
    let skipConcealedCaption: String
    let ignoredAppsHeader: String
    let ignoredAppsCaption: String

    // Storage
    let retention: String
    let retentionCaption: String
    let retentionDay: String
    let retentionWeek: String
    let retentionMonth: String
    let retentionThreeMonths: String
    let retentionYear: String
    let forever: String
    let maxItems: String
    let maxItemsCaption: String
    let itemsFormat: String
    let maxCapture: String
    let maxCaptureCaption: String
    let ocr: String
    let ocrCaption: String
    let ocrBackfill: String
    let ocrBackfillCaption: String
    let ocrProgress: String
    let ocrAllDoneFormat: String
    let ocrProgressFormat: String
    let ocrFailedFormat: String
    let ocrPaused: String
    let ocrLowPower: String
    let ocrRunning: String
    let ocrWaiting: String
    let itemCount: String
    let dataLocation: String
    let applyRetention: String

    // AI
    let aiProvider: String
    let aiProviderAnthropicHint: String
    let aiProviderResponsesHint: String
    let aiProviderChatHint: String
    let aiServiceHeader: String
    let aiBaseURL: String
    let aiAPIKey: String
    let aiModel: String
    let aiModelPresetsHelp: String
    let aiModelPlaceholderResponses: String
    let aiModelPlaceholderChat: String
    let aiEffort: String
    let aiEffortCaption: String
    let effortAuto: String
    let effortLow: String
    let effortMedium: String
    let effortHigh: String
    let testConnection: String
    let testing: String
    let aiTestSuccessFormat: String
    let aiServiceFooter: String
    let aiUsageHeader: String
    let aiUsage: String
    let aiPrivacy: String

    // Sync
    let webdavHeader: String
    let serverURL: String
    let presetsHelp: String
    let presetJianguoyun: String
    let presetSynology: String
    let presetQNAP: String
    let account: String
    let password: String
    let syncFolder: String
    let trustSelfSigned: String
    let trustSelfSignedCaption: String
    let webdavFooter: String
    let plainHTTPWarning: String
    let syncPrivacyHeader: String
    let passphrase: String
    let syncImages: String
    let maxSyncItem: String
    let maxSyncItemCaption: String
    let syncPrivacyFooter: String
    let syncToggle: String
    let status: String
    let lastSync: String
    let never: String
    let result: String
    let statusOff: String
    let statusOK: String
    let pendingFormat: String
    let saveSettings: String
    let syncNow: String
    let syncFooter: String
    let syncTestOK: String

    // Backup
    let migrateHeader: String
    let importFromPasteCaption: String
    let startImportEllipsis: String
    let transferHeader: String
    let exportBackup: String
    let importBackup: String
    let transferFooter: String
    let iCloudHeader: String
    let autoBackup: String
    let lastBackup: String
    let backUpNow: String
    let openBackupFolder: String
    let iCloudMissingFooter: String
    let iCloudFooterFormat: String
}

extension FeatureStrings {
    static func clipNoteSettings(_ language: AppLanguage) -> ClipNoteSettingsStrings {
        switch language {
        case .zhHans: return .zhHans
        case .ja: return .ja
        case .ko: return .ko
        // Only the offered languages are written; see LanguageExclusions.
        default: return .enUS
        }
    }
}

/// The tabs of ClipNote's Settings page.
enum ClipNoteSettingsTab: String, CaseIterable, Identifiable {
    case general, privacy, storage, ai, sync, backup

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .storage: return "internaldrive"
        case .ai: return "sparkles"
        case .sync: return "arrow.triangle.2.circlepath.icloud"
        case .backup: return "externaldrive.badge.timemachine"
        }
    }
}

/// One row of the panel keys list.
struct ClipNoteKeyRow {
    let keys: String
    let action: String
}

extension ClipNoteSettingsStrings {
    func tabTitle(_ tab: ClipNoteSettingsTab) -> String {
        switch tab {
        case .general: return tabGeneral
        case .privacy: return tabPrivacy
        case .storage: return tabStorage
        case .ai: return tabAI
        case .sync: return tabSync
        case .backup: return tabBackup
        }
    }

    func effortTitle(_ effort: AIEffort) -> String {
        switch effort {
        case .auto: return effortAuto
        case .low: return effortLow
        case .medium: return effortMedium
        case .high: return effortHigh
        }
    }

    func panelKeys(deleteNeedsCommand: Bool) -> [ClipNoteKeyRow] {
        [
            ClipNoteKeyRow(keys: "← →", action: keyMove),
            ClipNoteKeyRow(keys: "↩ / ⇧↩", action: keyPaste),
            ClipNoteKeyRow(keys: keyHoldCommand, action: keyNumbers),
            ClipNoteKeyRow(keys: keySpace, action: keyPreview),
            ClipNoteKeyRow(keys: "⇥ / ⇧⇥", action: keyTab),
            ClipNoteKeyRow(keys: deleteNeedsCommand ? "⌘C / ⌘⌫" : "⌘C / ⌫", action: keyCopyDelete),
            ClipNoteKeyRow(keys: "⌘R", action: keySync),
            ClipNoteKeyRow(keys: "Esc", action: keyEscape),
        ]
    }
}

extension ClipNoteSettingsStrings {
    static let enUS = ClipNoteSettingsStrings(
        enable: "Keep clipboard history",
        caption: "Keeps what you copy (text, rich text, links, images and files) with pinboards and search in any language. Open it with its shortcut or from the Command Bar.",
        localNote: "History stays on this Mac unless you turn on sync.",
        active: "Recording",
        storeErrorFormat: "The history could not be opened: %@",
        turnOnFirst: "Turn on clipboard history to change these settings.",
        tabGeneral: "General",
        tabPrivacy: "Privacy",
        tabStorage: "Storage",
        tabAI: "AI",
        tabSync: "Sync",
        tabBackup: "Backup",
        shortcutsHeader: "Shortcuts",
        stackShortcut: "Paste Stack shortcut",
        stackCaption: "While Paste Stack is open, each copy joins its list and ⌘V pastes them in turn.",
        autoPasteCaption: "Pastes the chosen item into the app in front; off only copies it.",
        accessibilityCaption: "Pasting for you and Paste Stack need Accessibility to press ⌘V.",
        deleteNeedsCommand: "Hold ⌘ to delete",
        deleteNeedsCommandCaption: "Delete alone removes the chosen item while the search is empty; on, only ⌘Delete does.",
        panelKeysHeader: "Panel keys",
        keyMove: "Move between items",
        keyPaste: "Paste / paste as plain text",
        keyHoldCommand: "Hold ⌘ · ⌘1 … ⌘9",
        keyNumbers: "Show and paste item N",
        keySpace: "Space / ⌘Y",
        keyPreview: "Preview (Space while the search is empty)",
        keyTab: "Switch pinboards",
        keyCopyDelete: "Copy / delete item",
        keySync: "Sync now (with sync on)",
        keyEscape: "Clear the search / close the panel",
        pauseCaption: "Stops saving new copies for now.",
        skipConcealed: "Ignore confidential content",
        skipConcealedCaption: "Skips what password managers and similar apps mark as sensitive.",
        ignoredAppsHeader: "Ignored apps",
        ignoredAppsCaption: "Copies from these apps are never saved.",
        retention: "Keep for",
        retentionCaption: "Older history is removed on its own; items in pinboards stay.",
        retentionDay: "1 day",
        retentionWeek: "1 week",
        retentionMonth: "1 month",
        retentionThreeMonths: "3 months",
        retentionYear: "1 year",
        forever: "Forever",
        maxItems: "Keep at most",
        maxItemsCaption: "Past this, the oldest history goes first.",
        itemsFormat: "%d items",
        maxCapture: "Largest copy to keep",
        maxCaptureCaption: "Text or images larger than this are not saved. Files copied in Finder are kept as paths, with no limit.",
        ocr: "Recognize text in images",
        ocrCaption: "Makes screenshots and images searchable. It runs on this Mac; nothing is uploaded. Loading the recognition model uses extra memory.",
        ocrBackfill: "Recognize existing images",
        ocrBackfillCaption: "Reads images saved before (Paste imports too) one at a time, at low priority, waiting in Low Power Mode. Turning it off and on again carries on where it stopped.",
        ocrProgress: "Recognition progress",
        ocrAllDoneFormat: "All %d recognized",
        ocrProgressFormat: "%1$d / %2$d · %3$d left · %4$@",
        ocrFailedFormat: "%d could not be read (missing or damaged)",
        ocrPaused: "Paused",
        ocrLowPower: "Waiting in Low Power Mode",
        ocrRunning: "Recognizing",
        ocrWaiting: "Waiting",
        itemCount: "Items",
        dataLocation: "Data location",
        applyRetention: "Clean Up Now",
        aiProvider: "API format",
        aiProviderAnthropicHint: "Anthropic Messages: Claude itself, and relay services that speak its format.",
        aiProviderResponsesHint: "OpenAI Responses (the format Codex uses).",
        aiProviderChatHint: "OpenAI Chat Completions compatible: DeepSeek, Qwen, Kimi, Ollama and others.",
        aiServiceHeader: "Model service",
        aiBaseURL: "Address",
        aiAPIKey: "API Key",
        aiModel: "Model",
        aiModelPresetsHelp: "Common models",
        aiModelPlaceholderResponses: "The provider’s model name",
        aiModelPlaceholderChat: "e.g. deepseek-chat, qwen-plus",
        aiEffort: "Thinking effort",
        aiEffortCaption: "Low is enough for polishing or translating, and answers faster. Ignored where the model or service has no such setting.",
        effortAuto: "Model default",
        effortLow: "Low (faster)",
        effortMedium: "Medium",
        effortHigh: "High (slower)",
        testConnection: "Test Connection",
        testing: "Testing…",
        aiTestSuccessFormat: "Connected (%1$@ s): %2$@",
        aiServiceFooter: "The address can be just the domain (https://api.anthropic.com) or the full endpoint; with a relay service, use the address it gives you. The API key is kept in the keychain.",
        aiUsageHeader: "How to use",
        aiUsage: "Right-click a card in the panel → “AI Actions” to polish, summarize, translate, pull out key points, explain, or give your own instruction. The answer streams in and can be pasted, copied or saved as a new item. Images use their recognized text.",
        aiPrivacy: "Only when you run an AI action is the chosen item’s text sent to the service above; nothing is sent on its own.",
        webdavHeader: "WebDAV server",
        serverURL: "Server address",
        presetsHelp: "Fill in a common service (change a NAS to your own IP and port)",
        presetJianguoyun: "Jianguoyun",
        presetSynology: "Synology (HTTPS 5006)",
        presetQNAP: "QNAP (HTTPS 5001)",
        account: "Account",
        password: "Password",
        syncFolder: "Sync folder",
        trustSelfSigned: "Trust self-signed certificate",
        trustSelfSignedCaption: "For a NAS with a self-signed HTTPS certificate (trusted for this address only).",
        webdavFooter: "Works with Jianguoyun, the WebDAV service of a Synology or QNAP NAS, Nextcloud, Alist and more. The address needs its scheme and port, and the account must be able to read and write the sync folder. Jianguoyun: use an app password made under Account → Security → Third-party apps. Synology: install “WebDAV Server” from Package Center (HTTPS port 5006). QNAP: Control Panel → Network & File Services → WebDAV.",
        plainHTTPWarning: "Over http the account and password travel unencrypted; use it only on your local network, with a sync password set below.",
        syncPrivacyHeader: "Privacy and traffic",
        passphrase: "Sync password (optional)",
        syncImages: "Sync images",
        maxSyncItem: "Largest item to upload",
        maxSyncItemCaption: "Text or images larger than this stay on this Mac, unseen by other devices. Copied files sync as paths, never the file itself.",
        syncPrivacyFooter: "With a sync password, everything uploaded is end-to-end encrypted, and other devices need the same password; unencrypted data already on the server cannot simply switch to encrypted. On a traffic-limited service (like Jianguoyun’s free plan), turn off “Sync images” if you copy many.",
        syncToggle: "Sync",
        status: "Status",
        lastSync: "Last synced",
        never: "Never",
        result: "Result",
        statusOff: "Off",
        statusOK: "OK",
        pendingFormat: "%d waiting to upload",
        saveSettings: "Save Settings",
        syncNow: "Sync Now",
        syncFooter: "Once on, it syncs every 15 seconds, and about 3 seconds after something new on this Mac. The first sync uploads everything here. If the server refuses or rate limits, it waits a while and tries again on its own.",
        syncTestOK: "Connected; the sync folder can be read and written",
        migrateHeader: "Moving from another tool",
        importFromPasteCaption: "Reads all of Paste’s items, pinboards and titles on this Mac and merges them in. Paste is never changed and nothing here is overwritten; it can be paused any time and continued later.",
        startImportEllipsis: "Import…",
        transferHeader: "Import / Export",
        exportBackup: "Export Backup…",
        importBackup: "Import Backup…",
        transferFooter: "A backup is a zip file with all text, images, pinboards and use history. Importing merges: content already here is skipped and nothing is deleted.",
        iCloudHeader: "iCloud Drive",
        autoBackup: "Back up to iCloud Drive every day",
        lastBackup: "Last backup",
        backUpNow: "Back Up Now",
        openBackupFolder: "Open Backup Folder",
        iCloudMissingFooter: "iCloud Drive isn’t on. Turn it on in System Settings → Apple Account → iCloud first.",
        iCloudFooterFormat: "Backups go to “ClipNote/自动备份” in iCloud Drive. The latest %d are kept, and the system carries them to your other devices; “Import Backup” on another Mac merges them.")

    static let zhHans = ClipNoteSettingsStrings(
        enable: "记录剪贴板历史",
        caption: "保存复制过的内容（文本、富文本、链接、图片和文件），支持分类和中英文全文搜索。用快捷键或在 Command Bar 中打开。",
        localNote: "除非开启同步，历史只保存在本机。",
        active: "正在记录",
        storeErrorFormat: "无法打开剪贴板历史：%@",
        turnOnFirst: "开启剪贴板历史后才能修改这些设置。",
        tabGeneral: "通用",
        tabPrivacy: "隐私",
        tabStorage: "存储",
        tabAI: "AI",
        tabSync: "同步",
        tabBackup: "备份",
        shortcutsHeader: "快捷键",
        stackShortcut: "Paste Stack 快捷键",
        stackCaption: "Paste Stack 打开期间，连续复制的内容会依次进入列表，再用 ⌘V 依次粘贴。",
        autoPasteCaption: "选中条目后直接粘贴到当前应用；关闭则只复制到剪贴板。",
        accessibilityCaption: "自动粘贴和 Paste Stack 需要辅助功能权限来模拟 ⌘V。",
        deleteNeedsCommand: "删除条目需按住 ⌘",
        deleteNeedsCommandCaption: "关闭时，搜索框为空时直接按 ⌫ 即可删除选中条目；打开后只有 ⌘⌫ 才会删除。",
        panelKeysHeader: "面板快捷键",
        keyMove: "切换条目",
        keyPaste: "粘贴 / 粘贴为纯文本",
        keyHoldCommand: "按住 ⌘ · ⌘1 … ⌘9",
        keyNumbers: "显示并粘贴第 N 个条目",
        keySpace: "空格 / ⌘Y",
        keyPreview: "预览（搜索框为空时可用空格）",
        keyTab: "切换分类",
        keyCopyDelete: "复制 / 删除条目",
        keySync: "立即同步（开启同步时）",
        keyEscape: "清空搜索 / 关闭面板",
        pauseCaption: "暂时不保存新的复制内容。",
        skipConcealed: "忽略机密内容",
        skipConcealedCaption: "检测到密码管理器等标记为敏感的内容时不保存。",
        ignoredAppsHeader: "忽略应用程序",
        ignoredAppsCaption: "不要保存从以下应用程序复制的内容。",
        retention: "保留时长",
        retentionCaption: "超过时长的历史会自动清理，分类中的条目除外。",
        retentionDay: "1 天",
        retentionWeek: "1 周",
        retentionMonth: "1 个月",
        retentionThreeMonths: "3 个月",
        retentionYear: "1 年",
        forever: "永久",
        maxItems: "最多保留",
        maxItemsCaption: "超出数量时从最早的历史开始清理。",
        itemsFormat: "%d 条",
        maxCapture: "记录大小上限",
        maxCaptureCaption: "复制的文字或图片超过此大小时，不保存到剪贴板历史。访达中复制的文件只记录路径，不受此限制。",
        ocr: "识别图片中的文字",
        ocrCaption: "复制图片时识别其中的文字，让截图和图片可以被搜索（在本机完成，不会上传）。识别模型会额外占用内存。",
        ocrBackfill: "后台识别已有图片",
        ocrBackfillCaption: "逐张识别以前保存（含从 Paste 导入）但尚未识别的图片。低优先级运行，低电量模式下暂停；随时可关闭，再次开启会从剩下的继续。",
        ocrProgress: "识别进度",
        ocrAllDoneFormat: "全部 %d 张已识别",
        ocrProgressFormat: "%1$d / %2$d 张 · 剩余 %3$d 张 · %4$@",
        ocrFailedFormat: "%d 张无法识别（文件丢失或已损坏）",
        ocrPaused: "已暂停",
        ocrLowPower: "低电量模式，已暂停",
        ocrRunning: "识别中",
        ocrWaiting: "等待中",
        itemCount: "条目数量",
        dataLocation: "数据位置",
        applyRetention: "立即应用保留策略",
        aiProvider: "接口格式",
        aiProviderAnthropicHint: "Anthropic Messages 接口：Claude 官方，以及兼容 Claude 格式的中转服务。",
        aiProviderResponsesHint: "OpenAI Responses 接口（Codex 使用的格式）。",
        aiProviderChatHint: "OpenAI Chat Completions 兼容接口：DeepSeek、通义千问、Kimi、Ollama 等。",
        aiServiceHeader: "模型服务",
        aiBaseURL: "服务地址",
        aiAPIKey: "API Key",
        aiModel: "模型",
        aiModelPresetsHelp: "选择常用模型",
        aiModelPlaceholderResponses: "服务商提供的模型名称",
        aiModelPlaceholderChat: "如 deepseek-chat、qwen-plus",
        aiEffort: "思考深度",
        aiEffortCaption: "润色、翻译等简单处理用「低」即可，出结果更快。模型或服务不支持时会自动忽略。",
        effortAuto: "模型默认",
        effortLow: "低（更快）",
        effortMedium: "中",
        effortHigh: "高（更慢）",
        testConnection: "测试连接",
        testing: "测试中…",
        aiTestSuccessFormat: "连接成功（%1$@ 秒）：%2$@",
        aiServiceFooter: "服务地址可以只填域名（如 https://api.anthropic.com），也可以填完整的接口地址；使用第三方中转服务时填写服务商提供的地址。API Key 保存在系统钥匙串中。",
        aiUsageHeader: "使用说明",
        aiUsage: "在面板中右键卡片 →「AI 操作」，可以润色、总结、翻译、提取要点、解释，或输入自定义要求。结果以流式显示，可直接粘贴、复制或存为新条目。图片使用识别出的文字。",
        aiPrivacy: "只有在你执行 AI 操作时，所选条目的文字才会发送到上面的服务，不会自动发送任何内容。",
        webdavHeader: "WebDAV 服务器",
        serverURL: "服务器地址",
        presetsHelp: "填入常用服务的地址（NAS 需改成自己的 IP 和端口）",
        presetJianguoyun: "坚果云",
        presetSynology: "群晖（HTTPS 5006）",
        presetQNAP: "威联通（HTTPS 5001）",
        account: "账号",
        password: "密码",
        syncFolder: "同步目录",
        trustSelfSigned: "信任自签名证书",
        trustSelfSignedCaption: "NAS 使用自签名 HTTPS 证书时打开（只信任上面这个地址）。",
        webdavFooter: "支持坚果云、群晖 / 威联通等 NAS 的 WebDAV 服务，以及 Nextcloud、Alist 等。地址需要包含协议和端口，账号需要对同步目录有读写权限。坚果云：密码填网页版「账户信息 → 安全选项 → 第三方应用管理」中生成的应用密码；群晖：套件中心安装「WebDAV Server」，HTTPS 端口默认 5006；威联通：控制台 → 网络和文件服务 → WebDAV。",
        plainHTTPWarning: "使用 http 时账号密码以明文传输，建议只在局域网内使用，并设置下面的同步密码。",
        syncPrivacyHeader: "隐私与流量",
        passphrase: "同步密码（可选）",
        syncImages: "同步图片",
        maxSyncItem: "上传大小上限",
        maxSyncItemCaption: "已记录的文字或图片超过此大小时不上传，只保留在本机，其他设备看不到。复制的文件只同步路径，不上传文件本身。",
        syncPrivacyFooter: "设置同步密码后，上传到服务器的内容全部端到端加密，其他设备需填写相同的密码；服务器上已有未加密数据时无法直接改为加密。服务有流量限制时（如坚果云免费版），图片较多可关闭「同步图片」。",
        syncToggle: "开启同步",
        status: "状态",
        lastSync: "上次同步",
        never: "从未",
        result: "结果",
        statusOff: "未开启",
        statusOK: "正常",
        pendingFormat: "%d 项待上传",
        saveSettings: "保存设置",
        syncNow: "立即同步",
        syncFooter: "开启后每 15 秒自动同步一次，本机有新内容约 3 秒后上传。首次开启会上传本机全部记录。服务器拒绝访问或限流时会暂停一段时间后自动重试。",
        syncTestOK: "连接成功，同步目录可读写",
        migrateHeader: "从其他工具迁移",
        importFromPasteCaption: "读取本机 Paste 的全部记录、分类和标题并合并进来。不会修改 Paste，也不会覆盖已有内容；可随时暂停，之后从中断处继续。",
        startImportEllipsis: "开始导入…",
        transferHeader: "导入 / 导出",
        exportBackup: "导出备份…",
        importBackup: "导入备份…",
        transferFooter: "备份为 zip 文件，包含全部文字、图片、分类与使用记录。导入是合并：已存在的内容会跳过，不会删除现有数据。",
        iCloudHeader: "iCloud 云盘",
        autoBackup: "每天自动备份到 iCloud 云盘",
        lastBackup: "上次备份",
        backUpNow: "立即备份",
        openBackupFolder: "打开备份文件夹",
        iCloudMissingFooter: "未检测到 iCloud 云盘。请在「系统设置 → Apple 账户 → iCloud」中开启后再使用。",
        iCloudFooterFormat: "备份保存在 iCloud 云盘「ClipNote/自动备份」，保留最近 %d 份，由系统同步到你的其他设备。在另一台 Mac 上用「导入备份」即可合并数据。")

    static let ja = ClipNoteSettingsStrings(
        enable: "クリップボードの履歴を記録",
        caption: "コピーした内容（テキスト、リッチテキスト、リンク、画像、ファイル）を保存し、ピンボードと全文検索に対応します。ショートカットか Command Bar から開きます。",
        localNote: "同期をオンにしない限り、履歴はこの Mac にだけ保存されます。",
        active: "記録中",
        storeErrorFormat: "履歴を開けませんでした：%@",
        turnOnFirst: "これらの設定を変更するには、クリップボードの履歴をオンにしてください。",
        tabGeneral: "一般",
        tabPrivacy: "プライバシー",
        tabStorage: "ストレージ",
        tabAI: "AI",
        tabSync: "同期",
        tabBackup: "バックアップ",
        shortcutsHeader: "ショートカット",
        stackShortcut: "Paste Stack のショートカット",
        stackCaption: "Paste Stack を開いている間、コピーした内容が順にリストに入り、⌘V で順番にペーストできます。",
        autoPasteCaption: "選んだ項目を前面のアプリにペーストします。オフにするとコピーだけします。",
        accessibilityCaption: "自動ペーストと Paste Stack は ⌘V を送るためにアクセシビリティの許可が必要です。",
        deleteNeedsCommand: "削除に ⌘ を必要にする",
        deleteNeedsCommandCaption: "オフのときは、検索が空なら Delete キーだけで選んだ項目を削除します。オンにすると ⌘Delete でのみ削除します。",
        panelKeysHeader: "パネルのキー操作",
        keyMove: "項目を移動",
        keyPaste: "ペースト / プレーンテキストとしてペースト",
        keyHoldCommand: "⌘ を長押し · ⌘1 … ⌘9",
        keyNumbers: "N 番目の項目を表示してペースト",
        keySpace: "スペース / ⌘Y",
        keyPreview: "プレビュー（検索が空のときはスペース）",
        keyTab: "ピンボードを切り替え",
        keyCopyDelete: "項目をコピー / 削除",
        keySync: "今すぐ同期（同期がオンのとき）",
        keyEscape: "検索を消去 / パネルを閉じる",
        pauseCaption: "新しいコピーの保存を一時的に止めます。",
        skipConcealed: "機密内容を無視",
        skipConcealedCaption: "パスワード管理アプリなどが機密として示した内容は保存しません。",
        ignoredAppsHeader: "無視するアプリ",
        ignoredAppsCaption: "これらのアプリからのコピーは保存しません。",
        retention: "保存期間",
        retentionCaption: "期間を過ぎた履歴は自動で削除されます。ピンボードの項目は残ります。",
        retentionDay: "1 日",
        retentionWeek: "1 週間",
        retentionMonth: "1 か月",
        retentionThreeMonths: "3 か月",
        retentionYear: "1 年",
        forever: "無期限",
        maxItems: "最大保存数",
        maxItemsCaption: "超えた分は古い履歴から削除されます。",
        itemsFormat: "%d 件",
        maxCapture: "保存するサイズの上限",
        maxCaptureCaption: "これより大きいテキストや画像は保存しません。Finder でコピーしたファイルはパスとして保存され、制限はありません。",
        ocr: "画像内の文字を認識",
        ocrCaption: "スクリーンショットや画像を検索できるようにします。この Mac 上で処理され、何もアップロードされません。認識モデルの読み込みで追加のメモリを使用します。",
        ocrBackfill: "既存の画像を認識",
        ocrBackfillCaption: "以前に保存した画像（Paste から読み込んだものも含む）を 1 枚ずつ低い優先度で認識し、低電力モードでは待機します。オフにしても、再びオンにすると続きから再開します。",
        ocrProgress: "認識の進行状況",
        ocrAllDoneFormat: "%d 枚すべて認識済み",
        ocrProgressFormat: "%1$d / %2$d 枚 · 残り %3$d 枚 · %4$@",
        ocrFailedFormat: "%d 枚は認識できませんでした（ファイルがないか破損しています）",
        ocrPaused: "一時停止中",
        ocrLowPower: "低電力モードのため待機中",
        ocrRunning: "認識中",
        ocrWaiting: "待機中",
        itemCount: "項目数",
        dataLocation: "データの場所",
        applyRetention: "今すぐ整理",
        aiProvider: "API 形式",
        aiProviderAnthropicHint: "Anthropic Messages：Claude 本体と、同じ形式に対応した中継サービス。",
        aiProviderResponsesHint: "OpenAI Responses（Codex が使う形式）。",
        aiProviderChatHint: "OpenAI Chat Completions 互換：DeepSeek、Qwen、Kimi、Ollama など。",
        aiServiceHeader: "モデルサービス",
        aiBaseURL: "アドレス",
        aiAPIKey: "API キー",
        aiModel: "モデル",
        aiModelPresetsHelp: "よく使うモデル",
        aiModelPlaceholderResponses: "プロバイダのモデル名",
        aiModelPlaceholderChat: "例：deepseek-chat、qwen-plus",
        aiEffort: "思考の深さ",
        aiEffortCaption: "推敲や翻訳には「低」で十分で、早く結果が出ます。モデルやサービスが対応していない場合は無視されます。",
        effortAuto: "モデルの既定",
        effortLow: "低（速い）",
        effortMedium: "中",
        effortHigh: "高（遅い）",
        testConnection: "接続をテスト",
        testing: "テスト中…",
        aiTestSuccessFormat: "接続しました（%1$@ 秒）：%2$@",
        aiServiceFooter: "アドレスはドメインだけ（https://api.anthropic.com）でも、エンドポイント全体でもかまいません。中継サービスではそのサービスのアドレスを入力します。API キーはキーチェーンに保存されます。",
        aiUsageHeader: "使い方",
        aiUsage: "パネルでカードを右クリック →「AI 操作」で、推敲・要約・翻訳・要点抽出・説明、または独自の指示ができます。結果は順次表示され、ペースト・コピー・新しい項目として保存できます。画像は認識した文字を使います。",
        aiPrivacy: "AI 操作を実行したときだけ、選んだ項目のテキストが上記のサービスに送信されます。自動で送信されることはありません。",
        webdavHeader: "WebDAV サーバ",
        serverURL: "サーバのアドレス",
        presetsHelp: "よく使うサービスを入力（NAS は自分の IP とポートに変更）",
        presetJianguoyun: "坚果云",
        presetSynology: "Synology（HTTPS 5006）",
        presetQNAP: "QNAP（HTTPS 5001）",
        account: "アカウント",
        password: "パスワード",
        syncFolder: "同期フォルダ",
        trustSelfSigned: "自己署名証明書を信頼",
        trustSelfSignedCaption: "NAS が自己署名の HTTPS 証明書を使うときにオンにします（このアドレスだけを信頼します）。",
        webdavFooter: "坚果云、Synology や QNAP の NAS の WebDAV、Nextcloud、Alist などに対応します。アドレスにはスキームとポートが必要で、アカウントには同期フォルダの読み書き権限が必要です。坚果云：Web 版の「アカウント情報 → セキュリティ → サードパーティアプリ」で作ったアプリパスワードを使います。Synology：パッケージセンターで「WebDAV Server」をインストール（HTTPS ポート 5006）。QNAP：コントロールパネル → ネットワークとファイルサービス → WebDAV。",
        plainHTTPWarning: "http ではアカウントとパスワードが暗号化されずに送られます。ローカルネットワーク内だけで使い、下の同期パスワードを設定してください。",
        syncPrivacyHeader: "プライバシーと通信量",
        passphrase: "同期パスワード（任意）",
        syncImages: "画像を同期",
        maxSyncItem: "アップロードするサイズの上限",
        maxSyncItemCaption: "これより大きいテキストや画像はアップロードせずこの Mac にだけ残り、他のデバイスには表示されません。コピーしたファイルはパスだけを同期し、ファイル自体は送りません。",
        syncPrivacyFooter: "同期パスワードを設定すると、アップロードする内容はすべてエンドツーエンドで暗号化され、他のデバイスにも同じパスワードが必要です。サーバに暗号化されていないデータがある場合は、そのまま暗号化に切り替えられません。通信量に制限のあるサービス（坚果云の無料プランなど）で画像が多い場合は「画像を同期」をオフにしてください。",
        syncToggle: "同期",
        status: "状態",
        lastSync: "前回の同期",
        never: "なし",
        result: "結果",
        statusOff: "オフ",
        statusOK: "正常",
        pendingFormat: "%d 件がアップロード待ち",
        saveSettings: "設定を保存",
        syncNow: "今すぐ同期",
        syncFooter: "オンにすると 15 秒ごとに同期し、この Mac で新しい内容があると約 3 秒後にアップロードします。最初の同期ではこの Mac の履歴をすべてアップロードします。サーバが拒否または制限した場合は、しばらく待ってから自動で再試行します。",
        syncTestOK: "接続しました。同期フォルダは読み書きできます",
        migrateHeader: "他のツールから移行",
        importFromPasteCaption: "この Mac の Paste の項目・ピンボード・タイトルをすべて読み込んで統合します。Paste は変更されず、既存の内容も上書きされません。いつでも一時停止して後で再開できます。",
        startImportEllipsis: "読み込む…",
        transferHeader: "読み込み / 書き出し",
        exportBackup: "バックアップを書き出す…",
        importBackup: "バックアップを読み込む…",
        transferFooter: "バックアップはすべてのテキスト・画像・ピンボード・使用履歴を含む zip ファイルです。読み込みは統合で、既にある内容はスキップされ、何も削除されません。",
        iCloudHeader: "iCloud Drive",
        autoBackup: "毎日 iCloud Drive にバックアップ",
        lastBackup: "前回のバックアップ",
        backUpNow: "今すぐバックアップ",
        openBackupFolder: "バックアップフォルダを開く",
        iCloudMissingFooter: "iCloud Drive がオフです。先に「システム設定」→「Apple アカウント」→「iCloud」でオンにしてください。",
        iCloudFooterFormat: "バックアップは iCloud Drive の「ClipNote/自动备份」に保存され、最新の %d 個が残り、システムが他のデバイスに同期します。別の Mac で「バックアップを読み込む」を使うと統合できます。")

    static let ko = ClipNoteSettingsStrings(
        enable: "클립보드 기록 저장",
        caption: "복사한 내용(텍스트, 서식 있는 텍스트, 링크, 이미지, 파일)을 저장하고 핀보드와 전체 텍스트 검색을 지원합니다. 단축키나 Command Bar에서 엽니다.",
        localNote: "동기화를 켜지 않는 한 기록은 이 Mac에만 저장됩니다.",
        active: "기록 중",
        storeErrorFormat: "기록을 열 수 없습니다: %@",
        turnOnFirst: "이 설정을 변경하려면 클립보드 기록을 켜세요.",
        tabGeneral: "일반",
        tabPrivacy: "개인 정보",
        tabStorage: "저장 공간",
        tabAI: "AI",
        tabSync: "동기화",
        tabBackup: "백업",
        shortcutsHeader: "단축키",
        stackShortcut: "Paste Stack 단축키",
        stackCaption: "Paste Stack이 열려 있는 동안 복사한 내용이 차례로 목록에 쌓이고 ⌘V로 순서대로 붙여넣습니다.",
        autoPasteCaption: "선택한 항목을 앞에 있는 앱에 붙여넣습니다. 끄면 복사만 합니다.",
        accessibilityCaption: "자동 붙여넣기와 Paste Stack은 ⌘V를 보내기 위해 손쉬운 사용 권한이 필요합니다.",
        deleteNeedsCommand: "삭제할 때 ⌘ 필요",
        deleteNeedsCommandCaption: "끄면 검색어가 비어 있을 때 Delete 키만으로 선택한 항목을 삭제합니다. 켜면 ⌘Delete로만 삭제합니다.",
        panelKeysHeader: "패널 키",
        keyMove: "항목 이동",
        keyPaste: "붙여넣기 / 일반 텍스트로 붙여넣기",
        keyHoldCommand: "⌘ 길게 누르기 · ⌘1 … ⌘9",
        keyNumbers: "N번째 항목 표시 및 붙여넣기",
        keySpace: "Space / ⌘Y",
        keyPreview: "미리보기 (검색이 비어 있을 때 Space)",
        keyTab: "핀보드 전환",
        keyCopyDelete: "항목 복사 / 삭제",
        keySync: "지금 동기화 (동기화가 켜져 있을 때)",
        keyEscape: "검색 지우기 / 패널 닫기",
        pauseCaption: "새로 복사한 내용을 잠시 저장하지 않습니다.",
        skipConcealed: "기밀 내용 무시",
        skipConcealedCaption: "암호 관리자 등이 민감하다고 표시한 내용은 저장하지 않습니다.",
        ignoredAppsHeader: "무시할 앱",
        ignoredAppsCaption: "이 앱에서 복사한 내용은 저장하지 않습니다.",
        retention: "보관 기간",
        retentionCaption: "기간이 지난 기록은 자동으로 삭제됩니다. 핀보드 항목은 유지됩니다.",
        retentionDay: "1일",
        retentionWeek: "1주",
        retentionMonth: "1개월",
        retentionThreeMonths: "3개월",
        retentionYear: "1년",
        forever: "영구",
        maxItems: "최대 보관",
        maxItemsCaption: "초과하면 가장 오래된 기록부터 삭제됩니다.",
        itemsFormat: "%d개",
        maxCapture: "저장할 최대 크기",
        maxCaptureCaption: "이보다 큰 텍스트나 이미지는 저장하지 않습니다. Finder에서 복사한 파일은 경로로 저장되며 제한이 없습니다.",
        ocr: "이미지 속 텍스트 인식",
        ocrCaption: "스크린샷과 이미지를 검색할 수 있게 합니다. 이 Mac에서 처리되며 아무것도 업로드하지 않습니다. 인식 모델을 불러오느라 메모리를 추가로 사용합니다.",
        ocrBackfill: "기존 이미지 인식",
        ocrBackfillCaption: "이전에 저장한 이미지(Paste에서 가져온 것 포함)를 한 장씩 낮은 우선순위로 인식하며, 저전력 모드에서는 대기합니다. 껐다가 다시 켜면 남은 것부터 이어집니다.",
        ocrProgress: "인식 진행 상황",
        ocrAllDoneFormat: "%d개 모두 인식됨",
        ocrProgressFormat: "%1$d / %2$d · %3$d개 남음 · %4$@",
        ocrFailedFormat: "%d개는 인식할 수 없음(파일 없음 또는 손상)",
        ocrPaused: "일시 정지됨",
        ocrLowPower: "저전력 모드로 대기 중",
        ocrRunning: "인식 중",
        ocrWaiting: "대기 중",
        itemCount: "항목 수",
        dataLocation: "데이터 위치",
        applyRetention: "지금 정리",
        aiProvider: "API 형식",
        aiProviderAnthropicHint: "Anthropic Messages: Claude 자체와 같은 형식을 지원하는 중계 서비스.",
        aiProviderResponsesHint: "OpenAI Responses (Codex가 쓰는 형식).",
        aiProviderChatHint: "OpenAI Chat Completions 호환: DeepSeek, Qwen, Kimi, Ollama 등.",
        aiServiceHeader: "모델 서비스",
        aiBaseURL: "주소",
        aiAPIKey: "API 키",
        aiModel: "모델",
        aiModelPresetsHelp: "자주 쓰는 모델",
        aiModelPlaceholderResponses: "제공업체의 모델 이름",
        aiModelPlaceholderChat: "예: deepseek-chat, qwen-plus",
        aiEffort: "사고 깊이",
        aiEffortCaption: "다듬기나 번역에는 ‘낮음’으로 충분하며 더 빨리 답합니다. 모델이나 서비스가 지원하지 않으면 무시됩니다.",
        effortAuto: "모델 기본값",
        effortLow: "낮음 (빠름)",
        effortMedium: "보통",
        effortHigh: "높음 (느림)",
        testConnection: "연결 테스트",
        testing: "테스트 중…",
        aiTestSuccessFormat: "연결됨 (%1$@초): %2$@",
        aiServiceFooter: "주소는 도메인만(https://api.anthropic.com) 입력하거나 전체 엔드포인트를 입력할 수 있습니다. 중계 서비스는 해당 서비스의 주소를 입력하세요. API 키는 키체인에 저장됩니다.",
        aiUsageHeader: "사용 방법",
        aiUsage: "패널에서 카드를 오른쪽 클릭 → ‘AI 작업’으로 다듬기, 요약, 번역, 핵심 추출, 설명을 하거나 직접 요청할 수 있습니다. 결과는 실시간으로 표시되며 붙여넣기, 복사, 새 항목으로 저장할 수 있습니다. 이미지는 인식된 텍스트를 사용합니다.",
        aiPrivacy: "AI 작업을 실행할 때만 선택한 항목의 텍스트가 위 서비스로 전송되며, 자동으로 전송되는 것은 없습니다.",
        webdavHeader: "WebDAV 서버",
        serverURL: "서버 주소",
        presetsHelp: "자주 쓰는 서비스 입력 (NAS는 자신의 IP와 포트로 변경)",
        presetJianguoyun: "Jianguoyun",
        presetSynology: "Synology (HTTPS 5006)",
        presetQNAP: "QNAP (HTTPS 5001)",
        account: "계정",
        password: "암호",
        syncFolder: "동기화 폴더",
        trustSelfSigned: "자체 서명 인증서 신뢰",
        trustSelfSignedCaption: "NAS가 자체 서명 HTTPS 인증서를 쓸 때 켜세요 (이 주소만 신뢰합니다).",
        webdavFooter: "Jianguoyun, Synology·QNAP NAS의 WebDAV, Nextcloud, Alist 등을 지원합니다. 주소에는 스킴과 포트가 필요하며 계정에 동기화 폴더 읽기/쓰기 권한이 있어야 합니다. Jianguoyun: 웹의 ‘계정 정보 → 보안 → 타사 앱 관리’에서 만든 앱 암호를 사용하세요. Synology: 패키지 센터에서 ‘WebDAV Server’ 설치(HTTPS 포트 5006). QNAP: 제어판 → 네트워크 및 파일 서비스 → WebDAV.",
        plainHTTPWarning: "http에서는 계정과 암호가 암호화되지 않고 전송됩니다. 로컬 네트워크에서만 사용하고 아래 동기화 암호를 설정하세요.",
        syncPrivacyHeader: "개인 정보 및 데이터 사용량",
        passphrase: "동기화 암호 (선택 사항)",
        syncImages: "이미지 동기화",
        maxSyncItem: "업로드할 최대 크기",
        maxSyncItemCaption: "이보다 큰 텍스트나 이미지는 업로드하지 않고 이 Mac에만 남으며 다른 기기에서는 보이지 않습니다. 복사한 파일은 경로만 동기화하고 파일 자체는 보내지 않습니다.",
        syncPrivacyFooter: "동기화 암호를 설정하면 업로드하는 모든 내용이 종단 간 암호화되며 다른 기기에도 같은 암호가 필요합니다. 서버에 암호화되지 않은 데이터가 있으면 바로 암호화로 바꿀 수 없습니다. 데이터 사용량 제한이 있는 서비스(Jianguoyun 무료 요금제 등)에서 이미지가 많다면 ‘이미지 동기화’를 끄세요.",
        syncToggle: "동기화",
        status: "상태",
        lastSync: "마지막 동기화",
        never: "없음",
        result: "결과",
        statusOff: "꺼짐",
        statusOK: "정상",
        pendingFormat: "업로드 대기 %d개",
        saveSettings: "설정 저장",
        syncNow: "지금 동기화",
        syncFooter: "켜면 15초마다 동기화하고, 이 Mac에 새 내용이 생기면 약 3초 후 업로드합니다. 처음 동기화할 때 이 Mac의 기록을 모두 업로드합니다. 서버가 거부하거나 제한하면 잠시 기다린 후 자동으로 다시 시도합니다.",
        syncTestOK: "연결됨. 동기화 폴더를 읽고 쓸 수 있습니다",
        migrateHeader: "다른 도구에서 옮기기",
        importFromPasteCaption: "이 Mac에 있는 Paste의 모든 항목, 핀보드, 제목을 읽어 병합합니다. Paste는 변경되지 않으며 기존 내용도 덮어쓰지 않습니다. 언제든 일시 정지했다가 나중에 이어서 할 수 있습니다.",
        startImportEllipsis: "가져오기…",
        transferHeader: "가져오기 / 내보내기",
        exportBackup: "백업 내보내기…",
        importBackup: "백업 가져오기…",
        transferFooter: "백업은 모든 텍스트, 이미지, 핀보드, 사용 기록이 담긴 zip 파일입니다. 가져오기는 병합이며 이미 있는 내용은 건너뛰고 아무것도 삭제하지 않습니다.",
        iCloudHeader: "iCloud Drive",
        autoBackup: "매일 iCloud Drive에 백업",
        lastBackup: "마지막 백업",
        backUpNow: "지금 백업",
        openBackupFolder: "백업 폴더 열기",
        iCloudMissingFooter: "iCloud Drive가 꺼져 있습니다. 먼저 시스템 설정 → Apple 계정 → iCloud에서 켜세요.",
        iCloudFooterFormat: "백업은 iCloud Drive의 ‘ClipNote/自动备份’에 저장되며 최근 %d개가 유지되고, 시스템이 다른 기기로 동기화합니다. 다른 Mac에서 ‘백업 가져오기’로 병합할 수 있습니다.")
}
