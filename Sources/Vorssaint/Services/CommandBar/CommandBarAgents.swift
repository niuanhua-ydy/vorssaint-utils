// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import os

/// Starts a coding agent in a terminal, in a folder picked from the bar. The
/// agents and folders are looked up away from the main thread and kept for a
/// moment, so the bar never waits on a shell or a disk to draw its rows.
enum CommandBarAgents {
    typealias Directory = CommandBarAgentsSupport.Directory

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "agents")
    private static let lock = NSLock()
    private static var installedPaths: [String: String] = [:]
    private static var loginPath: String?
    private static var askedLoginPath = false
    private static var detectedAt: Date?
    private static var detecting = false
    private static var history: (folders: [Directory], at: Date)?

    // MARK: - Agents on this Mac

    static var commands: [String: String] {
        CommandBarAgentsSupport.decodeCommands(UserDefaults.standard.string(forKey: DefaultsKey.commandBarAgentCommands))
    }

    static func command(for agent: CommandBarAgent) -> String {
        CommandBarAgentsSupport.command(for: agent, in: commands)
    }

    /// Where an agent's program was found the last time anyone looked.
    static func installedPath(for agent: CommandBarAgent) -> String? {
        lock.withLock { installedPaths[agent.id] }
    }

    /// The agents the person left on whose program is installed, as of the
    /// last look. Never waits on one.
    static func available() -> [CommandBarAgent] {
        let disabled = CommandBarAgentsSupport.disabledAgents(
            from: UserDefaults.standard.string(forKey: DefaultsKey.commandBarAgentDisabled) ?? "")
        let found = lock.withLock { installedPaths }
        return CommandBarAgentsSupport.presets.filter { !disabled.contains($0.id) && found[$0.id] != nil }
    }

    /// Looks for every agent's program again, at most once a minute unless
    /// forced. The login shell is asked for its PATH the first time, since an
    /// app opened from Finder only has the system folders on its own.
    /// `completion` runs on the main thread when what was found changed.
    static func refresh(force: Bool = false, completion: @escaping () -> Void = {}) {
        let start: Bool = lock.withLock {
            guard !detecting else { return false }
            if !force, let detectedAt, Date().timeIntervalSince(detectedAt) < 60 { return false }
            detecting = true
            return true
        }
        guard start else { return }
        let overrides = commands
        DispatchQueue.global(qos: .utility).async {
            let asked: String?? = lock.withLock { askedLoginPath ? .some(loginPath) : nil }
            let shellPath = asked ?? HomebrewEnvironment.loginShellExports(
                shellPath: HomebrewCommandBuilder.currentShellPath)["PATH"]
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let folders = ([".local/bin", ".bun/bin", ".npm-global/bin", ".volta/bin", ".cargo/bin", ".deno/bin"]
                .map { home + "/" + $0 } + ["/opt/homebrew/bin", "/usr/local/bin"])
                + (shellPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
            var found: [String: String] = [:]
            for agent in CommandBarAgentsSupport.presets {
                let command = CommandBarAgentsSupport.command(for: agent, in: overrides)
                guard let name = CommandBarAgentsSupport.executableName(of: command) else { continue }
                if let path = executable(named: name, in: folders, home: home) { found[agent.id] = path }
            }
            let changed: Bool = lock.withLock {
                askedLoginPath = true
                loginPath = shellPath
                detectedAt = Date()
                detecting = false
                defer { installedPaths = found }
                return installedPaths != found
            }
            if changed { DispatchQueue.main.async(execute: completion) }
        }
    }

    private static func executable(named name: String, in folders: [String], home: String) -> String? {
        let candidates: [String]
        if name.contains("/") {
            candidates = [name.hasPrefix("~/") ? home + name.dropFirst() : name]
        } else {
            candidates = folders.map { $0 + "/" + name }
        }
        return candidates.first { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: path)
        }
    }

    // MARK: - Terminals

    static func applicationURL(for terminal: CommandBarTerminal) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID)
    }

    static func installedTerminals() -> [CommandBarTerminal] {
        CommandBarTerminal.allCases.filter { applicationURL(for: $0) != nil }
    }

    static func preferredTerminal() -> CommandBarTerminal? {
        CommandBarAgentsSupport.terminal(
            preference: UserDefaults.standard.string(forKey: DefaultsKey.commandBarAgentTerminal) ?? "",
            installed: Set(installedTerminals()))
    }

    /// Opens `terminal` (or the preferred one) in `directory` with the
    /// agent's command typed into its shell, and remembers the folder.
    static func launch(_ agent: CommandBarAgent, in directory: String, terminal: CommandBarTerminal? = nil) {
        let strings = CommandBarAgentStrings.strings(L10n.shared.language)
        guard let terminal = terminal ?? preferredTerminal(), let appURL = applicationURL(for: terminal) else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.noTerminal)
            return
        }
        let command = command(for: agent)
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: terminal.bundleID).isEmpty
        log.notice("launch \(agent.id, privacy: .public) in \(directory, privacy: .public) with \(terminal.rawValue, privacy: .public), running: \(wasRunning)")
        DispatchQueue.global(qos: .userInitiated).async {
            let opened: Bool
            if terminal == .otty {
                let cli = appURL.appending(path: "Contents/MacOS/otty-cli").path
                opened = CommandBarAgentsSupport.ottyAttempts(isRunning: wasRunning, directory: directory,
                                                              command: command)
                    .contains { arguments in
                        let result = runOtty(cli, arguments, timeout: 10)
                        log.notice("otty \(arguments.prefix(2).joined(separator: " "), privacy: .public) → \(result.status): \(result.output.prefix(300), privacy: .public)")
                        return result.status == 0
                    }
                if opened {
                    // The bar never takes focus, so Vorssaint is not the active
                    // app and may not hand activation over itself; Launch
                    // Services brings the terminal forward either way.
                    DispatchQueue.main.async {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = true
                        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                    }
                }
            } else if let script = CommandBarAgentsSupport.appleScript(for: terminal, directory: directory,
                                                                       command: command, wasRunning: wasRunning) {
                let result = AppleScriptRunner.run(script)
                log.notice("\(terminal.rawValue, privacy: .public) script ok: \(result.ok) \(result.output.prefix(300), privacy: .public)")
                opened = result.ok
            } else {
                opened = false
            }
            DispatchQueue.main.async {
                guard opened else {
                    QuickToolHUD.show(icon: "exclamationmark.triangle",
                                      message: String(format: strings.launchFailedFormat, terminal.name))
                    return
                }
                remember(directory)
            }
        }
    }

    private static func remember(_ directory: String) {
        let defaults = UserDefaults.standard
        let recent = CommandBarAgentsSupport.decodeRecent(defaults.string(forKey: DefaultsKey.commandBarAgentRecentFolders))
        defaults.set(CommandBarAgentsSupport.encodeRecent(
            CommandBarAgentsSupport.recording(directory, at: Date(), in: recent)),
                     forKey: DefaultsKey.commandBarAgentRecentFolders)
        lock.withLock { history = nil }
    }

    /// Any folder at all, for when the one wanted is not among the recent.
    static func chooseFolder(for agent: CommandBarAgent) {
        let strings = CommandBarAgentStrings.strings(L10n.shared.language)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(format: strings.choosePanelMessageFormat, agent.name)
        panel.prompt = strings.choosePanelPrompt
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            launch(agent, in: url.path)
        }
    }

    // MARK: - Folders

    /// The folder of Finder's front window, when Finder is the app in front.
    /// Only asks for the Automation permission when `prompting`, which is
    /// when the person is choosing a folder, never just for opening the bar.
    static func finderFolder(prompting: Bool) -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return nil }
        let allowed = prompting
            ? AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder")
            : Permissions.automationStatus(for: .finder) == .granted
        guard allowed else { return nil }
        let result = AppleScriptRunner.run("""
        tell application "Finder"
            if (count of Finder windows) = 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """)
        let path = CommandBarAgentsSupport.normalizedPath(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        return result.ok && path.hasPrefix("/") ? path : nil
    }

    /// The folders agents and terminals were used in lately, newest first.
    /// Read again at most every half minute; blocking, so call it off the
    /// main thread.
    static func recentFolders() -> [Directory] {
        if let history = lock.withLock({ history }), Date().timeIntervalSince(history.at) < 30 {
            return history.folders
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let own = CommandBarAgentsSupport.decodeRecent(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarAgentRecentFolders))
        let folders = CommandBarAgentsSupport.merged(
            [own, claudeFolders(home: home), codexFolders(home: home), ottyFolders()],
            home: home.path, limit: 40,
            exists: { path in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
            })
        lock.withLock { history = (folders, Date()) }
        return folders
    }

    /// Claude Code's projects, dated by the folder it keeps their sessions in.
    private static func claudeFolders(home: URL) -> [Directory] {
        guard let data = try? Data(contentsOf: home.appending(path: ".claude.json")) else { return [] }
        let sessions = home.appending(path: ".claude/projects")
        let dates = (try? FileManager.default.contentsOfDirectory(
            at: sessions, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .reduce(into: [String: Date]()) { dates, url in
                dates[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
            } ?? [:]
        return CommandBarAgentsSupport.claudeProjects(json: data).compactMap { path in
            dates[CommandBarAgentsSupport.claudeProjectFolderName(path)].map { Directory(path: path, lastUsed: $0) }
        }
    }

    /// The folders of the latest Codex sessions, newest first by day.
    private static func codexFolders(home: URL, limit: Int = 150) -> [Directory] {
        let manager = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var logs: [URL] = []
        outer: for year in children(home.appending(path: ".codex/sessions")) {
            for month in children(year) {
                for day in children(month) {
                    logs += children(day).filter { $0.pathExtension == "jsonl" }
                    if logs.count >= limit { break outer }
                }
            }
        }
        return logs.prefix(limit).compactMap { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 16 * 1024),
                  let path = CommandBarAgentsSupport.codexDirectory(fromHead: head),
                  let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                      .contentModificationDate else { return nil }
            return Directory(path: path, lastUsed: date)
        }
    }

    /// `otty` finds the running app's socket under `$HOME`, and a child of
    /// `Shell.run` starts with an empty environment, so it is handed this
    /// process's own, with a home folder whatever launched the app.
    private static func runOtty(_ cli: String, _ arguments: [String],
                                timeout: TimeInterval) -> (status: Int32, output: String) {
        var environment = ProcessInfo.processInfo.environment
        if (environment["HOME"] ?? "").isEmpty { environment["HOME"] = NSHomeDirectory() }
        let result = BoundedProcessRunner.run(cli, arguments, timeout: timeout,
                                              maxOutputBytes: 1024 * 1024, environment: environment)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }

    private static func ottyFolders() -> [Directory] {
        guard let app = applicationURL(for: .otty) else { return [] }
        let cli = app.appending(path: "Contents/MacOS/otty-cli").path
        guard FileManager.default.isExecutableFile(atPath: cli) else { return [] }
        let result = runOtty(cli, ["jump", "ls", "100", "--json"], timeout: 3)
        guard result.status == 0 else { return [] }
        return CommandBarAgentsSupport.ottyDirectories(json: Data(result.output.utf8))
    }

    // MARK: - Rows

    /// The ranking priority of an agent row for what was typed.
    static func priority(forRowID id: String, normalizedQuery: String) -> Int {
        guard id.hasPrefix(CommandBarAgentsSupport.agentRowPrefix),
              let agent = CommandBarAgentsSupport.preset(id: String(id.dropFirst(CommandBarAgentsSupport.agentRowPrefix.count))),
              CommandBarAgentsSupport.queryNames(agent, command: command(for: agent), normalizedQuery: normalizedQuery)
        else { return 0 }
        return CommandBarAgentsSupport.namedPriority
    }

    private static func icon(for agent: CommandBarAgent) -> CommandBarEntry.Icon {
        for id in agent.iconBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return .appIcon(path: url.path)
            }
        }
        return .symbol("terminal")
    }

    /// One row per agent: Return steps into the folders to start it in.
    static func agentEntries(language: AppLanguage) -> [CommandBarEntry] {
        let strings = CommandBarAgentStrings.strings(language)
        let terminal = preferredTerminal()?.name ?? CommandBarTerminal.terminal.name
        return available().map { agent in
            CommandBarEntry(
                id: agent.rowID,
                title: agent.name,
                subtitle: String(format: strings.agentSubtitleFormat, terminal),
                keywords: agent.keywords + " " + command(for: agent),
                icon: icon(for: agent),
                keepsBarOpen: true,
                run: { _ in CommandBarService.shared.beginAgentLaunch(agent) })
        }
    }

    /// The folders to start `agent` in: Finder's, then the recent ones, then
    /// a row that asks for any other. Without an agent the rows are only a
    /// preview and do nothing.
    static func folderEntries(agent: CommandBarAgent?, finder: String?, recent: [Directory],
                              language: AppLanguage) -> [CommandBarEntry] {
        let strings = CommandBarAgentStrings.strings(language)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func row(_ path: String, note: String?) -> CommandBarEntry {
            let short = CommandBarAgentsSupport.abbreviated(path, home: home)
            let name = (path as NSString).lastPathComponent
            return CommandBarEntry(
                id: CommandBarAgentsSupport.directoryRowPrefix + path,
                title: name.isEmpty ? path : name,
                subtitle: note.map { "\($0) · \(short)" } ?? short,
                keywords: short + " " + path,
                icon: .filePath(path),
                countsUsage: false,
                revealPath: path,
                run: { _ in
                    guard let agent else {
                        log.error("folder row ran without an agent")
                        NSSound.beep()
                        return
                    }
                    launch(agent, in: path)
                })
        }
        var rows: [CommandBarEntry] = []
        if let finder { rows.append(row(finder, note: strings.finderFolder)) }
        rows += recent.filter { $0.path != finder }.map { row($0.path, note: nil) }
        rows.append(CommandBarEntry(
            id: CommandBarAgentsSupport.chooseFolderRowID,
            title: strings.chooseFolder,
            subtitle: recent.isEmpty && finder == nil ? strings.emptyFolders : strings.chooseFolderSubtitle,
            keywords: "choose browse open folder 选择 文件夹 浏览",
            icon: .symbol("folder.badge.plus"),
            countsUsage: false,
            run: { _ in
                guard let agent else { NSSound.beep(); return }
                chooseFolder(for: agent)
            }))
        return rows
    }
}
