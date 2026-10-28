// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A coding agent that runs in a terminal, started from the bar in a folder.
struct CommandBarAgent: Identifiable, Equatable {
    let id: String
    let name: String
    /// What is typed into the shell when the person has not said otherwise.
    let command: String
    let keywords: String
    /// Desktop apps from the same vendor, whose icon the row borrows when
    /// one is installed; otherwise the row shows a terminal.
    let iconBundleIDs: [String]

    var rowID: String { CommandBarAgentsSupport.agentRowPrefix + id }
}

/// The terminals the bar knows how to open in a folder with a command typed
/// into the person's own shell, so their PATH and startup files apply and the
/// tab outlives the agent. Warp is missing on purpose: it can open a folder
/// but has no way to be handed a command to run there. Case order is the
/// order the bar prefers; Rex leads, as the terminal the owner moved to.
enum CommandBarTerminal: String, CaseIterable, Identifiable {
    case rex, otty, ghostty, iterm, terminal

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .rex: return "com.superlogical.rex"
        case .otty: return "io.appmakes.otty"
        case .ghostty: return "com.mitchellh.ghostty"
        case .iterm: return "com.googlecode.iterm2"
        case .terminal: return "com.apple.Terminal"
        }
    }

    var name: String {
        switch self {
        case .rex: return "Rex"
        case .otty: return "Otty"
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        case .terminal: return "Terminal"
        }
    }
}

enum CommandBarAgentsSupport {
    /// Row ids persist (pins, names, shortcuts), so these never drift.
    static let agentRowPrefix = "agent.cli."
    static let directoryRowPrefix = "agent.dir."
    static let chooseFolderRowID = "agent.choose"

    static let presets: [CommandBarAgent] = [
        .init(id: "claude", name: "Claude Code", command: "claude",
              keywords: "claude code anthropic cc agent cli",
              iconBundleIDs: ["com.anthropic.claudefordesktop"]),
        .init(id: "codex", name: "Codex", command: "codex",
              keywords: "codex openai gpt agent cli",
              iconBundleIDs: ["com.openai.codex", "com.openai.chat"]),
        .init(id: "gemini", name: "Gemini CLI", command: "gemini",
              keywords: "gemini google agent cli", iconBundleIDs: []),
        .init(id: "opencode", name: "OpenCode", command: "opencode",
              keywords: "opencode open code agent cli", iconBundleIDs: ["ai.opencode.desktop"]),
        .init(id: "kimi", name: "Kimi Code", command: "kimi",
              keywords: "kimi moonshot agent cli", iconBundleIDs: []),
        .init(id: "cursor-agent", name: "Cursor Agent", command: "cursor-agent",
              keywords: "cursor agent cli", iconBundleIDs: ["com.todesktop.230313mzl4w4u92"]),
        .init(id: "droid", name: "Droid", command: "droid",
              keywords: "droid factory agent cli", iconBundleIDs: []),
        .init(id: "qwen", name: "Qwen Code", command: "qwen",
              keywords: "qwen code alibaba agent cli", iconBundleIDs: []),
        .init(id: "copilot", name: "Copilot CLI", command: "copilot",
              keywords: "copilot github agent cli", iconBundleIDs: []),
        .init(id: "amp", name: "Amp", command: "amp",
              keywords: "amp sourcegraph agent cli", iconBundleIDs: []),
        .init(id: "aider", name: "Aider", command: "aider",
              keywords: "aider agent cli", iconBundleIDs: []),
    ]

    static func preset(id: String) -> CommandBarAgent? {
        presets.first { $0.id == id }
    }

    // MARK: - What the person decided

    /// The command lines the person wrote over the defaults, by agent id.
    static func decodeCommands(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map.compactMapValues { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
    }

    static func encodeCommands(_ commands: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(commands.filter { !$0.value.isEmpty }),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// An empty or default value forgets the override, so a later change to
    /// the preset still reaches someone who never really changed it.
    static func settingCommand(_ command: String, for agent: CommandBarAgent,
                               in commands: [String: String]) -> [String: String] {
        var next = commands
        let clean = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean == agent.command {
            next.removeValue(forKey: agent.id)
        } else {
            next[agent.id] = clean
        }
        return next
    }

    static func command(for agent: CommandBarAgent, in commands: [String: String]) -> String {
        commands[agent.id] ?? agent.command
    }

    /// The program a command line starts, so it can be looked for on PATH:
    /// leading `NAME=value` assignments and `env` are skipped, and quotes and
    /// backslashes are read the way the shell reads them.
    static func executableName(of command: String) -> String? {
        for word in shellWords(command) {
            if word == "env" || word.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil {
                continue
            }
            return word.isEmpty ? nil : word
        }
        return nil
    }

    /// Enough of the shell's word splitting to find a program's name; no
    /// expansion beyond quotes and backslashes.
    static func shellWords(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                word.append(character)
                escaped = false
            } else if let open = quote {
                if character == open { quote = nil }
                else if character == "\\" && open == "\"" { escaped = true }
                else { word.append(character) }
            } else if character == "\\" {
                escaped = true
                inWord = true
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character == " " || character == "\t" {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(character)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }

    /// What a row for an agent the query plainly names is worth: above any
    /// learned habit, below a name the person gave a row themselves.
    static let namedPriority = 800

    /// Whether what was typed is plainly this agent: its program, its id or
    /// its full name, alone or followed by more words. "claude" is Claude
    /// Code, not the app whose name merely starts the same way.
    static func queryNames(_ agent: CommandBarAgent, command: String, normalizedQuery query: String) -> Bool {
        let program = executableName(of: command).map { ($0 as NSString).lastPathComponent }
        let names = [program, agent.id, agent.name].compactMap { $0 }
            .map(CommandBarSearch.normalized).filter { !$0.isEmpty }
        return names.contains { query == $0 || query.hasPrefix($0 + " ") }
    }

    static func disabledAgents(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func settingAgent(_ id: String, enabled: Bool, disabledRaw: String) -> String {
        var disabled = disabledAgents(from: disabledRaw)
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        return disabled.sorted().joined(separator: ",")
    }

    /// The terminal the person chose, or the first one installed in the
    /// order the bar prefers when they left it to the bar.
    static func terminal(preference raw: String, installed: Set<CommandBarTerminal>) -> CommandBarTerminal? {
        if let chosen = CommandBarTerminal(rawValue: raw), installed.contains(chosen) { return chosen }
        return CommandBarTerminal.allCases.first { installed.contains($0) }
    }

    // MARK: - Command lines

    static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9._+@%/=:,-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// What is typed into a terminal that can only be handed text: change to
    /// the folder, and start the agent only if that worked.
    static func typedCommand(directory: String, command: String) -> String {
        "cd -- \(shellQuote(directory)) && \(command)"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The `otty` invocations to try in order. A running Otty takes a tab in
    /// its front window, falling back to a window of its own; one that is not
    /// running is launched straight into the folder. `open` is never a fallback
    /// for a running Otty: it answers success there without opening anything.
    static func ottyAttempts(isRunning: Bool, directory: String, command: String) -> [[String]] {
        guard isRunning else { return [["open", directory, "--command", command]] }
        return [
            ["tab", "new", "--cwd", directory, "--command", command],
            ["window", "new", "--cwd", directory, "--command", command],
        ]
    }

    /// The `rex` CLI inside the app, which talks to the Rex server the app
    /// keeps its sessions in.
    static let rexCLIPath = "Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"

    /// The session a new Rex tab joins, from `rex ls --json`. Rex cannot say
    /// which session its window shows, so with several the first in its own
    /// order is taken; nil when there is none and one has to be made.
    static func rexSession(listJSON data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sessions = object["sessions"] as? [[String: Any]] else { return nil }
        return sessions.lazy.compactMap { $0["session_id"] as? String }.first { !$0.isEmpty }
    }

    /// Opens a shell tab in the folder, in `session` or in a new session when
    /// there is none. The tab is named for the folder; the agent is typed in
    /// afterwards so the shell outlives it.
    static func rexOpenArguments(session: String?, directory: String) -> [String] {
        let label = (normalizedPath(directory) as NSString).lastPathComponent
        guard let session else { return ["new", label, "-c", directory, "--json"] }
        return ["window", "new", "-s", session, label, "-c", directory, "--json"]
    }

    /// The new tab's session, window and terminal, from either `window new`
    /// or `new`, which nests its first window.
    static func rexOpened(json data: Data, session: String?) -> (session: String, window: String, block: String)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let session = session ?? object["session_id"] as? String else { return nil }
        let window = (object["initial_windows"] as? [[String: Any]])?.first ?? object
        guard let id = window["window_id"] as? String,
              let block = (window["block_ids"] as? [Any])?.first as? String else { return nil }
        return (session, id, block)
    }

    /// The script for a terminal driven over Apple Events. A terminal that was
    /// not running opens a window of its own on launch, which is reused
    /// instead of leaving an empty one behind the agent's.
    static func appleScript(for terminal: CommandBarTerminal, directory: String, command: String,
                            wasRunning: Bool) -> String? {
        let app = "application id \(appleScriptLiteral(terminal.bundleID))"
        switch terminal {
        case .rex, .otty:
            return nil
        case .ghostty:
            // Typed into the shell rather than run in its place, so the tab
            // keeps the person's environment and stays when the agent exits.
            return """
            tell \(app)
                activate
                set cfg to new surface configuration
                set initial working directory of cfg to \(appleScriptLiteral(directory))
                set initial input of cfg to \(appleScriptLiteral(command)) & linefeed
                if (count of windows) > 0 then
                    new tab in front window with configuration cfg
                else
                    new window with configuration cfg
                end if
            end tell
            """
        case .iterm:
            let typed = appleScriptLiteral(typedCommand(directory: directory, command: command))
            return """
            tell \(app)
                activate
                if \(wasRunning ? "true" : "false") or (count of windows) = 0 then
                    set w to (create window with default profile)
                else
                    set w to current window
                end if
                tell current session of w to write text \(typed)
            end tell
            """
        case .terminal:
            let typed = appleScriptLiteral(typedCommand(directory: directory, command: command))
            if wasRunning {
                return """
                tell \(app)
                    do script \(typed)
                    activate
                end tell
                """
            }
            return """
            tell \(app)
                activate
                try
                    do script \(typed) in window 1
                on error
                    do script \(typed)
                end try
            end tell
            """
        }
    }

    // MARK: - Folders

    struct Directory: Equatable {
        let path: String
        let lastUsed: Date
    }

    /// Every list merged into one, newest first. A folder named by several
    /// sources counts once, at its latest use. The home folder and the disk
    /// itself are where shells start, not projects, so a history that only
    /// passed through them does not offer them.
    static func merged(_ lists: [[Directory]], home: String, limit: Int,
                       exists: (String) -> Bool) -> [Directory] {
        var latest: [String: Date] = [:]
        for directory in lists.joined() {
            let path = normalizedPath(directory.path)
            guard path != "/", path != normalizedPath(home) else { continue }
            if let known = latest[path], known >= directory.lastUsed { continue }
            latest[path] = directory.lastUsed
        }
        var folders: [Directory] = []
        for (path, date) in latest.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            guard folders.count < limit else { break }
            if exists(path) { folders.append(Directory(path: path, lastUsed: date)) }
        }
        return folders
    }

    static func normalizedPath(_ path: String) -> String {
        var path = (path as NSString).standardizingPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func abbreviated(_ path: String, home: String) -> String {
        let home = normalizedPath(home)
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The folder Claude Code keeps a project's sessions in: every character
    /// that is not a letter or a digit becomes a dash.
    static func claudeProjectFolderName(_ path: String) -> String {
        String(path.unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : "-"
        })
    }

    /// The projects listed in `~/.claude.json`, which keeps their real paths.
    static func claudeProjects(json data: Data) -> [String] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let projects = object["projects"] as? [String: Any] else { return [] }
        return projects.keys.filter { $0.hasPrefix("/") }.sorted()
    }

    /// The folder a Codex session ran in, read from the head of its log: the
    /// first line is its metadata, and the folder comes before the long
    /// instructions that follow it on that line.
    static func codexDirectory(fromHead data: Data) -> String? {
        let head = String(decoding: data, as: UTF8.self)
        guard let range = head.range(of: #""cwd"\s*:\s*"((?:[^"\\]|\\.)*)""#, options: .regularExpression) else {
            return nil
        }
        let match = String(head[range])
        guard let open = match.range(of: ":")?.upperBound else { return nil }
        let literal = match[open...].trimmingCharacters(in: .whitespaces)
        guard let value = (try? JSONSerialization.jsonObject(with: Data(literal.utf8),
                                                             options: [.fragmentsAllowed])) as? String,
              value.hasPrefix("/") else { return nil }
        return value
    }

    /// Otty's own list of the folders the person goes to, `jump ls --json`.
    static func ottyDirectories(json data: Data) -> [Directory] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let entries = payload["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let path = entry["path"] as? String, path.hasPrefix("/"),
                  let seen = (entry["last_seen"] as? NSNumber)?.doubleValue, seen.isFinite else { return nil }
            return Directory(path: path, lastUsed: Date(timeIntervalSince1970: seen))
        }
    }

    // MARK: - Where the bar itself started an agent

    static let recentLimit = 30

    private struct StoredDirectory: Codable {
        let path: String
        let time: TimeInterval
    }

    static func decodeRecent(_ raw: String?) -> [Directory] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([StoredDirectory].self, from: data) else { return [] }
        return stored.filter { $0.path.hasPrefix("/") && $0.time.isFinite }
            .map { Directory(path: $0.path, lastUsed: Date(timeIntervalSince1970: $0.time)) }
    }

    static func encodeRecent(_ directories: [Directory]) -> String {
        let stored = directories.map { StoredDirectory(path: $0.path, time: $0.lastUsed.timeIntervalSince1970) }
        guard let data = try? JSONEncoder().encode(stored),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func recording(_ path: String, at date: Date, in recent: [Directory]) -> [Directory] {
        let path = normalizedPath(path)
        let rest = recent.filter { normalizedPath($0.path) != path }
        return Array(([Directory(path: path, lastUsed: date)] + rest).prefix(recentLimit))
    }
}
