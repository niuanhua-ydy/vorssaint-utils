// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import Foundation

/// The words of ClipNote's panel, Paste Stack, previews, AI window, imports
/// and messages. Its Settings page has its own, in `ClipNoteSettingsStrings`.
struct ClipNoteStrings {
    let id: String
    let title: String
    let hubDescription: String

    // Item types
    let typeText: String
    let typeRich: String
    let typeLink: String
    let typeImage: String
    let typeFile: String

    // Shared
    let ok: String
    let cancel: String
    let clear: String
    let paste: String
    let copy: String
    let delete: String
    let rename: String
    let color: String
    let preview: String
    let editEllipsis: String
    let editTitle: String
    let save: String
    let editSaveHelp: String
    let editRichNote: String
    let revealInFinder: String
    let openInBrowser: String
    let retry: String
    let stop: String
    let pause: String
    let unlimited: String
    let listSeparator: String
    let justNow: String
    let charactersFormat: String
    let filesFormat: String
    let moreFilesFormat: String
    let fileMissing: String
    let copied: String
    let saveFailed: String
    let savedAsNewItem: String

    // Panel
    let historyTab: String
    let searchHelp: String
    let searchPlaceholder: String
    let pausedHelp: String
    let deletePinboard: String
    let newPinboard: String
    let untitledPinboard: String
    let nextColorHelp: String
    let typeFilter: String
    let allTypes: String
    let sourceAppFilter: String
    let allApps: String
    let clearFilters: String
    let filterHelp: String
    let pauseRecording: String
    let autoPaste: String
    let clearHistoryEllipsis: String
    let settingsEllipsis: String
    let syncErrorHelpFormat: String
    let syncing: String
    let lastSyncFormat: String
    let neverSynced: String
    let syncNowHelpFormat: String
    let pasteToFormat: String
    let pasteAsPlainText: String
    let cleanAndPaste: String
    let cleanTrim: String
    let cleanCollapseBlankLines: String
    let cleanJoinLines: String
    let cleanMarkdown: String
    let aiActions: String
    let aiPolish: String
    let aiSummarize: String
    let aiTranslate: String
    let aiKeyPoints: String
    let aiExplain: String
    let aiCustom: String
    let aiCustomEllipsis: String
    let pinToBoard: String
    let noPinboardsYet: String
    let removeFromBoard: String
    let noMatches: String
    let emptyPinboard: String
    let emptyHistory: String
    let editTitleHelp: String
    let clearHistoryTitle: String
    let clearHistoryMessage: String

    // Preview
    let previewCloseHint: String
    let previewTruncatedFormat: String
    let previewFileMissing: String

    // Paste Stack
    let stackTitle: String
    let stackHelp: String
    let closeStack: String
    let stackNeedsAccessibility: String
    let deselect: String
    let selectWithCommand: String
    let selectAll: String
    let removeFromList: String
    let clearList: String
    let stackEmpty: String
    let selectedCountFormat: String
    let separator: String
    let separatorHelp: String
    let separatorNewline: String
    let separatorBlankLine: String
    let separatorSpace: String
    let separatorComma: String
    let separatorNone: String
    let merge: String
    let mergeHelp: String
    let orderFirstFirstHelp: String
    let orderLastFirstHelp: String
    let fromAppFormat: String

    // AI window
    let aiTitleFormat: String
    let aiGenerating: String
    let closeEscapeHelp: String
    let aiCustomPlaceholder: String
    let aiRun: String
    let aiInputTruncatedFormat: String
    let aiOutputTruncated: String
    let aiThinking: String
    let aiCustomHint: String
    let openAISettings: String
    let aiDisclaimer: String
    let aiStopHelp: String
    let regenerate: String
    let saveAsNewItem: String
    let aiSaveHelp: String
    let aiPasteHelp: String
    let aiImageHasNoText: String
    let aiItemHasNoText: String
    let providerCompatible: String

    // Sync
    let syncUploadedFormat: String
    let syncInsertedFormat: String
    let syncUpdatedFormat: String
    let syncDeletedFormat: String
    let syncMissingImagesFormat: String
    let syncUpToDateFormat: String
    let syncSummaryFormat: String
    let syncStoppedFormat: String
    let invalidServerURL: String

    // Backups
    let iCloudMissingTitle: String
    let iCloudMissingMessage: String
    let backingUpToICloud: String
    let backedUpToICloudFormat: String
    let backupDoneTitle: String
    let backupFailedTitle: String
    let exportPanelTitle: String
    let exportOnlyPinned: String
    let exporting: String
    let exportedFormat: String
    let exportDoneTitle: String
    let exportFailedTitle: String
    let importPanelTitle: String
    let backupUnreadableTitle: String
    let importConfirmFormat: String
    let importConfirmDetailFormat: String
    let importButton: String
    let importing: String
    let importSummaryFormat: String
    let importPinboardsFormat: String
    let importMissingFilesFormat: String
    let importDoneTitle: String
    let importFailedTitle: String
    let progressOfFormat: String
    let progressProcessedFormat: String

    // Paste import
    let importFromPaste: String
    let pasteUnreadableTitle: String
    let pasteUnreadableDetailFormat: String
    let chooseFolder: String
    let choosePasteFolderMessage: String
    let pasteEmptyTitle: String
    let pasteResumeFormat: String
    let pasteConfirmFormat: String
    let pasteTimeRangeFormat: String
    let pastePinboardsFormat: String
    let pasteMergeExplanation: String
    let startImport: String
    let importImages: String
    let itemSizeLimit: String
    let syncImported: String
    let syncImportedNote: String
    let pasteImportRunning: String
    let pasteImportPausing: String
    let statNew: String
    let statExisting: String
    let statSkipped: String
    let statFailed: String
    let pasteImportKeepWorking: String
    let preparing: String
    let secondsFormat: String
    let minutesFormat: String
    let importSpeedFormat: String
    let pasteResultFormat: String
    let pasteSkippedFormat: String
    let pasteSkippedTooLargeFormat: String
    let pasteSkippedImagesFormat: String
    let pasteSkippedUnsupportedFormat: String
    let pasteFailedFormat: String
    let pastePausedNote: String
    let pasteDoneTitle: String
    let pastePausedTitle: String
    let pasteInterruptedTitle: String
    let pasteInterruptedFormat: String

    // Errors
    let errorWebDAVUnauthorized: String
    let errorWebDAVForbidden: String
    let errorWebDAVRateLimited: String
    let errorHTTPFormat: String
    let errorNetworkFormat: String
    let errorBadResponse: String
    let errorPassphraseRequired: String
    let errorWrongPassphrase: String
    let errorRemoteNotEncrypted: String
    let errorUnsupportedFormatFormat: String
    let errorCorruptFormat: String
    let errorAIKeyMissing: String
    let errorAIModelMissing: String
    let errorAIInvalidURL: String
    let errorAIHTTPFormat: String
    let errorAIHTTPDetailFormat: String
    let errorAI401: String
    let errorAI403: String
    let errorAI404: String
    let errorAI413: String
    let errorAI429: String
    let errorAIUnavailable: String
    let errorAIRequestFailed: String
    let errorAIRefused: String
    let errorAIServerFormat: String
    let errorAIEmpty: String
    let errorBackupInvalidFormat: String
    let errorBackupToolFormat: String
    let errorPasteNotFoundFormat: String
    let errorPasteNotReadableFormat: String
    let errorPasteUnsupportedFormat: String
}

extension FeatureStrings {
    static func clipNote(_ language: AppLanguage) -> ClipNoteStrings {
        switch language {
        case .zhHans: return .zhHans
        case .ja: return .ja
        case .ko: return .ko
        // Only the offered languages are written; see LanguageExclusions.
        default: return .enUS
        }
    }
}

extension ClipNoteStrings {
    func typeName(_ type: ClipType) -> String {
        switch type {
        case .text: return typeText
        case .rich: return typeRich
        case .link: return typeLink
        case .image: return typeImage
        case .file: return typeFile
        }
    }

    /// The item's own title, or its type.
    func displayTitle(of item: ClipItem) -> String {
        item.title ?? typeName(item.type)
    }

    func providerTitle(_ provider: AIProvider) -> String {
        provider == .openAIChat ? providerCompatible : provider.title
    }

    func syncSummary(_ report: SyncReport) -> String {
        var parts: [String] = []
        if report.uploadedOps > 0 { parts.append(String(format: syncUploadedFormat, report.uploadedOps)) }
        let applied = report.applied
        if applied.inserted > 0 { parts.append(String(format: syncInsertedFormat, applied.inserted)) }
        if applied.updated > 0 { parts.append(String(format: syncUpdatedFormat, applied.updated)) }
        if applied.deleted > 0 { parts.append(String(format: syncDeletedFormat, applied.deleted)) }
        if applied.missingFiles > 0 { parts.append(String(format: syncMissingImagesFormat, applied.missingFiles)) }
        if parts.isEmpty { return String(format: syncUpToDateFormat, report.otherDevices) }
        return String(format: syncSummaryFormat, parts.joined(separator: listSeparator), report.otherDevices)
    }

    /// ClipNote's core describes its errors in Chinese; this says the same in
    /// the interface language. Details the core passes along (a server path,
    /// a reason from a damaged file) are shown as they came.
    func describe(_ error: Error) -> String {
        switch error {
        case let error as WebDAVError:
            switch error {
            case .unauthorized: return errorWebDAVUnauthorized
            case .forbidden: return errorWebDAVForbidden
            case .rateLimited: return errorWebDAVRateLimited
            case .http(let code, let path): return String(format: errorHTTPFormat, code, path)
            case .network(let message): return String(format: errorNetworkFormat, message)
            case .badResponse: return errorBadResponse
            }
        case let error as SyncError:
            switch error {
            case .passphraseRequired: return errorPassphraseRequired
            case .wrongPassphrase: return errorWrongPassphrase
            case .remoteNotEncrypted: return errorRemoteNotEncrypted
            case .unsupportedFormat(let version): return String(format: errorUnsupportedFormatFormat, version)
            case .corruptData(let what): return String(format: errorCorruptFormat, what)
            }
        case let error as AIError:
            switch error {
            case .notConfigured(let what): return what.contains("API Key") ? errorAIKeyMissing : errorAIModelMissing
            case .invalidURL: return errorAIInvalidURL
            case .http(let status, let message):
                let hint: String
                switch status {
                case 401: hint = errorAI401
                case 403: hint = errorAI403
                case 404: hint = errorAI404
                case 413: hint = errorAI413
                case 429: hint = errorAI429
                case 500...599: hint = errorAIUnavailable
                default: hint = errorAIRequestFailed
                }
                return message.isEmpty ? String(format: errorAIHTTPFormat, hint, status)
                    : String(format: errorAIHTTPDetailFormat, hint, status, message)
            case .refused: return errorAIRefused
            case .server(let message): return String(format: errorAIServerFormat, message)
            case .network(let message): return String(format: errorNetworkFormat, message)
            case .emptyResponse: return errorAIEmpty
            }
        case let error as BackupService.BackupError:
            switch error {
            case .invalidArchive(let reason): return String(format: errorBackupInvalidFormat, reason)
            case .archiveTool(let output): return String(format: errorBackupToolFormat, output)
            }
        case let error as PasteLibrary.LibraryError:
            switch error {
            case .notFound(let url): return String(format: errorPasteNotFoundFormat, url.path)
            case .notReadable(_, let reason): return String(format: errorPasteNotReadableFormat, reason)
            case .unsupported(let reason): return String(format: errorPasteUnsupportedFormat, reason)
            }
        default:
            return error.localizedDescription
        }
    }
}

extension ClipNoteStrings {
    static let enUS = ClipNoteStrings(
        id: "en-US",
        title: "Clipboard",
        hubDescription: "Clipboard history with pinboards, full-text search, Paste Stack, AI actions and sync",
        typeText: "Text",
        typeRich: "Rich Text",
        typeLink: "Link",
        typeImage: "Image",
        typeFile: "File",
        ok: "OK",
        cancel: "Cancel",
        clear: "Clear",
        paste: "Paste",
        copy: "Copy",
        delete: "Delete",
        rename: "Rename",
        color: "Color",
        preview: "Preview",
        editEllipsis: "Edit…",
        editTitle: "Edit",
        save: "Save",
        editSaveHelp: "Save (⌘S)",
        editRichNote: "Saving keeps the text and drops its formatting",
        revealInFinder: "Show in Finder",
        openInBrowser: "Open in Browser",
        retry: "Try Again",
        stop: "Stop",
        pause: "Pause",
        unlimited: "Unlimited",
        listSeparator: ", ",
        justNow: "just now",
        charactersFormat: "%d characters",
        filesFormat: "%d files",
        moreFilesFormat: "%d more…",
        fileMissing: "File moved or deleted",
        copied: "Copied",
        saveFailed: "Couldn’t save",
        savedAsNewItem: "Saved as a new item",
        historyTab: "Clipboard",
        searchHelp: "Search (just start typing)",
        searchPlaceholder: "Search…",
        pausedHelp: "Recording paused",
        deletePinboard: "Delete Pinboard (Items Stay in History)",
        newPinboard: "New Pinboard",
        untitledPinboard: "Untitled",
        nextColorHelp: "Click to change the color",
        typeFilter: "Type",
        allTypes: "All Types",
        sourceAppFilter: "Source App",
        allApps: "All Apps",
        clearFilters: "Clear Filters",
        filterHelp: "Filter",
        pauseRecording: "Pause Recording",
        autoPaste: "Paste After Choosing",
        clearHistoryEllipsis: "Clear History…",
        settingsEllipsis: "Settings…",
        syncErrorHelpFormat: "Sync failed: %@\nClick to try again (⌘R)",
        syncing: "Syncing…",
        lastSyncFormat: "Last synced %@",
        neverSynced: "Not synced yet",
        syncNowHelpFormat: "Sync Now (⌘R)\n%@",
        pasteToFormat: "Paste to %@",
        pasteAsPlainText: "Paste as Plain Text",
        cleanAndPaste: "Clean Up and Paste",
        cleanTrim: "Trim Whitespace",
        cleanCollapseBlankLines: "Remove Extra Blank Lines",
        cleanJoinLines: "Join into One Line",
        cleanMarkdown: "Convert to Markdown",
        aiActions: "AI Actions",
        aiPolish: "Polish",
        aiSummarize: "Summarize",
        aiTranslate: "Translate",
        aiKeyPoints: "Key Points",
        aiExplain: "Explain",
        aiCustom: "Custom",
        aiCustomEllipsis: "Custom Instruction…",
        pinToBoard: "Pin to Pinboard",
        noPinboardsYet: "No pinboards yet. Click + at the top to add one.",
        removeFromBoard: "Remove from Pinboard",
        noMatches: "No matches",
        emptyPinboard: "Right-click a card → “Pin to Pinboard” to add it here",
        emptyHistory: "Copy something and it shows up here",
        editTitleHelp: "Click to edit the title",
        clearHistoryTitle: "Clear clipboard history?",
        clearHistoryMessage: "Items in pinboards are kept. This can’t be undone.",
        previewCloseHint: "Space / Esc to close",
        previewTruncatedFormat: "…Too long; showing the first %d characters",
        previewFileMissing: "The file was moved or deleted and can’t be previewed",
        stackTitle: "Paste Stack",
        stackHelp: "Each copy joins the list; press ⌘V in any app to paste them in turn. ⌘-click to pick rows and merge them; right-click to remove or clear.",
        closeStack: "Close Paste Stack",
        stackNeedsAccessibility: "No Accessibility access: clicking a row copies it",
        deselect: "Deselect",
        selectWithCommand: "Select (⌘-Click)",
        selectAll: "Select All",
        removeFromList: "Remove from List",
        clearList: "Clear List",
        stackEmpty: "Your copies will line up here",
        selectedCountFormat: "%d selected",
        separator: "Separator",
        separatorHelp: "How merged rows are joined",
        separatorNewline: "New Line",
        separatorBlankLine: "Blank Line",
        separatorSpace: "Space",
        separatorComma: "Comma",
        separatorNone: "Nothing",
        merge: "Merge",
        mergeHelp: "Joins them in list order into one text that replaces the selected rows and is saved to the history",
        orderFirstFirstHelp: "First in, first out: the first copy pastes first. Click for last in, first out.",
        orderLastFirstHelp: "Last in, first out: the latest copy pastes first. Click for first in, first out.",
        fromAppFormat: "From %@",
        aiTitleFormat: "AI %@",
        aiGenerating: "Generating…",
        closeEscapeHelp: "Close (Esc)",
        aiCustomPlaceholder: "What should be done? E.g. “make it a formal email”",
        aiRun: "Run",
        aiInputTruncatedFormat: "The source is long; only its first %d characters were used",
        aiOutputTruncated: "The answer hit the length limit and was cut off",
        aiThinking: "Thinking…",
        aiCustomHint: "Type an instruction above and press ↩",
        openAISettings: "Open AI Settings",
        aiDisclaimer: "AI can make mistakes. Check before using.",
        aiStopHelp: "Stop (Esc or ⌘.)",
        regenerate: "Regenerate",
        saveAsNewItem: "Save as Item",
        aiSaveHelp: "Save to the clipboard history (⌘S)",
        aiPasteHelp: "Paste into the app you came from (⌘↩)",
        aiImageHasNoText: "No text has been recognized in this image yet",
        aiItemHasNoText: "This item has no text to work on",
        providerCompatible: "OpenAI Compatible",
        syncUploadedFormat: "%d uploaded",
        syncInsertedFormat: "%d new",
        syncUpdatedFormat: "%d updated",
        syncDeletedFormat: "%d deleted",
        syncMissingImagesFormat: "%d images missing their files",
        syncUpToDateFormat: "Up to date (%d other devices)",
        syncSummaryFormat: "%1$@ (%2$d other devices)",
        syncStoppedFormat: "%1$@ (failed %2$d times in a row, so automatic sync is paused; click “Sync Now” to resume)",
        invalidServerURL: "The server address isn’t valid; include the scheme, like https://192.168.1.10:5006/",
        iCloudMissingTitle: "iCloud Drive not found",
        iCloudMissingMessage: "Turn on iCloud Drive in System Settings → Apple Account → iCloud, then try again.",
        backingUpToICloud: "Backing up to iCloud Drive…",
        backedUpToICloudFormat: "Backed up %d items to iCloud Drive",
        backupDoneTitle: "Backup Complete",
        backupFailedTitle: "Backup Failed",
        exportPanelTitle: "Export Clipboard Backup",
        exportOnlyPinned: "Only items in pinboards",
        exporting: "Exporting…",
        exportedFormat: "Exported %1$d items to %2$@",
        exportDoneTitle: "Export Complete",
        exportFailedTitle: "Export Failed",
        importPanelTitle: "Import Clipboard Backup",
        backupUnreadableTitle: "Can’t read the backup",
        importConfirmFormat: "Import %d clipboard items?",
        importConfirmDetailFormat: "Exported %@.\nImporting merges: content already here is skipped, pinboards match by name, and nothing is deleted.",
        importButton: "Import",
        importing: "Importing…",
        importSummaryFormat: "%1$d added, %2$d already here skipped",
        importPinboardsFormat: ", %d pinboards created",
        importMissingFilesFormat: ".\n%d images had no file in the backup and were not imported",
        importDoneTitle: "Import Complete",
        importFailedTitle: "Import Failed",
        progressOfFormat: "%1$@ %2$d / %3$d",
        progressProcessedFormat: "%1$@ %2$d processed",
        importFromPaste: "Import from Paste",
        pasteUnreadableTitle: "Can’t read Paste’s data",
        pasteUnreadableDetailFormat: "%@\n\nIf Paste is installed, click “Choose Folder…” and pick Paste’s data folder (usually Library → Containers → Paste → Data → Library → Application Support → Paste). macOS lets Vorssaint read a folder you choose.",
        chooseFolder: "Choose Folder…",
        choosePasteFolderMessage: "Choose the Paste data folder that contains db.sqlite",
        pasteEmptyTitle: "Paste has nothing to import",
        pasteResumeFormat: "Continue the unfinished import (about %1$d of %2$d left)",
        pasteConfirmFormat: "Import %d items from Paste?",
        pasteTimeRangeFormat: "From %1$@ to %2$@. ",
        pastePinboardsFormat: "%d pinboards.",
        pasteMergeExplanation: "Importing only merges: content already here stays as it is (only missing pinboards and titles are filled in), and nothing in Vorssaint or Paste is changed or deleted. It runs in the background and can be paused and continued later.",
        startImport: "Start Import",
        importImages: "Import images",
        itemSizeLimit: "Size limit per item",
        syncImported: "Sync imported items to other devices",
        syncImportedNote: "Off keeps imported items on this Mac. With a traffic-limited service (Jianguoyun’s free plan uploads 1 GB a month), leave it off for large imports.",
        pasteImportRunning: "Importing from Paste…",
        pasteImportPausing: "Pausing (saving the current batch)…",
        statNew: "New",
        statExisting: "Already Here",
        statSkipped: "Skipped",
        statFailed: "Failed",
        pasteImportKeepWorking: "You can keep working. Importing again after a pause picks up where it stopped.",
        preparing: "Preparing…",
        secondsFormat: "%d s",
        minutesFormat: "%d min",
        importSpeedFormat: "About %1$d/s · about %2$@ left",
        pasteResultFormat: "%1$d added, %2$d already here (merged)",
        pasteSkippedFormat: "Skipped: %@",
        pasteSkippedTooLargeFormat: "%d over the size limit",
        pasteSkippedImagesFormat: "%d images",
        pasteSkippedUnsupportedFormat: "%d unsupported (files not downloaded, browser-internal data)",
        pasteFailedFormat: "%d could not be read",
        pastePausedNote: "Paused. Choose “Import from Paste” again to continue where it stopped.",
        pasteDoneTitle: "Import Complete",
        pastePausedTitle: "Import Paused",
        pasteInterruptedTitle: "Import Interrupted",
        pasteInterruptedFormat: "%@\n\nWhat was imported is saved. Choose “Import from Paste” again to continue where it stopped.",
        errorWebDAVUnauthorized: "Wrong account or password (services like Jianguoyun need an app password, not the sign-in password)",
        errorWebDAVForbidden: "The server refused access: check that the account may read and write the sync folder. It may also be rate limiting; sync tries again later on its own.",
        errorWebDAVRateLimited: "The server is refusing for now (too many requests or temporarily unavailable); sync tries again later on its own",
        errorHTTPFormat: "The server returned error %1$d (%2$@)",
        errorNetworkFormat: "Network error: %@",
        errorBadResponse: "The server’s response wasn’t understood",
        errorPassphraseRequired: "The synced data is encrypted: enter the same sync password as on your other devices",
        errorWrongPassphrase: "Wrong sync password; use the one your other devices use",
        errorRemoteNotEncrypted: "The synced data isn’t encrypted: clear the sync password, or reset the server data before turning encryption on",
        errorUnsupportedFormatFormat: "The synced data comes from a newer version (format v%d); update first",
        errorCorruptFormat: "The synced data is damaged: %@",
        errorAIKeyMissing: "No API key yet; add it in Settings → Clipboard → AI",
        errorAIModelMissing: "No model yet; add it in Settings → Clipboard → AI",
        errorAIInvalidURL: "The service address isn’t valid",
        errorAIHTTPFormat: "%1$@ (HTTP %2$d)",
        errorAIHTTPDetailFormat: "%1$@ (HTTP %2$d): %3$@",
        errorAI401: "The API key isn’t valid",
        errorAI403: "Not allowed",
        errorAI404: "The endpoint or model doesn’t exist",
        errorAI413: "The content is too long",
        errorAI429: "Too many requests or out of quota; try again later",
        errorAIUnavailable: "The service is unavailable for now; try again later",
        errorAIRequestFailed: "The request failed",
        errorAIRefused: "The model declined to work on this content",
        errorAIServerFormat: "The service returned an error: %@",
        errorAIEmpty: "The model returned nothing",
        errorBackupInvalidFormat: "Not a valid clipboard backup: %@",
        errorBackupToolFormat: "Compressing or extracting failed: %@",
        errorPasteNotFoundFormat: "Paste’s database wasn’t found: %@",
        errorPasteNotReadableFormat: "Can’t read Paste’s database: %@",
        errorPasteUnsupportedFormat: "Unsupported Paste data: %@")

    static let zhHans = ClipNoteStrings(
        id: "zh-Hans",
        title: "剪贴板",
        hubDescription: "带分类、全文搜索、Paste Stack、AI 操作与同步的剪贴板历史",
        typeText: "文本",
        typeRich: "富文本",
        typeLink: "链接",
        typeImage: "图片",
        typeFile: "文件",
        ok: "好",
        cancel: "取消",
        clear: "清空",
        paste: "粘贴",
        copy: "复制",
        delete: "删除",
        rename: "重命名",
        color: "颜色",
        preview: "预览",
        editEllipsis: "编辑…",
        editTitle: "编辑",
        save: "保存",
        editSaveHelp: "保存（⌘S）",
        editRichNote: "保存后只保留文字，原有格式会去掉",
        revealInFinder: "在访达中显示",
        openInBrowser: "在浏览器中打开",
        retry: "重试",
        stop: "停止",
        pause: "暂停",
        unlimited: "不限",
        listSeparator: "、",
        justNow: "刚刚",
        charactersFormat: "%d 个字符",
        filesFormat: "%d 个文件",
        moreFilesFormat: "还有 %d 个…",
        fileMissing: "文件已移动或删除",
        copied: "已复制",
        saveFailed: "保存失败",
        savedAsNewItem: "已存为新条目",
        historyTab: "剪贴板",
        searchHelp: "搜索（直接输入即可）",
        searchPlaceholder: "搜索…",
        pausedHelp: "已暂停记录",
        deletePinboard: "删除分类（条目保留在历史中）",
        newPinboard: "新建分类",
        untitledPinboard: "未命名",
        nextColorHelp: "点击切换颜色",
        typeFilter: "类型",
        allTypes: "全部类型",
        sourceAppFilter: "来源应用",
        allApps: "全部应用",
        clearFilters: "清除过滤",
        filterHelp: "过滤",
        pauseRecording: "暂停记录",
        autoPaste: "选择后自动粘贴",
        clearHistoryEllipsis: "清空历史…",
        settingsEllipsis: "设置…",
        syncErrorHelpFormat: "同步出错：%@\n点击重试（⌘R）",
        syncing: "正在同步…",
        lastSyncFormat: "上次同步：%@",
        neverSynced: "尚未同步",
        syncNowHelpFormat: "立即同步（⌘R）\n%@",
        pasteToFormat: "粘贴到 %@",
        pasteAsPlainText: "粘贴为纯文本",
        cleanAndPaste: "清洗后粘贴",
        cleanTrim: "去除首尾空白",
        cleanCollapseBlankLines: "去除多余空行",
        cleanJoinLines: "合并为一行",
        cleanMarkdown: "转为 Markdown",
        aiActions: "AI 操作",
        aiPolish: "润色",
        aiSummarize: "总结",
        aiTranslate: "翻译",
        aiKeyPoints: "提取要点",
        aiExplain: "解释",
        aiCustom: "自定义",
        aiCustomEllipsis: "自定义要求…",
        pinToBoard: "固定到分类",
        noPinboardsYet: "还没有分类，点击顶部 + 新建",
        removeFromBoard: "从分类中移除",
        noMatches: "没有找到匹配的内容",
        emptyPinboard: "右键卡片 →「固定到分类」把条目放进来",
        emptyHistory: "复制点什么，它就会出现在这里",
        editTitleHelp: "点击编辑标题",
        clearHistoryTitle: "清空剪贴板历史？",
        clearHistoryMessage: "已固定到分类中的条目会保留。此操作无法撤销。",
        previewCloseHint: "空格 / Esc 关闭",
        previewTruncatedFormat: "…内容过长，仅显示前 %d 个字符",
        previewFileMissing: "文件已移动或删除，无法预览",
        stackTitle: "Paste Stack",
        stackHelp: "复制的内容会依次进入列表；在任意应用按 ⌘V 依次粘贴。⌘ 点击可多选并合并为一段文本，右键可移除或清空。",
        closeStack: "关闭 Paste Stack",
        stackNeedsAccessibility: "未授予辅助功能权限：点击条目复制到剪贴板",
        deselect: "取消选择",
        selectWithCommand: "选择（⌘ 点击）",
        selectAll: "全选",
        removeFromList: "从列表中移除",
        clearList: "清空列表",
        stackEmpty: "复制的内容会依次出现在这里",
        selectedCountFormat: "已选 %d 项",
        separator: "分隔",
        separatorHelp: "合并时条目之间的分隔方式",
        separatorNewline: "换行",
        separatorBlankLine: "空一行",
        separatorSpace: "空格",
        separatorComma: "逗号",
        separatorNone: "直接拼接",
        merge: "合并",
        mergeHelp: "按列表顺序合并为一段文本，替换选中的条目，并存入剪贴板历史",
        orderFirstFirstHelp: "正序：先复制的先粘贴（先进先出）。点击切换为倒序",
        orderLastFirstHelp: "倒序：后复制的先粘贴（后进先出）。点击切换为正序",
        fromAppFormat: "来自 %@",
        aiTitleFormat: "AI %@",
        aiGenerating: "生成中…",
        closeEscapeHelp: "关闭（Esc）",
        aiCustomPlaceholder: "输入处理要求，如「改成正式的邮件语气」「写成三条朋友圈文案」",
        aiRun: "执行",
        aiInputTruncatedFormat: "原文较长，只处理了前 %d 个字符",
        aiOutputTruncated: "输出达到长度上限，后面的内容被截断",
        aiThinking: "正在思考…",
        aiCustomHint: "在上方输入要求，按 ↩ 开始",
        openAISettings: "打开 AI 设置",
        aiDisclaimer: "AI 生成的内容可能有误，使用前请核对",
        aiStopHelp: "停止生成（Esc 或 ⌘.）",
        regenerate: "重新生成",
        saveAsNewItem: "存为新条目",
        aiSaveHelp: "保存到剪贴板历史（⌘S）",
        aiPasteHelp: "粘贴到原来的应用（⌘↩）",
        aiImageHasNoText: "这张图片还没有识别出文字",
        aiItemHasNoText: "这条内容没有可处理的文字",
        providerCompatible: "OpenAI 兼容",
        syncUploadedFormat: "上传 %d 项",
        syncInsertedFormat: "新增 %d 条",
        syncUpdatedFormat: "更新 %d 条",
        syncDeletedFormat: "删除 %d 条",
        syncMissingImagesFormat: "%d 张图片缺少文件",
        syncUpToDateFormat: "已是最新（%d 台其他设备）",
        syncSummaryFormat: "%1$@（%2$d 台其他设备）",
        syncStoppedFormat: "%1$@（已连续失败 %2$d 次，自动同步已暂停，点击「立即同步」恢复）",
        invalidServerURL: "服务器地址无效，需要包含协议，如 https://192.168.1.10:5006/",
        iCloudMissingTitle: "未找到 iCloud 云盘",
        iCloudMissingMessage: "请在「系统设置 → Apple 账户 → iCloud」中开启 iCloud 云盘后重试。",
        backingUpToICloud: "正在备份到 iCloud 云盘…",
        backedUpToICloudFormat: "已备份 %d 条到 iCloud 云盘",
        backupDoneTitle: "备份完成",
        backupFailedTitle: "备份失败",
        exportPanelTitle: "导出剪贴板备份",
        exportOnlyPinned: "只导出分类中的条目",
        exporting: "正在导出…",
        exportedFormat: "已导出 %1$d 条到 %2$@",
        exportDoneTitle: "导出完成",
        exportFailedTitle: "导出失败",
        importPanelTitle: "导入剪贴板备份",
        backupUnreadableTitle: "无法读取备份",
        importConfirmFormat: "导入 %d 条剪贴板记录？",
        importConfirmDetailFormat: "备份导出于 %@。\n导入是合并：本地已有的相同内容会跳过，分类按名称对应，不会删除任何现有数据。",
        importButton: "导入",
        importing: "正在导入…",
        importSummaryFormat: "新增 %1$d 条，跳过已存在的 %2$d 条",
        importPinboardsFormat: "，新建分类 %d 个",
        importMissingFilesFormat: "。\n有 %d 张图片在备份中缺少文件，未能导入",
        importDoneTitle: "导入完成",
        importFailedTitle: "导入失败",
        progressOfFormat: "%1$@ %2$d / %3$d",
        progressProcessedFormat: "%1$@ 已处理 %2$d 条",
        importFromPaste: "从 Paste 导入",
        pasteUnreadableTitle: "无法读取 Paste 的数据",
        pasteUnreadableDetailFormat: "%@\n\n如果已安装 Paste，请点「选择文件夹…」，选中 Paste 的数据文件夹（一般位于：资源库 → Containers → Paste → Data → Library → Application Support → Paste）。由你主动选择的文件夹，系统会允许 Vorssaint 读取。",
        chooseFolder: "选择文件夹…",
        choosePasteFolderMessage: "选择包含 db.sqlite 的 Paste 数据文件夹",
        pasteEmptyTitle: "Paste 中没有可导入的记录",
        pasteResumeFormat: "继续上次未完成的导入（约剩 %1$d / %2$d 条）",
        pasteConfirmFormat: "从 Paste 导入 %d 条记录？",
        pasteTimeRangeFormat: "时间范围：%1$@ 至 %2$@。",
        pastePinboardsFormat: "分类 %d 个。",
        pasteMergeExplanation: "导入只做合并：已有的相同内容会保留原样（仅补上缺少的分类和标题），不会修改或删除 Vorssaint 与 Paste 中的任何数据。导入在后台进行，可随时暂停，之后可以继续。",
        startImport: "开始导入",
        importImages: "导入图片",
        itemSizeLimit: "单条大小上限",
        syncImported: "同步导入的内容到其他设备",
        syncImportedNote: "关闭时导入的内容只保存在本机。同步服务有流量限制时（如坚果云免费版每月上传 1GB），大量导入建议关闭。",
        pasteImportRunning: "正在从 Paste 导入…",
        pasteImportPausing: "正在暂停（等待当前批次保存）…",
        statNew: "新增",
        statExisting: "已存在",
        statSkipped: "跳过",
        statFailed: "失败",
        pasteImportKeepWorking: "可以继续使用其他功能。暂停后再次导入会从中断处继续。",
        preparing: "准备中…",
        secondsFormat: "%d 秒",
        minutesFormat: "%d 分钟",
        importSpeedFormat: "约 %1$d 条/秒 · 剩余约 %2$@",
        pasteResultFormat: "新增 %1$d 条，已存在 %2$d 条（已合并）",
        pasteSkippedFormat: "跳过：%@",
        pasteSkippedTooLargeFormat: "超过大小上限 %d 条",
        pasteSkippedImagesFormat: "图片 %d 条",
        pasteSkippedUnsupportedFormat: "不支持的内容 %d 条（如未下载完成的文件、浏览器内部数据）",
        pasteFailedFormat: "读取失败 %d 条",
        pastePausedNote: "已暂停。再次选择「从 Paste 导入」可从中断处继续。",
        pasteDoneTitle: "导入完成",
        pastePausedTitle: "导入已暂停",
        pasteInterruptedTitle: "导入中断",
        pasteInterruptedFormat: "%@\n\n已导入的部分已保存。再次选择「从 Paste 导入」可从中断处继续。",
        errorWebDAVUnauthorized: "账号或密码不正确（坚果云等服务需使用第三方应用密码，而不是登录密码）",
        errorWebDAVForbidden: "服务器拒绝访问：请检查账号对同步目录是否有读写权限；也可能是访问过于频繁，稍后会自动重试",
        errorWebDAVRateLimited: "服务器暂时拒绝访问（访问过于频繁或服务暂不可用），稍后会自动重试",
        errorHTTPFormat: "服务器返回错误 %1$d（%2$@）",
        errorNetworkFormat: "网络错误：%@",
        errorBadResponse: "服务器响应无法识别",
        errorPassphraseRequired: "云端数据已加密，请填写与其他设备相同的同步密码",
        errorWrongPassphrase: "同步密码不正确，请与其他设备保持一致",
        errorRemoteNotEncrypted: "云端数据未加密：请清空同步密码，或在设置中重置云端数据后再启用加密",
        errorUnsupportedFormatFormat: "云端数据来自更新的版本（格式 v%d），请先升级",
        errorCorruptFormat: "云端数据损坏：%@",
        errorAIKeyMissing: "还没有设置 API Key，请在「设置 → 剪贴板 → AI」中填写",
        errorAIModelMissing: "还没有设置模型，请在「设置 → 剪贴板 → AI」中填写",
        errorAIInvalidURL: "服务地址无效",
        errorAIHTTPFormat: "%1$@（HTTP %2$d）",
        errorAIHTTPDetailFormat: "%1$@（HTTP %2$d）：%3$@",
        errorAI401: "API Key 无效",
        errorAI403: "没有权限",
        errorAI404: "接口地址或模型不存在",
        errorAI413: "内容太长",
        errorAI429: "请求过于频繁或额度不足，请稍后再试",
        errorAIUnavailable: "服务暂时不可用，请稍后再试",
        errorAIRequestFailed: "请求失败",
        errorAIRefused: "模型拒绝处理这段内容",
        errorAIServerFormat: "服务端出错：%@",
        errorAIEmpty: "模型没有返回内容",
        errorBackupInvalidFormat: "不是有效的剪贴板备份：%@",
        errorBackupToolFormat: "压缩 / 解压失败：%@",
        errorPasteNotFoundFormat: "没有找到 Paste 的数据库：%@",
        errorPasteNotReadableFormat: "无法读取 Paste 的数据库：%@",
        errorPasteUnsupportedFormat: "不支持的 Paste 数据格式：%@")

    static let ja = ClipNoteStrings(
        id: "ja",
        title: "クリップボード",
        hubDescription: "ピンボード、全文検索、Paste Stack、AI 操作、同期に対応したクリップボード履歴",
        typeText: "テキスト",
        typeRich: "リッチテキスト",
        typeLink: "リンク",
        typeImage: "画像",
        typeFile: "ファイル",
        ok: "OK",
        cancel: "キャンセル",
        clear: "消去",
        paste: "ペースト",
        copy: "コピー",
        delete: "削除",
        rename: "名前を変更",
        color: "カラー",
        preview: "プレビュー",
        editEllipsis: "編集…",
        editTitle: "編集",
        save: "保存",
        editSaveHelp: "保存（⌘S）",
        editRichNote: "保存するとテキストだけが残り、書式は失われます",
        revealInFinder: "Finder に表示",
        openInBrowser: "ブラウザで開く",
        retry: "再試行",
        stop: "停止",
        pause: "一時停止",
        unlimited: "無制限",
        listSeparator: "、",
        justNow: "たった今",
        charactersFormat: "%d 文字",
        filesFormat: "%d 個のファイル",
        moreFilesFormat: "他 %d 個…",
        fileMissing: "ファイルは移動または削除されました",
        copied: "コピーしました",
        saveFailed: "保存できませんでした",
        savedAsNewItem: "新しい項目として保存しました",
        historyTab: "クリップボード",
        searchHelp: "検索（そのまま入力できます）",
        searchPlaceholder: "検索…",
        pausedHelp: "記録を一時停止中",
        deletePinboard: "ピンボードを削除（項目は履歴に残ります）",
        newPinboard: "新規ピンボード",
        untitledPinboard: "名称未設定",
        nextColorHelp: "クリックで色を変更",
        typeFilter: "種類",
        allTypes: "すべての種類",
        sourceAppFilter: "コピー元のアプリ",
        allApps: "すべてのアプリ",
        clearFilters: "フィルタを解除",
        filterHelp: "フィルタ",
        pauseRecording: "記録を一時停止",
        autoPaste: "選択後に自動でペースト",
        clearHistoryEllipsis: "履歴を消去…",
        settingsEllipsis: "設定…",
        syncErrorHelpFormat: "同期エラー：%@\nクリックで再試行（⌘R）",
        syncing: "同期中…",
        lastSyncFormat: "前回の同期：%@",
        neverSynced: "まだ同期していません",
        syncNowHelpFormat: "今すぐ同期（⌘R）\n%@",
        pasteToFormat: "%@ にペースト",
        pasteAsPlainText: "プレーンテキストとしてペースト",
        cleanAndPaste: "整形してペースト",
        cleanTrim: "前後の空白を削除",
        cleanCollapseBlankLines: "余分な空行を削除",
        cleanJoinLines: "1 行にまとめる",
        cleanMarkdown: "Markdown に変換",
        aiActions: "AI 操作",
        aiPolish: "推敲",
        aiSummarize: "要約",
        aiTranslate: "翻訳",
        aiKeyPoints: "要点を抽出",
        aiExplain: "説明",
        aiCustom: "カスタム",
        aiCustomEllipsis: "カスタム指示…",
        pinToBoard: "ピンボードに追加",
        noPinboardsYet: "ピンボードはまだありません。上部の + で作成します",
        removeFromBoard: "ピンボードから外す",
        noMatches: "一致する項目はありません",
        emptyPinboard: "カードを右クリック →「ピンボードに追加」でここに入ります",
        emptyHistory: "何かをコピーするとここに表示されます",
        editTitleHelp: "クリックしてタイトルを編集",
        clearHistoryTitle: "クリップボードの履歴を消去しますか？",
        clearHistoryMessage: "ピンボードの項目は残ります。この操作は取り消せません。",
        previewCloseHint: "スペース / Esc で閉じる",
        previewTruncatedFormat: "…長すぎるため最初の %d 文字のみ表示しています",
        previewFileMissing: "ファイルが移動または削除されたためプレビューできません",
        stackTitle: "Paste Stack",
        stackHelp: "コピーした内容が順にリストに入り、どのアプリでも ⌘V で順番にペーストできます。⌘ クリックで複数選択して結合、右クリックで削除や消去ができます。",
        closeStack: "Paste Stack を閉じる",
        stackNeedsAccessibility: "アクセシビリティが未許可：行をクリックするとコピーします",
        deselect: "選択解除",
        selectWithCommand: "選択（⌘ クリック）",
        selectAll: "すべてを選択",
        removeFromList: "リストから削除",
        clearList: "リストを消去",
        stackEmpty: "コピーした内容が順にここに並びます",
        selectedCountFormat: "%d 件選択",
        separator: "区切り",
        separatorHelp: "結合する行の区切り方",
        separatorNewline: "改行",
        separatorBlankLine: "空行",
        separatorSpace: "スペース",
        separatorComma: "読点",
        separatorNone: "なし",
        merge: "結合",
        mergeHelp: "リスト順に 1 つのテキストに結合して選択行と置き換え、履歴にも保存します",
        orderFirstFirstHelp: "先入れ先出し：先にコピーしたものから。クリックで後入れ先出しに切り替え",
        orderLastFirstHelp: "後入れ先出し：最後にコピーしたものから。クリックで先入れ先出しに切り替え",
        fromAppFormat: "%@ から",
        aiTitleFormat: "AI %@",
        aiGenerating: "生成中…",
        closeEscapeHelp: "閉じる（Esc）",
        aiCustomPlaceholder: "指示を入力（例：「正式なメールの文体にする」）",
        aiRun: "実行",
        aiInputTruncatedFormat: "元の文章が長いため、最初の %d 文字のみ処理しました",
        aiOutputTruncated: "出力が上限に達したため、続きは省略されました",
        aiThinking: "考え中…",
        aiCustomHint: "上に指示を入力して ↩ を押します",
        openAISettings: "AI 設定を開く",
        aiDisclaimer: "AI の生成内容には誤りがある場合があります。使用前に確認してください",
        aiStopHelp: "生成を停止（Esc または ⌘.）",
        regenerate: "再生成",
        saveAsNewItem: "項目として保存",
        aiSaveHelp: "クリップボード履歴に保存（⌘S）",
        aiPasteHelp: "元のアプリにペースト（⌘↩）",
        aiImageHasNoText: "この画像からはまだ文字が認識されていません",
        aiItemHasNoText: "この項目には処理できるテキストがありません",
        providerCompatible: "OpenAI 互換",
        syncUploadedFormat: "%d 件アップロード",
        syncInsertedFormat: "%d 件追加",
        syncUpdatedFormat: "%d 件更新",
        syncDeletedFormat: "%d 件削除",
        syncMissingImagesFormat: "%d 枚の画像のファイルが見つかりません",
        syncUpToDateFormat: "最新です（他のデバイス %d 台）",
        syncSummaryFormat: "%1$@（他のデバイス %2$d 台）",
        syncStoppedFormat: "%1$@（%2$d 回連続で失敗したため自動同期を停止しました。「今すぐ同期」で再開します）",
        invalidServerURL: "サーバのアドレスが無効です。https://192.168.1.10:5006/ のようにスキームを含めてください",
        iCloudMissingTitle: "iCloud Drive が見つかりません",
        iCloudMissingMessage: "「システム設定」→「Apple アカウント」→「iCloud」で iCloud Drive をオンにしてから、もう一度お試しください。",
        backingUpToICloud: "iCloud Drive にバックアップ中…",
        backedUpToICloudFormat: "%d 件を iCloud Drive にバックアップしました",
        backupDoneTitle: "バックアップ完了",
        backupFailedTitle: "バックアップに失敗しました",
        exportPanelTitle: "クリップボードのバックアップを書き出す",
        exportOnlyPinned: "ピンボードの項目のみ",
        exporting: "書き出し中…",
        exportedFormat: "%1$d 件を %2$@ に書き出しました",
        exportDoneTitle: "書き出し完了",
        exportFailedTitle: "書き出しに失敗しました",
        importPanelTitle: "クリップボードのバックアップを読み込む",
        backupUnreadableTitle: "バックアップを読み込めません",
        importConfirmFormat: "%d 件のクリップボード項目を読み込みますか？",
        importConfirmDetailFormat: "%@ に書き出されたバックアップです。\n読み込みは統合です。既にある内容はスキップされ、ピンボードは名前で対応し、既存のデータは削除されません。",
        importButton: "読み込む",
        importing: "読み込み中…",
        importSummaryFormat: "%1$d 件を追加、既存の %2$d 件をスキップ",
        importPinboardsFormat: "、ピンボードを %d 個作成",
        importMissingFilesFormat: "。\n%d 枚の画像はバックアップにファイルがなく、読み込めませんでした",
        importDoneTitle: "読み込み完了",
        importFailedTitle: "読み込みに失敗しました",
        progressOfFormat: "%1$@ %2$d / %3$d",
        progressProcessedFormat: "%1$@ %2$d 件処理済み",
        importFromPaste: "Paste から読み込む",
        pasteUnreadableTitle: "Paste のデータを読み込めません",
        pasteUnreadableDetailFormat: "%@\n\nPaste がインストールされている場合は「フォルダを選択…」をクリックし、Paste のデータフォルダ（通常は ライブラリ → Containers → Paste → Data → Library → Application Support → Paste）を選んでください。自分で選んだフォルダは Vorssaint が読み取れるようになります。",
        chooseFolder: "フォルダを選択…",
        choosePasteFolderMessage: "db.sqlite を含む Paste のデータフォルダを選択",
        pasteEmptyTitle: "Paste に読み込める項目はありません",
        pasteResumeFormat: "前回の途中から続ける（残り約 %1$d / %2$d 件）",
        pasteConfirmFormat: "Paste から %d 件を読み込みますか？",
        pasteTimeRangeFormat: "期間：%1$@〜%2$@。",
        pastePinboardsFormat: "ピンボード %d 個。",
        pasteMergeExplanation: "読み込みは統合のみです。既にある内容はそのまま残り（足りないピンボードとタイトルだけを補います）、Vorssaint と Paste のデータは変更も削除もされません。バックグラウンドで実行され、いつでも一時停止して後で再開できます。",
        startImport: "読み込みを開始",
        importImages: "画像を読み込む",
        itemSizeLimit: "1 項目のサイズ上限",
        syncImported: "読み込んだ項目を他のデバイスに同期",
        syncImportedNote: "オフにすると読み込んだ項目はこの Mac にのみ保存されます。転送量に制限のあるサービス（坚果云の無料プランは月 1GB のアップロード）では、大量に読み込むときはオフをおすすめします。",
        pasteImportRunning: "Paste から読み込み中…",
        pasteImportPausing: "一時停止中（現在のバッチを保存しています）…",
        statNew: "追加",
        statExisting: "既存",
        statSkipped: "スキップ",
        statFailed: "失敗",
        pasteImportKeepWorking: "そのまま作業を続けられます。一時停止後にもう一度読み込むと中断したところから続きます。",
        preparing: "準備中…",
        secondsFormat: "%d 秒",
        minutesFormat: "%d 分",
        importSpeedFormat: "約 %1$d 件/秒 · 残り約 %2$@",
        pasteResultFormat: "%1$d 件を追加、既存 %2$d 件（統合済み）",
        pasteSkippedFormat: "スキップ：%@",
        pasteSkippedTooLargeFormat: "サイズ上限超過 %d 件",
        pasteSkippedImagesFormat: "画像 %d 件",
        pasteSkippedUnsupportedFormat: "未対応 %d 件（ダウンロードが終わっていないファイル、ブラウザ内部のデータなど）",
        pasteFailedFormat: "読み取り失敗 %d 件",
        pastePausedNote: "一時停止しました。もう一度「Paste から読み込む」を選ぶと中断したところから続けます。",
        pasteDoneTitle: "読み込み完了",
        pastePausedTitle: "読み込みを一時停止しました",
        pasteInterruptedTitle: "読み込みが中断されました",
        pasteInterruptedFormat: "%@\n\n読み込んだ分は保存されています。もう一度「Paste から読み込む」を選ぶと中断したところから続けます。",
        errorWebDAVUnauthorized: "アカウントまたはパスワードが正しくありません（坚果云などはログインパスワードではなくアプリパスワードが必要です）",
        errorWebDAVForbidden: "サーバがアクセスを拒否しました。アカウントに同期フォルダの読み書き権限があるか確認してください。アクセス過多の場合もあり、しばらくして自動で再試行します",
        errorWebDAVRateLimited: "サーバが一時的にアクセスを拒否しています（アクセス過多または一時的に利用不可）。しばらくして自動で再試行します",
        errorHTTPFormat: "サーバがエラー %1$d を返しました（%2$@）",
        errorNetworkFormat: "ネットワークエラー：%@",
        errorBadResponse: "サーバの応答を認識できません",
        errorPassphraseRequired: "同期データは暗号化されています。他のデバイスと同じ同期パスワードを入力してください",
        errorWrongPassphrase: "同期パスワードが正しくありません。他のデバイスと同じものにしてください",
        errorRemoteNotEncrypted: "同期データは暗号化されていません。同期パスワードを空にするか、サーバ上のデータをリセットしてから暗号化を有効にしてください",
        errorUnsupportedFormatFormat: "同期データは新しいバージョンのものです（形式 v%d）。先にアップデートしてください",
        errorCorruptFormat: "同期データが破損しています：%@",
        errorAIKeyMissing: "API キーがまだありません。「設定」→「クリップボード」→「AI」で入力してください",
        errorAIModelMissing: "モデルがまだ設定されていません。「設定」→「クリップボード」→「AI」で入力してください",
        errorAIInvalidURL: "サービスのアドレスが無効です",
        errorAIHTTPFormat: "%1$@（HTTP %2$d）",
        errorAIHTTPDetailFormat: "%1$@（HTTP %2$d）：%3$@",
        errorAI401: "API キーが無効です",
        errorAI403: "権限がありません",
        errorAI404: "エンドポイントまたはモデルが存在しません",
        errorAI413: "内容が長すぎます",
        errorAI429: "リクエストが多すぎるか、利用枠が不足しています。しばらくしてからお試しください",
        errorAIUnavailable: "サービスは一時的に利用できません。しばらくしてからお試しください",
        errorAIRequestFailed: "リクエストに失敗しました",
        errorAIRefused: "モデルがこの内容の処理を拒否しました",
        errorAIServerFormat: "サービスでエラーが発生しました：%@",
        errorAIEmpty: "モデルから応答がありませんでした",
        errorBackupInvalidFormat: "有効なクリップボードのバックアップではありません：%@",
        errorBackupToolFormat: "圧縮または展開に失敗しました：%@",
        errorPasteNotFoundFormat: "Paste のデータベースが見つかりません：%@",
        errorPasteNotReadableFormat: "Paste のデータベースを読み込めません：%@",
        errorPasteUnsupportedFormat: "未対応の Paste データ形式：%@")

    static let ko = ClipNoteStrings(
        id: "ko",
        title: "클립보드",
        hubDescription: "핀보드, 전체 텍스트 검색, Paste Stack, AI 작업, 동기화를 지원하는 클립보드 기록",
        typeText: "텍스트",
        typeRich: "서식 있는 텍스트",
        typeLink: "링크",
        typeImage: "이미지",
        typeFile: "파일",
        ok: "확인",
        cancel: "취소",
        clear: "지우기",
        paste: "붙여넣기",
        copy: "복사",
        delete: "삭제",
        rename: "이름 변경",
        color: "색상",
        preview: "미리보기",
        editEllipsis: "편집…",
        editTitle: "편집",
        save: "저장",
        editSaveHelp: "저장 (⌘S)",
        editRichNote: "저장하면 텍스트만 남고 서식은 사라집니다",
        revealInFinder: "Finder에서 보기",
        openInBrowser: "브라우저에서 열기",
        retry: "다시 시도",
        stop: "중지",
        pause: "일시 정지",
        unlimited: "제한 없음",
        listSeparator: ", ",
        justNow: "방금",
        charactersFormat: "%d자",
        filesFormat: "파일 %d개",
        moreFilesFormat: "외 %d개…",
        fileMissing: "파일이 이동되었거나 삭제됨",
        copied: "복사됨",
        saveFailed: "저장하지 못함",
        savedAsNewItem: "새 항목으로 저장됨",
        historyTab: "클립보드",
        searchHelp: "검색 (바로 입력하세요)",
        searchPlaceholder: "검색…",
        pausedHelp: "기록 일시 정지됨",
        deletePinboard: "핀보드 삭제(항목은 기록에 남음)",
        newPinboard: "새 핀보드",
        untitledPinboard: "제목 없음",
        nextColorHelp: "클릭하여 색상 변경",
        typeFilter: "유형",
        allTypes: "모든 유형",
        sourceAppFilter: "출처 앱",
        allApps: "모든 앱",
        clearFilters: "필터 지우기",
        filterHelp: "필터",
        pauseRecording: "기록 일시 정지",
        autoPaste: "선택 후 자동 붙여넣기",
        clearHistoryEllipsis: "기록 지우기…",
        settingsEllipsis: "설정…",
        syncErrorHelpFormat: "동기화 오류: %@\n클릭하여 다시 시도 (⌘R)",
        syncing: "동기화 중…",
        lastSyncFormat: "마지막 동기화: %@",
        neverSynced: "아직 동기화하지 않음",
        syncNowHelpFormat: "지금 동기화 (⌘R)\n%@",
        pasteToFormat: "%@에 붙여넣기",
        pasteAsPlainText: "일반 텍스트로 붙여넣기",
        cleanAndPaste: "정리 후 붙여넣기",
        cleanTrim: "앞뒤 공백 제거",
        cleanCollapseBlankLines: "불필요한 빈 줄 제거",
        cleanJoinLines: "한 줄로 합치기",
        cleanMarkdown: "Markdown으로 변환",
        aiActions: "AI 작업",
        aiPolish: "다듬기",
        aiSummarize: "요약",
        aiTranslate: "번역",
        aiKeyPoints: "핵심 추출",
        aiExplain: "설명",
        aiCustom: "사용자 지정",
        aiCustomEllipsis: "사용자 지정 요청…",
        pinToBoard: "핀보드에 고정",
        noPinboardsYet: "아직 핀보드가 없습니다. 상단의 +를 눌러 만드세요",
        removeFromBoard: "핀보드에서 제거",
        noMatches: "일치하는 항목 없음",
        emptyPinboard: "카드를 오른쪽 클릭 → ‘핀보드에 고정’으로 여기에 추가하세요",
        emptyHistory: "무언가를 복사하면 여기에 표시됩니다",
        editTitleHelp: "클릭하여 제목 편집",
        clearHistoryTitle: "클립보드 기록을 지울까요?",
        clearHistoryMessage: "핀보드의 항목은 유지됩니다. 이 작업은 되돌릴 수 없습니다.",
        previewCloseHint: "Space / Esc로 닫기",
        previewTruncatedFormat: "…너무 길어 처음 %d자만 표시합니다",
        previewFileMissing: "파일이 이동되었거나 삭제되어 미리 볼 수 없습니다",
        stackTitle: "Paste Stack",
        stackHelp: "복사한 내용이 순서대로 목록에 쌓이고, 어떤 앱에서든 ⌘V로 차례로 붙여넣습니다. ⌘ 클릭으로 여러 개를 선택해 합치고, 오른쪽 클릭으로 제거하거나 비울 수 있습니다.",
        closeStack: "Paste Stack 닫기",
        stackNeedsAccessibility: "손쉬운 사용 권한 없음: 행을 클릭하면 복사됩니다",
        deselect: "선택 해제",
        selectWithCommand: "선택 (⌘ 클릭)",
        selectAll: "모두 선택",
        removeFromList: "목록에서 제거",
        clearList: "목록 비우기",
        stackEmpty: "복사한 내용이 여기에 차례로 쌓입니다",
        selectedCountFormat: "%d개 선택됨",
        separator: "구분자",
        separatorHelp: "합칠 때 행 사이의 구분 방식",
        separatorNewline: "줄바꿈",
        separatorBlankLine: "빈 줄",
        separatorSpace: "공백",
        separatorComma: "쉼표",
        separatorNone: "없음",
        merge: "합치기",
        mergeHelp: "목록 순서대로 하나의 텍스트로 합쳐 선택한 행을 대체하고 기록에도 저장합니다",
        orderFirstFirstHelp: "선입선출: 먼저 복사한 것부터. 클릭하면 후입선출로 전환",
        orderLastFirstHelp: "후입선출: 마지막에 복사한 것부터. 클릭하면 선입선출로 전환",
        fromAppFormat: "%@에서",
        aiTitleFormat: "AI %@",
        aiGenerating: "생성 중…",
        closeEscapeHelp: "닫기 (Esc)",
        aiCustomPlaceholder: "요청을 입력하세요 (예: ‘격식 있는 이메일로 바꿔 줘’)",
        aiRun: "실행",
        aiInputTruncatedFormat: "원문이 길어 처음 %d자만 처리했습니다",
        aiOutputTruncated: "출력이 길이 제한에 도달해 뒷부분이 잘렸습니다",
        aiThinking: "생각 중…",
        aiCustomHint: "위에 요청을 입력하고 ↩를 누르세요",
        openAISettings: "AI 설정 열기",
        aiDisclaimer: "AI가 생성한 내용은 틀릴 수 있습니다. 사용 전에 확인하세요",
        aiStopHelp: "생성 중지 (Esc 또는 ⌘.)",
        regenerate: "다시 생성",
        saveAsNewItem: "항목으로 저장",
        aiSaveHelp: "클립보드 기록에 저장 (⌘S)",
        aiPasteHelp: "원래 앱에 붙여넣기 (⌘↩)",
        aiImageHasNoText: "이 이미지에서 아직 인식된 텍스트가 없습니다",
        aiItemHasNoText: "이 항목에는 처리할 텍스트가 없습니다",
        providerCompatible: "OpenAI 호환",
        syncUploadedFormat: "%d개 업로드",
        syncInsertedFormat: "%d개 추가",
        syncUpdatedFormat: "%d개 업데이트",
        syncDeletedFormat: "%d개 삭제",
        syncMissingImagesFormat: "이미지 %d개의 파일 없음",
        syncUpToDateFormat: "최신 상태 (다른 기기 %d대)",
        syncSummaryFormat: "%1$@ (다른 기기 %2$d대)",
        syncStoppedFormat: "%1$@ (%2$d회 연속 실패하여 자동 동기화가 일시 정지됨. ‘지금 동기화’를 눌러 재개)",
        invalidServerURL: "서버 주소가 올바르지 않습니다. https://192.168.1.10:5006/처럼 스킴을 포함하세요",
        iCloudMissingTitle: "iCloud Drive를 찾을 수 없음",
        iCloudMissingMessage: "시스템 설정 → Apple 계정 → iCloud에서 iCloud Drive를 켠 후 다시 시도하세요.",
        backingUpToICloud: "iCloud Drive에 백업 중…",
        backedUpToICloudFormat: "%d개 항목을 iCloud Drive에 백업했습니다",
        backupDoneTitle: "백업 완료",
        backupFailedTitle: "백업 실패",
        exportPanelTitle: "클립보드 백업 내보내기",
        exportOnlyPinned: "핀보드 항목만",
        exporting: "내보내는 중…",
        exportedFormat: "%1$d개 항목을 %2$@(으)로 내보냈습니다",
        exportDoneTitle: "내보내기 완료",
        exportFailedTitle: "내보내기 실패",
        importPanelTitle: "클립보드 백업 가져오기",
        backupUnreadableTitle: "백업을 읽을 수 없음",
        importConfirmFormat: "클립보드 항목 %d개를 가져올까요?",
        importConfirmDetailFormat: "%@에 내보낸 백업입니다.\n가져오기는 병합입니다. 이미 있는 내용은 건너뛰고, 핀보드는 이름으로 맞추며, 기존 데이터는 삭제하지 않습니다.",
        importButton: "가져오기",
        importing: "가져오는 중…",
        importSummaryFormat: "%1$d개 추가, 이미 있는 %2$d개 건너뜀",
        importPinboardsFormat: ", 핀보드 %d개 생성",
        importMissingFilesFormat: ".\n이미지 %d개는 백업에 파일이 없어 가져오지 못했습니다",
        importDoneTitle: "가져오기 완료",
        importFailedTitle: "가져오기 실패",
        progressOfFormat: "%1$@ %2$d / %3$d",
        progressProcessedFormat: "%1$@ %2$d개 처리됨",
        importFromPaste: "Paste에서 가져오기",
        pasteUnreadableTitle: "Paste 데이터를 읽을 수 없음",
        pasteUnreadableDetailFormat: "%@\n\nPaste가 설치되어 있다면 ‘폴더 선택…’을 눌러 Paste 데이터 폴더(보통 라이브러리 → Containers → Paste → Data → Library → Application Support → Paste)를 선택하세요. 직접 선택한 폴더는 Vorssaint가 읽을 수 있습니다.",
        chooseFolder: "폴더 선택…",
        choosePasteFolderMessage: "db.sqlite가 있는 Paste 데이터 폴더를 선택하세요",
        pasteEmptyTitle: "Paste에 가져올 항목이 없습니다",
        pasteResumeFormat: "이전 가져오기 이어서 진행 (약 %1$d / %2$d개 남음)",
        pasteConfirmFormat: "Paste에서 %d개 항목을 가져올까요?",
        pasteTimeRangeFormat: "기간: %1$@ ~ %2$@. ",
        pastePinboardsFormat: "핀보드 %d개.",
        pasteMergeExplanation: "가져오기는 병합만 합니다. 이미 있는 내용은 그대로 두고(빠진 핀보드와 제목만 채움), Vorssaint와 Paste의 데이터는 변경하거나 삭제하지 않습니다. 백그라운드에서 실행되며 언제든 일시 정지했다가 나중에 이어서 할 수 있습니다.",
        startImport: "가져오기 시작",
        importImages: "이미지 가져오기",
        itemSizeLimit: "항목당 크기 제한",
        syncImported: "가져온 항목을 다른 기기에 동기화",
        syncImportedNote: "끄면 가져온 항목이 이 Mac에만 저장됩니다. 전송량 제한이 있는 서비스(Jianguoyun 무료 요금제는 월 1GB 업로드)에서는 대량 가져오기 시 끄는 것이 좋습니다.",
        pasteImportRunning: "Paste에서 가져오는 중…",
        pasteImportPausing: "일시 정지 중(현재 배치를 저장하는 중)…",
        statNew: "추가",
        statExisting: "이미 있음",
        statSkipped: "건너뜀",
        statFailed: "실패",
        pasteImportKeepWorking: "계속 작업할 수 있습니다. 일시 정지 후 다시 가져오면 중단된 곳부터 이어집니다.",
        preparing: "준비 중…",
        secondsFormat: "%d초",
        minutesFormat: "%d분",
        importSpeedFormat: "초당 약 %1$d개 · 약 %2$@ 남음",
        pasteResultFormat: "%1$d개 추가, 이미 있음 %2$d개(병합됨)",
        pasteSkippedFormat: "건너뜀: %@",
        pasteSkippedTooLargeFormat: "크기 제한 초과 %d개",
        pasteSkippedImagesFormat: "이미지 %d개",
        pasteSkippedUnsupportedFormat: "지원하지 않는 내용 %d개(다운로드되지 않은 파일, 브라우저 내부 데이터 등)",
        pasteFailedFormat: "읽기 실패 %d개",
        pastePausedNote: "일시 정지됨. ‘Paste에서 가져오기’를 다시 선택하면 중단된 곳부터 이어집니다.",
        pasteDoneTitle: "가져오기 완료",
        pastePausedTitle: "가져오기 일시 정지됨",
        pasteInterruptedTitle: "가져오기 중단됨",
        pasteInterruptedFormat: "%@\n\n가져온 부분은 저장되었습니다. ‘Paste에서 가져오기’를 다시 선택하면 중단된 곳부터 이어집니다.",
        errorWebDAVUnauthorized: "계정 또는 암호가 올바르지 않습니다(Jianguoyun 등은 로그인 암호가 아닌 앱 암호가 필요합니다)",
        errorWebDAVForbidden: "서버가 접근을 거부했습니다. 계정에 동기화 폴더 읽기/쓰기 권한이 있는지 확인하세요. 요청이 너무 잦은 경우일 수도 있으며 잠시 후 자동으로 다시 시도합니다",
        errorWebDAVRateLimited: "서버가 일시적으로 접근을 거부하고 있습니다(요청 과다 또는 일시적 사용 불가). 잠시 후 자동으로 다시 시도합니다",
        errorHTTPFormat: "서버가 오류 %1$d을(를) 반환했습니다(%2$@)",
        errorNetworkFormat: "네트워크 오류: %@",
        errorBadResponse: "서버 응답을 인식할 수 없습니다",
        errorPassphraseRequired: "동기화 데이터가 암호화되어 있습니다. 다른 기기와 같은 동기화 암호를 입력하세요",
        errorWrongPassphrase: "동기화 암호가 올바르지 않습니다. 다른 기기와 같게 맞추세요",
        errorRemoteNotEncrypted: "동기화 데이터가 암호화되어 있지 않습니다. 동기화 암호를 비우거나 서버 데이터를 초기화한 후 암호화를 켜세요",
        errorUnsupportedFormatFormat: "동기화 데이터가 더 새로운 버전의 것입니다(형식 v%d). 먼저 업데이트하세요",
        errorCorruptFormat: "동기화 데이터가 손상되었습니다: %@",
        errorAIKeyMissing: "API 키가 아직 없습니다. 설정 → 클립보드 → AI에서 입력하세요",
        errorAIModelMissing: "모델이 아직 없습니다. 설정 → 클립보드 → AI에서 입력하세요",
        errorAIInvalidURL: "서비스 주소가 올바르지 않습니다",
        errorAIHTTPFormat: "%1$@ (HTTP %2$d)",
        errorAIHTTPDetailFormat: "%1$@ (HTTP %2$d): %3$@",
        errorAI401: "API 키가 올바르지 않습니다",
        errorAI403: "권한이 없습니다",
        errorAI404: "엔드포인트 또는 모델이 없습니다",
        errorAI413: "내용이 너무 깁니다",
        errorAI429: "요청이 너무 많거나 할당량이 부족합니다. 잠시 후 다시 시도하세요",
        errorAIUnavailable: "서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도하세요",
        errorAIRequestFailed: "요청 실패",
        errorAIRefused: "모델이 이 내용의 처리를 거부했습니다",
        errorAIServerFormat: "서비스 오류: %@",
        errorAIEmpty: "모델이 아무것도 반환하지 않았습니다",
        errorBackupInvalidFormat: "올바른 클립보드 백업이 아닙니다: %@",
        errorBackupToolFormat: "압축 또는 압축 해제 실패: %@",
        errorPasteNotFoundFormat: "Paste 데이터베이스를 찾을 수 없습니다: %@",
        errorPasteNotReadableFormat: "Paste 데이터베이스를 읽을 수 없습니다: %@",
        errorPasteUnsupportedFormat: "지원하지 않는 Paste 데이터 형식: %@")
}
