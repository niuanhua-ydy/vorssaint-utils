// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// The usage record: Vorssaint's own use, and the AI agents' tokens.
struct UsageRecordStrings {
    let language: AppLanguage
    let title: String
    let hubDescription: String
    let open: String
    let appTab: String
    let aiTab: String
    // Shared
    let peakDay: String
    let longestStreak: String
    let currentStreak: String
    let activity: String
    let daily: String
    let weekly: String
    let cumulative: String
    let less: String
    let more: String
    let none: String
    let weekFormat: String
    let throughFormat: String
    let activeDaysFormat: String
    let cancel: String
    let keywords: String
    // Vorssaint
    let totalUses: String
    let favorite: String
    let usesActivity: String
    let allFeatures: String
    let byFeature: String
    let topCommands: String
    let freedFormat: String
    let appEmpty: String
    let appNote: String
    let clearApp: String
    let clearAppQuestion: String
    let clearAppDetail: String
    // AI
    let totalTokens: String
    let totalCost: String
    let longestTurn: String
    let tokens: String
    let cost: String
    let allAgents: String
    let agents: String
    let requestsFormat: String
    let empty: String
    let paused: String
    let backfilling: String
    let openSettings: String
    let note: String
    let costNote: String
    let clearAgents: String
    let clearAgentsQuestion: String
    let clearAgentsDetail: String

    func days(_ count: Int) -> String {
        switch language {
        case .zhHans, .zhTW, .zhHK: return "\(count) 天"
        case .ja: return "\(count) 日"
        case .ko: return "\(count)일"
        default: return count == 1 ? "1 day" : "\(count) days"
        }
    }

    func times(_ count: String) -> String {
        switch language {
        case .zhHans, .zhTW, .zhHK: return "\(count) 次"
        case .ja: return "\(count) 回"
        case .ko: return "\(count)회"
        default: return count == "1" ? "1 use" : "\(count) uses"
        }
    }

    func group(_ group: AppUsageGroup) -> String {
        let chinese = ["Command Bar", "截图与录屏", "文本", "系统维护"]
        let japanese = ["Command Bar", "スクリーンショットと録画", "テキスト", "メンテナンス"]
        let korean = ["Command Bar", "스크린샷과 녹화", "텍스트", "유지 관리"]
        let english = ["Command Bar", "Capture", "Text", "Maintenance"]
        let index = AppUsageGroup.allCases.firstIndex(of: group) ?? 0
        return pick(chinese, japanese, korean, english)[index]
    }

    func kind(_ kind: AppUsageKind) -> String {
        let chinese = ["Command Bar", "截图", "录屏", "文字识别", "取色", "截图翻译",
                       "翻译", "ClipNote 粘贴", "纯文本粘贴", "清理", "卸载 App", "结束进程", "释放端口"]
        let japanese = ["Command Bar", "スクリーンショット", "画面収録", "文字認識", "カラーピッカー", "スクリーンショット翻訳",
                        "翻訳", "ClipNote からペースト", "プレーンテキストでペースト", "クリーンアップ", "アプリの削除",
                        "プロセスの終了", "ポートの解放"]
        let korean = ["Command Bar", "스크린샷", "화면 녹화", "텍스트 인식", "색상 추출", "스크린샷 번역",
                      "번역", "ClipNote 붙여넣기", "일반 텍스트 붙여넣기", "정리", "앱 제거", "프로세스 종료", "포트 해제"]
        let english = ["Command Bar", "Screenshots", "Recordings", "Text recognition", "Color picks", "Screenshot translation",
                       "Translations", "ClipNote pastes", "Plain pastes", "Cleanups", "Apps uninstalled",
                       "Processes ended", "Ports freed"]
        let index = AppUsageKind.allCases.firstIndex(of: kind) ?? 0
        return pick(chinese, japanese, korean, english)[index]
    }

    private func pick(_ chinese: [String], _ japanese: [String], _ korean: [String], _ english: [String]) -> [String] {
        switch language {
        case .zhHans, .zhTW, .zhHK: return chinese
        case .ja: return japanese
        case .ko: return korean
        default: return english
        }
    }

    static func strings(_ language: AppLanguage) -> Self {
        switch language {
        case .zhHans, .zhTW, .zhHK: return Self(
            language: language,
            title: "用量记录",
            hubDescription: "参考 Codex 的用量页：Vorssaint 各功能每天用了几次，以及 Claude、Codex 等 AI Agent 一年来的 Token 和费用，配热力图和连续天数。",
            open: "打开用量记录",
            appTab: "Vorssaint",
            aiTab: "AI",
            peakDay: "单日峰值",
            longestStreak: "最长连续天数",
            currentStreak: "当前连续天数",
            activity: "活动",
            daily: "每天",
            weekly: "每周",
            cumulative: "累计总量",
            less: "少",
            more: "多",
            none: "无使用",
            weekFormat: "%@ 起的一周",
            throughFormat: "截至 %@",
            activeDaysFormat: "%@ 个活跃日",
            cancel: "取消",
            keywords: "usage record history statistics streak 用量 记录 统计 使用次数 yongliang tongji AI token Claude Codex",
            totalUses: "累计使用次数",
            favorite: "最常用",
            usesActivity: "使用活动",
            allFeatures: "全部功能",
            byFeature: "按功能",
            topCommands: "常用命令",
            freedFormat: "共释放 %@",
            appEmpty: "还没有记录。用 Command Bar、截图、翻译、ClipNote、清理等功能时，这里会自动记下次数。",
            appNote: "只在本机记下哪天用了哪些功能、用了几次，以及 Command Bar 里运行过的命令名；不记截图、粘贴或翻译的内容。",
            clearApp: "清空 Vorssaint 记录…",
            clearAppQuestion: "清空 Vorssaint 使用记录？",
            clearAppDetail: "已记下的使用次数会全部删除，无法恢复。",
            totalTokens: "累计 Token",
            totalCost: "累计 API 价值",
            longestTurn: "最长任务用时",
            tokens: "Token",
            cost: "费用",
            allAgents: "全部 Agent",
            agents: "按 Agent",
            requestsFormat: "%@ 次请求",
            empty: "还没有记录。灵动岛的 AI 页面读取 Claude、Codex 等留在本机的日志，打开后这里会显示一年的用量。",
            paused: "灵动岛的 AI 页面已关闭，记录已暂停。",
            backfilling: "正在从日志补齐更早的用量…",
            openSettings: "打开设置",
            note: "最近 13 周直接来自灵动岛读取的日志，更早的部分从日志补齐一次后按天保存，Agent 删掉旧日志也不受影响。只存每天的总量，不含任何对话内容。",
            costNote: "费用按 API 列表价估算，不是订阅的实际花费。",
            clearAgents: "清空 AI 记录…",
            clearAgentsQuestion: "清空 AI 用量记录？",
            clearAgentsDetail: "清空后会重新从日志读取；Agent 已经删掉的日志里的用量就找不回了。")
        case .ja: return Self(
            language: language,
            title: "使用量の記録",
            hubDescription: "Codex の使用量ページのように、Vorssaint の各機能を毎日何回使ったかと、Claude や Codex などの AI エージェントの 1 年分のトークンと費用を、ヒートマップと連続日数で表示します。",
            open: "使用量の記録を開く",
            appTab: "Vorssaint",
            aiTab: "AI",
            peakDay: "1 日の最大",
            longestStreak: "最長連続日数",
            currentStreak: "現在の連続日数",
            activity: "アクティビティ",
            daily: "毎日",
            weekly: "毎週",
            cumulative: "累計",
            less: "少",
            more: "多",
            none: "使用なし",
            weekFormat: "%@ からの週",
            throughFormat: "%@ まで",
            activeDaysFormat: "%@ 日アクティブ",
            cancel: "キャンセル",
            keywords: "usage record history statistics streak 使用量 記録 統計 使用回数 AI トークン Claude Codex",
            totalUses: "累計使用回数",
            favorite: "よく使う機能",
            usesActivity: "使用アクティビティ",
            allFeatures: "すべての機能",
            byFeature: "機能別",
            topCommands: "よく使うコマンド",
            freedFormat: "合計 %@ を解放",
            appEmpty: "まだ記録がありません。Command Bar、スクリーンショット、翻訳、ClipNote、クリーンアップなどを使うと、ここに回数が記録されます。",
            appNote: "この Mac にだけ、どの日にどの機能を何回使ったかと Command Bar で実行したコマンド名を記録します。スクリーンショット、ペースト、翻訳の内容は記録しません。",
            clearApp: "Vorssaint の記録を消去…",
            clearAppQuestion: "Vorssaint の使用記録を消去しますか？",
            clearAppDetail: "記録された使用回数はすべて削除され、元に戻せません。",
            totalTokens: "累計トークン",
            totalCost: "累計 API 換算額",
            longestTurn: "最長タスク時間",
            tokens: "トークン",
            cost: "費用",
            allAgents: "すべてのエージェント",
            agents: "エージェント別",
            requestsFormat: "%@ リクエスト",
            empty: "まだ記録がありません。ダイナミックアイランドの AI ページを有効にすると、Claude や Codex がこの Mac に残すログから 1 年分の使用量を表示します。",
            paused: "ダイナミックアイランドの AI ページがオフのため、記録は停止中です。",
            backfilling: "以前の使用量をログから読み込んでいます…",
            openSettings: "設定を開く",
            note: "直近 13 週はアイランドが読むログから、それより前はログから一度読み込んで日ごとに保存するため、エージェントが古いログを消しても残ります。保存するのは日ごとの合計だけで、会話の内容は含みません。",
            costNote: "費用は API の定価による概算で、サブスクリプションの実際の支払額ではありません。",
            clearAgents: "AI の記録を消去…",
            clearAgentsQuestion: "AI の使用量の記録を消去しますか？",
            clearAgentsDetail: "消去後はログから読み直します。エージェントがすでに削除したログの分は戻りません。")
        case .ko: return Self(
            language: language,
            title: "사용량 기록",
            hubDescription: "Codex의 사용량 페이지처럼 Vorssaint의 기능을 하루에 몇 번 썼는지와 Claude, Codex 등 AI 에이전트의 1년간 토큰과 비용을 히트맵과 연속 일수로 보여 줍니다.",
            open: "사용량 기록 열기",
            appTab: "Vorssaint",
            aiTab: "AI",
            peakDay: "하루 최대",
            longestStreak: "최장 연속 일수",
            currentStreak: "현재 연속 일수",
            activity: "활동",
            daily: "매일",
            weekly: "매주",
            cumulative: "누적",
            less: "적음",
            more: "많음",
            none: "사용 없음",
            weekFormat: "%@부터 한 주",
            throughFormat: "%@까지",
            activeDaysFormat: "활동한 날 %@일",
            cancel: "취소",
            keywords: "usage record history statistics streak 사용량 기록 통계 사용 횟수 AI 토큰 Claude Codex",
            totalUses: "누적 사용 횟수",
            favorite: "가장 많이 쓴 기능",
            usesActivity: "사용 활동",
            allFeatures: "모든 기능",
            byFeature: "기능별",
            topCommands: "자주 쓰는 명령",
            freedFormat: "총 %@ 확보",
            appEmpty: "아직 기록이 없습니다. Command Bar, 스크린샷, 번역, ClipNote, 정리 등을 사용하면 여기에 횟수가 기록됩니다.",
            appNote: "이 Mac에만 어느 날 어떤 기능을 몇 번 썼는지와 Command Bar에서 실행한 명령 이름을 기록합니다. 스크린샷, 붙여넣기, 번역 내용은 기록하지 않습니다.",
            clearApp: "Vorssaint 기록 지우기…",
            clearAppQuestion: "Vorssaint 사용 기록을 지울까요?",
            clearAppDetail: "기록된 사용 횟수가 모두 삭제되며 되돌릴 수 없습니다.",
            totalTokens: "누적 토큰",
            totalCost: "누적 API 환산액",
            longestTurn: "가장 긴 작업 시간",
            tokens: "토큰",
            cost: "비용",
            allAgents: "모든 에이전트",
            agents: "에이전트별",
            requestsFormat: "요청 %@회",
            empty: "아직 기록이 없습니다. 다이내믹 아일랜드의 AI 페이지를 켜면 Claude, Codex 등이 이 Mac에 남긴 로그에서 1년 치 사용량을 보여 줍니다.",
            paused: "다이내믹 아일랜드의 AI 페이지가 꺼져 있어 기록이 멈췄습니다.",
            backfilling: "이전 사용량을 로그에서 읽는 중…",
            openSettings: "설정 열기",
            note: "최근 13주는 아일랜드가 읽는 로그에서, 그 이전은 로그에서 한 번 읽어 하루 단위로 저장하므로 에이전트가 오래된 로그를 지워도 남습니다. 하루 합계만 저장하며 대화 내용은 담지 않습니다.",
            costNote: "비용은 API 정가로 추정한 값이며 구독의 실제 지출이 아닙니다.",
            clearAgents: "AI 기록 지우기…",
            clearAgentsQuestion: "AI 사용량 기록을 지울까요?",
            clearAgentsDetail: "지운 뒤 로그에서 다시 읽습니다. 에이전트가 이미 지운 로그의 사용량은 되돌릴 수 없습니다.")
        default: return Self(
            language: language,
            title: "Usage Record",
            hubDescription: "Like Codex’s usage page: how often each Vorssaint feature was used per day, and a year of tokens and cost from Claude, Codex and other AI agents, with a heatmap and streaks.",
            open: "Open Usage Record",
            appTab: "Vorssaint",
            aiTab: "AI",
            peakDay: "Busiest day",
            longestStreak: "Longest streak",
            currentStreak: "Current streak",
            activity: "Activity",
            daily: "Daily",
            weekly: "Weekly",
            cumulative: "Cumulative",
            less: "Less",
            more: "More",
            none: "No use",
            weekFormat: "Week of %@",
            throughFormat: "Through %@",
            activeDaysFormat: "%@ active days",
            cancel: "Cancel",
            keywords: "usage record history statistics streak uses AI tokens Claude Codex",
            totalUses: "Total uses",
            favorite: "Most used",
            usesActivity: "Activity",
            allFeatures: "All features",
            byFeature: "By feature",
            topCommands: "Top commands",
            freedFormat: "%@ freed in all",
            appEmpty: "Nothing recorded yet. Using the Command Bar, screenshots, translation, ClipNote, the cleaner and the rest adds to the counts here.",
            appNote: "Kept on this Mac only: which features were used on which day, how often, and the names of Command Bar commands run. Nothing captured, pasted or translated is kept.",
            clearApp: "Clear Vorssaint Record…",
            clearAppQuestion: "Clear the Vorssaint usage record?",
            clearAppDetail: "Every recorded use is deleted and cannot be brought back.",
            totalTokens: "Total tokens",
            totalCost: "Total API value",
            longestTurn: "Longest task",
            tokens: "Tokens",
            cost: "Cost",
            allAgents: "All agents",
            agents: "By agent",
            requestsFormat: "%@ requests",
            empty: "Nothing recorded yet. With the Dynamic Island’s AI page on, a year of use from the logs Claude, Codex and others leave on this Mac shows here.",
            paused: "The Dynamic Island’s AI page is off, so recording is paused.",
            backfilling: "Reading earlier use from the logs…",
            openSettings: "Open Settings",
            note: "The last thirteen weeks come from the logs the island reads; older use is read from the logs once and kept by day, so it stays after an agent deletes old logs. Daily totals only, nothing that was said.",
            costNote: "Cost is estimated at API list prices, not what a subscription charges.",
            clearAgents: "Clear AI Record…",
            clearAgentsQuestion: "Clear the AI usage record?",
            clearAgentsDetail: "It is read from the logs again; use from logs an agent already deleted cannot be brought back.")
        }
    }
}
