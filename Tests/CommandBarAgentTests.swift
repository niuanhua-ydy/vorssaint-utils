// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarAgentTests {
    static func run(_ suite: TestSuite) {
        typealias Support = CommandBarAgentsSupport
        typealias Directory = CommandBarAgentsSupport.Directory
        let claude = Support.preset(id: "claude")!

        // Rows and their place among the sources.
        suite.expect(CommandBarPreferences.source(ofRowID: claude.rowID) == .agents
                     && CommandBarPreferences.source(ofRowID: Support.directoryRowPrefix + "/tmp") == .agents
                     && CommandBarPreferences.source(ofRowID: Support.chooseFolderRowID) == .agents,
                     "agent and folder rows belong to the agents source")
        suite.expect(CommandBarPreferences.acceptsAlias(rowID: claude.rowID)
                     && CommandBarPreferences.acceptsPin(rowID: claude.rowID),
                     "an agent row keeps a name and a pin")
        suite.expect(!CommandBarPreferences.acceptsAlias(rowID: Support.directoryRowPrefix + "/tmp")
                     && !CommandBarPreferences.acceptsPin(rowID: Support.chooseFolderRowID),
                     "folder rows come and go, so they take neither")
        suite.expect(Set(Support.presets.map(\.id)).count == Support.presets.count,
                     "agent ids are unique")

        // Command lines.
        var commands = Support.settingCommand("claude --dangerously-skip-permissions", for: claude, in: [:])
        suite.expect(Support.command(for: claude, in: commands) == "claude --dangerously-skip-permissions",
                     "a command written over the default is used")
        commands = Support.settingCommand("  claude ", for: claude, in: commands)
        suite.expect(commands.isEmpty && Support.command(for: claude, in: commands) == "claude",
                     "writing the default back forgets the override")
        suite.expect(Support.decodeCommands(Support.encodeCommands(["codex": "codex --yolo"])) == ["codex": "codex --yolo"]
                     && Support.decodeCommands("not json").isEmpty && Support.decodeCommands(#"{"x":"  "}"#).isEmpty,
                     "command overrides round-trip and junk reads as none")
        suite.expect(Support.executableName(of: "claude --resume") == "claude"
                     && Support.executableName(of: "ANTHROPIC_MODEL=x env FOO=1 claude") == "claude"
                     && Support.executableName(of: "'/opt/my tools/agent' --x") == "/opt/my tools/agent"
                     && Support.executableName(of: #"/opt/my\ tools/a"#) == "/opt/my tools/a"
                     && Support.executableName(of: #"FOO="a b" codex"#) == "codex"
                     && Support.executableName(of: "~/bin/codex -m o3") == "~/bin/codex"
                     && Support.executableName(of: "   ") == nil,
                     "the program a command starts skips assignments")
        let disabled = Support.settingAgent("codex", enabled: false, disabledRaw: "")
        suite.expect(Support.disabledAgents(from: disabled) == ["codex"]
                     && Support.settingAgent("codex", enabled: true, disabledRaw: disabled).isEmpty,
                     "agents switch off and back on")

        // A query that plainly names an agent.
        let codex = Support.preset(id: "codex")!
        let cursor = Support.preset(id: "cursor-agent")!
        func names(_ agent: CommandBarAgent, _ query: String, command: String? = nil) -> Bool {
            Support.queryNames(agent, command: command ?? agent.command,
                               normalizedQuery: CommandBarSearch.normalized(query))
        }
        suite.expect(names(claude, "claude") && names(claude, "Claude Code") && names(claude, "claude vors")
                     && names(codex, "codex") && names(cursor, "cursor-agent")
                     && names(claude, "cc", command: "/opt/bin/cc --x"),
                     "an agent's program, id or name finds it plainly")
        suite.expect(!names(claude, "clau") && !names(claude, "claudette") && !names(cursor, "cursor")
                     && !names(codex, "code"),
                     "a prefix or another word is not plainly the agent")
        suite.expect(CommandBarSearch.launcherOrdered([0, 1, 2], id: {
            ["file./x", claude.rowID, "app./Applications/X.app"][$0] }) == [1, 2, 0],
                     "agent rows rank with apps and actions, ahead of discovery")

        // Terminals.
        suite.expect(Support.terminal(preference: "", installed: [.terminal, .otty, .iterm]) == .otty
                     && Support.terminal(preference: "", installed: [.terminal, .iterm]) == .iterm
                     && Support.terminal(preference: "iterm", installed: [.otty, .iterm]) == .iterm
                     && Support.terminal(preference: "ghostty", installed: [.terminal]) == .terminal
                     && Support.terminal(preference: "", installed: []) == nil,
                     "Otty leads when left to the bar, and a chosen terminal that is gone falls back")
        suite.expect(Support.typedCommand(directory: "/Users/me/it's here", command: "claude")
                     == #"cd -- '/Users/me/it'\''s here' && claude"#
                     && Support.typedCommand(directory: "/tmp/a", command: "codex") == "cd -- /tmp/a && codex",
                     "a folder is quoted for the shell it is typed into")
        let otty = Support.ottyAttempts(isRunning: true, directory: "/tmp", command: "claude")
        suite.expect(otty.first == ["tab", "new", "--cwd", "/tmp", "--command", "claude"] && otty.count == 2
                     && !otty.contains { $0.first == "open" }
                     && Support.ottyAttempts(isRunning: false, directory: "/tmp", command: "claude")
                        == [["open", "/tmp", "--command", "claude"]],
                     "a running Otty takes a tab; one not running is launched into the folder")
        let ghostty = Support.appleScript(for: .ghostty, directory: #"/tmp/"q""#, command: "claude",
                                          wasRunning: true) ?? ""
        suite.expect(ghostty.contains(#"initial working directory of cfg to "/tmp/\"q\"""#)
                     && ghostty.contains(#"initial input of cfg to "claude" & linefeed"#),
                     "Ghostty gets the folder and types the agent into its shell")
        let iterm = Support.appleScript(for: .iterm, directory: "/tmp", command: "claude", wasRunning: false) ?? ""
        suite.expect(iterm.contains(#"write text "cd -- /tmp && claude""#) && iterm.contains("if false or"),
                     "iTerm reuses the window it opened on launch")
        suite.expect(Support.appleScript(for: .terminal, directory: "/tmp", command: "x", wasRunning: false)?
                        .contains("in window 1") == true
                     && Support.appleScript(for: .otty, directory: "/tmp", command: "x", wasRunning: true) == nil,
                     "Terminal reuses its first window; Otty is driven by its own command")

        // Folders.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let merged = Support.merged([
            [Directory(path: "/Users/me/a", lastUsed: now.addingTimeInterval(-10)),
             Directory(path: "/Users/me", lastUsed: now)],
            [Directory(path: "/Users/me/a/", lastUsed: now.addingTimeInterval(-1)),
             Directory(path: "/Users/me/b", lastUsed: now.addingTimeInterval(-5)),
             Directory(path: "/", lastUsed: now),
             Directory(path: "/Users/me/gone", lastUsed: now)],
        ], home: "/Users/me", limit: 10, exists: { $0 != "/Users/me/gone" })
        suite.expect(merged == [Directory(path: "/Users/me/a", lastUsed: now.addingTimeInterval(-1)),
                                Directory(path: "/Users/me/b", lastUsed: now.addingTimeInterval(-5))],
                     "folders merge at their latest use, without home, the disk or what is gone")
        suite.expect(Support.merged([[Directory(path: "/x", lastUsed: now), Directory(path: "/y", lastUsed: now)]],
                                    home: "/h", limit: 1, exists: { _ in true }).count == 1,
                     "the list is capped")
        suite.expect(Support.abbreviated("/Users/me/code", home: "/Users/me/") == "~/code"
                     && Support.abbreviated("/Users/meme", home: "/Users/me") == "/Users/meme",
                     "paths under home are written with a tilde")
        suite.expect(Support.claudeProjectFolderName("/Users/me/tools/vorssaint-utils")
                     == "-Users-me-tools-vorssaint-utils"
                     && Support.claudeProjectFolderName("/Users/me/my.app_x 中") == "-Users-me-my-app-x--",
                     "Claude Code's session folder name is the path with every non-alphanumeric a dash")
        suite.expect(Support.claudeProjects(json: Data(#"{"projects":{"/b":{},"/a":{},"relative":{}}}"#.utf8)) == ["/a", "/b"]
                     && Support.claudeProjects(json: Data("[]".utf8)).isEmpty,
                     "Claude Code's projects are its absolute keys")
        let head = #"{"type":"session_meta","payload":{"id":"x","cwd":"/Users/me/\"q\"","base_instructions":{"text":"#
        suite.expect(Support.codexDirectory(fromHead: Data(head.utf8)) == #"/Users/me/"q""#
                     && Support.codexDirectory(fromHead: Data(#"{"cwd":"relative"}"#.utf8)) == nil
                     && Support.codexDirectory(fromHead: Data("{}".utf8)) == nil,
                     "a Codex session's folder is read from a truncated first line")
        let jump = #"{"data":{"entries":[{"path":"/a","last_seen":5.5},{"path":"b","last_seen":1},{"path":"/c"}]}}"#
        suite.expect(Support.ottyDirectories(json: Data(jump.utf8))
                     == [Directory(path: "/a", lastUsed: Date(timeIntervalSince1970: 5.5))],
                     "Otty's jump list keeps dated absolute folders")
        var recent: [Directory] = []
        for index in 0..<(Support.recentLimit + 5) {
            recent = Support.recording("/p/\(index)", at: now.addingTimeInterval(Double(index)), in: recent)
        }
        recent = Support.recording("/p/10/", at: now.addingTimeInterval(100), in: recent)
        suite.expect(recent.count == Support.recentLimit && recent.first?.path == "/p/10"
                     && recent.filter { $0.path == "/p/10" }.count == 1,
                     "a folder started again moves to the front once, within the limit")
        suite.expect(Support.decodeRecent(Support.encodeRecent(Array(recent.prefix(2)))) == Array(recent.prefix(2))
                     && Support.decodeRecent("junk").isEmpty,
                     "recent folders round-trip")
    }
}
