// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct TranslatorStrings {
    let title: String
    let apple: String
    let ai: String
    let dictionary: String
    let auto: String
    let detectedFormat: String
    let autoTargetFormat: String
    let placeholder: String
    let pending: String
    let copy: String
    let copied: String
    let speak: String
    let pin: String
    let unpin: String
    let swap: String
    let settings: String
    let close: String
    let noSelection: String
    let needsAccessibility: String
    let noText: String
    let ocrUnavailable: String
    let aiMissing: String
    let systemRequirement: String
    let unsupported: String
    let configure: String
    let tooLong: String
    let failed: String
    let truncated: String
    let privacy: String
    let selectionShortcut: String
    let inputShortcut: String
    let screenshotShortcut: String
    let translateSelection: String
    let firstLanguage: String
    let secondLanguage: String
    let directionCaption: String
    let services: String
    let dictionaryCaption: String
    let aiCaption: String
    let keysHint: String

    static func strings(_ language: AppLanguage) -> Self {
        switch language {
        case .zhHans, .zhTW, .zhHK: return Self(
            title: "翻译",
            apple: "Apple 翻译",
            ai: "AI 翻译",
            dictionary: "系统词典",
            auto: "自动检测",
            detectedFormat: "检测到 %@",
            autoTargetFormat: "%@（自动）",
            placeholder: "输入要翻译的文字",
            pending: "按 ↩ 用 AI 翻译",
            copy: "复制",
            copied: "已复制",
            speak: "朗读",
            pin: "钉住窗口",
            unpin: "取消钉住",
            swap: "交换语言",
            settings: "翻译设置",
            close: "关闭",
            noSelection: "没有读取到选中的文字，可以直接输入或粘贴。",
            needsAccessibility: "读取选中的文字需要辅助功能权限。",
            noText: "没有识别到文字。",
            ocrUnavailable: "截图翻译需要先启用屏幕文字识别。",
            aiMissing: "AI 翻译还没有配置",
            systemRequirement: "Apple 翻译需要 macOS 15 或更高版本。",
            unsupported: "不支持这个语言组合，请换一种语言或服务。",
            configure: "请配置 AI 地址、模型和 API Key。使用 HTTPS，仅本机地址允许 HTTP。",
            tooLong: "文本超过 10,000 字，请分段翻译。",
            failed: "翻译失败，请检查服务或语言设置后重试。",
            truncated: "译文被截断，请分段后重试。",
            privacy: "Apple 翻译和系统词典在本机处理，首次使用可能下载语言包。AI 只在打开窗口翻译或按 ↩ 时向你配置的服务发送文本。不保存翻译记录。",
            selectionShortcut: "划词翻译",
            inputShortcut: "输入翻译",
            screenshotShortcut: "截图翻译",
            translateSelection: "翻译所选文字",
            firstLanguage: "首选语言",
            secondLanguage: "第二语言",
            directionCaption: "目标语言设为自动时：原文是首选语言就翻译成第二语言，否则翻译成首选语言。",
            services: "翻译服务",
            dictionaryCaption: "查单词或短语时显示 macOS 词典里的释义。",
            aiCaption: "单词和短语会返回音标、词性和例句。打字时不会调用 AI，按 ↩ 才发送。",
            keysHint: "↩ 翻译 · ⇧↩ 换行 · ⌘↩ 复制译文 · ⌘S 交换 · ⌘P 钉住 · Esc 关闭")
        case .ja: return Self(
            title: "翻訳",
            apple: "Apple 翻訳",
            ai: "AI 翻訳",
            dictionary: "システム辞書",
            auto: "言語を検出",
            detectedFormat: "%@ を検出",
            autoTargetFormat: "%@（自動）",
            placeholder: "翻訳するテキストを入力",
            pending: "↩ で AI 翻訳",
            copy: "コピー",
            copied: "コピーしました",
            speak: "読み上げ",
            pin: "ウインドウを固定",
            unpin: "固定を解除",
            swap: "言語を入れ替え",
            settings: "翻訳の設定",
            close: "閉じる",
            noSelection: "選択されたテキストを読み取れませんでした。入力またはペーストしてください。",
            needsAccessibility: "選択テキストの読み取りにはアクセシビリティの許可が必要です。",
            noText: "テキストが見つかりませんでした。",
            ocrUnavailable: "スクリーンショット翻訳には画面テキスト認識を有効にしてください。",
            aiMissing: "AI 翻訳が未設定です",
            systemRequirement: "Apple 翻訳には macOS 15 以降が必要です。",
            unsupported: "この言語の組み合わせには対応していません。別の言語かサービスを選んでください。",
            configure: "AI の URL、モデル、API キーを設定してください。HTTPS を使用し、HTTP は localhost のみ可能です。",
            tooLong: "テキストが 10,000 文字を超えています。分割して翻訳してください。",
            failed: "翻訳に失敗しました。サービスや言語の設定を確認して再試行してください。",
            truncated: "翻訳が途中で切れました。分割して再試行してください。",
            privacy: "Apple 翻訳とシステム辞書はこの Mac 上で処理され、初回は言語のダウンロードが必要な場合があります。AI には、テキスト付きでウインドウを開いたときか ↩ を押したときだけ送信されます。履歴は保存しません。",
            selectionShortcut: "選択テキストを翻訳",
            inputShortcut: "入力して翻訳",
            screenshotShortcut: "スクリーンショット翻訳",
            translateSelection: "選択テキストを翻訳",
            firstLanguage: "第一言語",
            secondLanguage: "第二言語",
            directionCaption: "翻訳先が自動のとき、原文が第一言語なら第二言語へ、それ以外は第一言語へ翻訳します。",
            services: "翻訳サービス",
            dictionaryCaption: "単語や短いフレーズでは macOS の辞書の定義を表示します。",
            aiCaption: "単語やフレーズには発音、品詞、例文を返します。入力中は送信せず、↩ で送信します。",
            keysHint: "↩ 翻訳 · ⇧↩ 改行 · ⌘↩ 訳文をコピー · ⌘S 入れ替え · ⌘P 固定 · Esc 閉じる")
        case .ko: return Self(
            title: "번역",
            apple: "Apple 번역",
            ai: "AI 번역",
            dictionary: "시스템 사전",
            auto: "언어 감지",
            detectedFormat: "%@ 감지됨",
            autoTargetFormat: "%@ (자동)",
            placeholder: "번역할 텍스트 입력",
            pending: "↩ 를 눌러 AI 번역",
            copy: "복사",
            copied: "복사됨",
            speak: "읽기",
            pin: "윈도우 고정",
            unpin: "고정 해제",
            swap: "언어 바꾸기",
            settings: "번역 설정",
            close: "닫기",
            noSelection: "선택한 텍스트를 읽지 못했습니다. 직접 입력하거나 붙여넣으세요.",
            needsAccessibility: "선택한 텍스트를 읽으려면 손쉬운 사용 권한이 필요합니다.",
            noText: "텍스트를 찾지 못했습니다.",
            ocrUnavailable: "스크린샷 번역을 사용하려면 화면 텍스트 인식을 켜세요.",
            aiMissing: "AI 번역이 설정되지 않았습니다",
            systemRequirement: "Apple 번역은 macOS 15 이상이 필요합니다.",
            unsupported: "이 언어 조합은 지원되지 않습니다. 다른 언어나 서비스를 선택하세요.",
            configure: "AI 주소, 모델, API 키를 설정하세요. HTTPS를 사용하고 HTTP는 localhost에서만 허용됩니다.",
            tooLong: "텍스트가 10,000자를 넘습니다. 나누어 번역하세요.",
            failed: "번역하지 못했습니다. 서비스나 언어 설정을 확인한 뒤 다시 시도하세요.",
            truncated: "번역이 잘렸습니다. 나누어 다시 시도하세요.",
            privacy: "Apple 번역과 시스템 사전은 이 Mac에서 처리되며 처음에는 언어 다운로드가 필요할 수 있습니다. AI에는 텍스트와 함께 창을 열거나 ↩ 를 누를 때만 보냅니다. 기록은 저장하지 않습니다.",
            selectionShortcut: "선택 텍스트 번역",
            inputShortcut: "입력 번역",
            screenshotShortcut: "스크린샷 번역",
            translateSelection: "선택한 텍스트 번역",
            firstLanguage: "첫 번째 언어",
            secondLanguage: "두 번째 언어",
            directionCaption: "대상 언어가 자동이면 원문이 첫 번째 언어일 때 두 번째 언어로, 그 밖에는 첫 번째 언어로 번역합니다.",
            services: "번역 서비스",
            dictionaryCaption: "단어나 짧은 구절에는 macOS 사전의 뜻을 보여 줍니다.",
            aiCaption: "단어와 구절에는 발음, 품사, 예문을 돌려줍니다. 입력 중에는 보내지 않고 ↩ 를 눌러야 보냅니다.",
            keysHint: "↩ 번역 · ⇧↩ 줄바꿈 · ⌘↩ 번역 복사 · ⌘S 바꾸기 · ⌘P 고정 · Esc 닫기")
        default: return Self(
            title: "Translate",
            apple: "Apple Translation",
            ai: "AI Translation",
            dictionary: "System Dictionary",
            auto: "Detect language",
            detectedFormat: "Detected %@",
            autoTargetFormat: "%@ (auto)",
            placeholder: "Type text to translate",
            pending: "Press ↩ to translate with AI",
            copy: "Copy",
            copied: "Copied",
            speak: "Speak",
            pin: "Pin window",
            unpin: "Unpin window",
            swap: "Swap languages",
            settings: "Translation settings",
            close: "Close",
            noSelection: "No selected text could be read. Type or paste it here.",
            needsAccessibility: "Reading selected text needs Accessibility permission.",
            noText: "No text was found.",
            ocrUnavailable: "Screenshot translation needs Screen Text Recognition turned on.",
            aiMissing: "AI translation is not set up",
            systemRequirement: "Apple Translation requires macOS 15 or later.",
            unsupported: "This language pair is not supported. Try another language or service.",
            configure: "Configure the AI URL, model and API key. Use HTTPS (HTTP is allowed only for localhost).",
            tooLong: "Text exceeds 10,000 characters. Please split it before translating.",
            failed: "Translation failed. Check the service or language settings and retry.",
            truncated: "The translation was cut short. Split the text and retry.",
            privacy: "Apple Translation and the system dictionary work on this Mac; first use may download languages. AI receives text only when the window opens on text or you press ↩, and only your configured service. No history is kept.",
            selectionShortcut: "Translate selection",
            inputShortcut: "Translate input",
            screenshotShortcut: "Translate screenshot",
            translateSelection: "Translate selection",
            firstLanguage: "First language",
            secondLanguage: "Second language",
            directionCaption: "With the target on automatic, text in your first language goes to your second, and everything else to your first.",
            services: "Services",
            dictionaryCaption: "Shows the macOS dictionary’s definition for a word or short phrase.",
            aiCaption: "Words and phrases come back with pronunciation, parts of speech and examples. Typing never calls the AI; ↩ does.",
            keysHint: "↩ Translate · ⇧↩ New line · ⌘↩ Copy · ⌘S Swap · ⌘P Pin · Esc Close")
        }
    }
}
