// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct CommandBarAgentStrings {
    let sourceTitle: String
    let agentSubtitleFormat: String
    let categoryTitleFormat: String
    let finderFolder: String
    let chooseFolder: String
    let chooseFolderSubtitle: String
    let choosePanelMessageFormat: String
    let choosePanelPrompt: String
    let openInFormat: String
    let noTerminal: String
    let launchFailedFormat: String
    let emptyFolders: String
    let terminal: String
    let automatic: String
    let agents: String
    let notFound: String
    let caption: String

    static func strings(_ language: AppLanguage) -> Self {
        switch language {
        case .zhHans, .zhTW, .zhHK: return Self(
            sourceTitle: "Agent CLI",
            agentSubtitleFormat: "选择目录后在 %@ 中启动",
            categoryTitleFormat: "%@ · 选择目录",
            finderFolder: "Finder 当前目录",
            chooseFolder: "选择文件夹…",
            chooseFolderSubtitle: "从任意位置选一个目录",
            choosePanelMessageFormat: "选择 %@ 的工作目录",
            choosePanelPrompt: "启动",
            openInFormat: "在 %@ 中打开",
            noTerminal: "没有找到支持的终端（Otty、Ghostty、iTerm 或 Terminal）",
            launchFailedFormat: "无法在 %@ 中启动",
            emptyFolders: "还没有最近的目录，选一个文件夹开始",
            terminal: "终端",
            automatic: "自动",
            agents: "Agent",
            notFound: "PATH 中未找到",
            caption: "输入 agent 名称，回车进入目录列表。最近目录合并自 Finder 当前窗口、在这里启动过的目录、Claude Code 与 Codex 的会话记录和 Otty 的跳转记录。命令会输入到终端的 shell 中执行，可在命令后追加参数。")
        case .ja: return Self(
            sourceTitle: "Agent CLI",
            agentSubtitleFormat: "フォルダを選んで %@ で起動",
            categoryTitleFormat: "%@ · フォルダを選択",
            finderFolder: "Finder の現在のフォルダ",
            chooseFolder: "フォルダを選択…",
            chooseFolderSubtitle: "任意の場所からフォルダを選ぶ",
            choosePanelMessageFormat: "%@ の作業フォルダを選択",
            choosePanelPrompt: "起動",
            openInFormat: "%@ で開く",
            noTerminal: "対応するターミナル（Otty、Ghostty、iTerm、Terminal）が見つかりません",
            launchFailedFormat: "%@ で起動できませんでした",
            emptyFolders: "最近のフォルダはまだありません。フォルダを選んでください",
            terminal: "ターミナル",
            automatic: "自動",
            agents: "Agent",
            notFound: "PATH に見つかりません",
            caption: "Agent の名前を入力し、Return でフォルダ一覧へ。最近のフォルダは Finder の前面ウインドウ、ここで起動した場所、Claude Code と Codex のセッション、Otty のジャンプ履歴から集めます。コマンドはターミナルのシェルに入力され、引数を追加できます。")
        case .ko: return Self(
            sourceTitle: "Agent CLI",
            agentSubtitleFormat: "폴더를 고른 뒤 %@에서 실행",
            categoryTitleFormat: "%@ · 폴더 선택",
            finderFolder: "Finder 현재 폴더",
            chooseFolder: "폴더 선택…",
            chooseFolderSubtitle: "아무 위치에서나 폴더 고르기",
            choosePanelMessageFormat: "%@의 작업 폴더 선택",
            choosePanelPrompt: "실행",
            openInFormat: "%@에서 열기",
            noTerminal: "지원되는 터미널(Otty, Ghostty, iTerm, Terminal)을 찾을 수 없습니다",
            launchFailedFormat: "%@에서 실행하지 못했습니다",
            emptyFolders: "최근 폴더가 아직 없습니다. 폴더를 선택하세요",
            terminal: "터미널",
            automatic: "자동",
            agents: "Agent",
            notFound: "PATH에서 찾을 수 없음",
            caption: "Agent 이름을 입력하고 Return으로 폴더 목록에 들어갑니다. 최근 폴더는 Finder 앞 윈도우, 여기서 실행한 위치, Claude Code와 Codex 세션, Otty 점프 기록에서 모읍니다. 명령은 터미널 셸에 입력되며 인수를 덧붙일 수 있습니다.")
        default: return Self(
            sourceTitle: "Agent CLI",
            agentSubtitleFormat: "Pick a folder, then start in %@",
            categoryTitleFormat: "%@ · Choose a Folder",
            finderFolder: "Finder’s current folder",
            chooseFolder: "Choose Folder…",
            chooseFolderSubtitle: "Pick any folder to start in",
            choosePanelMessageFormat: "Choose the folder %@ starts in",
            choosePanelPrompt: "Start",
            openInFormat: "Open in %@",
            noTerminal: "No supported terminal found (Otty, Ghostty, iTerm or Terminal)",
            launchFailedFormat: "Couldn’t start in %@",
            emptyFolders: "No recent folders yet. Choose one to start",
            terminal: "Terminal",
            automatic: "Automatic",
            agents: "Agents",
            notFound: "Not found on PATH",
            caption: "Type an agent’s name and press Return to pick a folder. Recent folders come from Finder’s front window, places started from here, Claude Code and Codex sessions, and Otty’s jump history. The command is typed into the terminal’s shell, so arguments can be added.")
        }
    }
}
