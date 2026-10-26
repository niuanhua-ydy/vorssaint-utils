// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct CommandBarTranslationStrings {
    let title: String
    let system: String
    let auto: String
    let source: String
    let target: String
    let result: String
    let privacy: String
    let systemRequirement: String
    let unsupported: String
    let configure: String
    let tooLong: String
    let failed: String
    let truncated: String

    static func strings(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return Self(
            title: "Translate",
            system: "Apple Translation",
            auto: "Detect language",
            source: "Source",
            target: "Target",
            result: "Translation",
            privacy: "Apple translates on device; first use may download languages. AI sends text only when you translate, to your configured service. No translation history is saved.",
            systemRequirement: "Apple Translation requires macOS 15 or later. You can use AI instead.",
            unsupported: "This language pair is not supported. Try selecting the source language or another service.",
            configure: "Configure the AI URL, model and API key in Command Bar settings. Use HTTPS (HTTP is allowed only for localhost).",
            tooLong: "Text exceeds 10,000 characters. Please split it before translating.",
            failed: "Translation failed. Check the service or language settings and retry.",
            truncated: "The translation was cut short. Split the text and retry.")
        case .zhHans: return Self(
            title: "翻译",
            system: "Apple 系统翻译",
            auto: "自动检测",
            source: "原文语言",
            target: "译文语言",
            result: "译文",
            privacy: "系统翻译在本机处理，首次使用可能下载语言包。AI 仅在主动翻译时向配置的服务发送文本。不保存翻译历史。",
            systemRequirement: "系统翻译需要 macOS 15 或更高版本，也可改用 AI 翻译。",
            unsupported: "不支持此语言组合，请指定原文语言或切换服务。",
            configure: "请在命令栏设置中配置 AI 地址、模型和 API Key。使用 HTTPS，仅本机地址允许 HTTP。",
            tooLong: "文本超过 10,000 字，请分段翻译。",
            failed: "翻译失败，请检查服务或语言设置后重试。",
            truncated: "译文被截断，请分段后重试。")
        case .zhTW: return Self(
            title: "翻譯",
            system: "Apple 系統翻譯",
            auto: "自動偵測",
            source: "原文語言",
            target: "譯文語言",
            result: "譯文",
            privacy: "系統翻譯在本機處理，首次使用可能下載語言套件。AI 僅在主動翻譯時向設定的服務傳送文字。不儲存翻譯記錄。",
            systemRequirement: "系統翻譯需要 macOS 15 或更新版本，也可改用 AI 翻譯。",
            unsupported: "不支援此語言組合，請指定原文語言或切換服務。",
            configure: "請在命令列設定中設定 AI 網址、模型和 API Key。使用 HTTPS，僅本機網址允許 HTTP。",
            tooLong: "文字超過 10,000 字，請分段翻譯。",
            failed: "翻譯失敗，請檢查服務或語言設定後重試。",
            truncated: "譯文被截斷，請分段後重試。")
        case .zhHK: return Self(
            title: "翻譯",
            system: "Apple 系統翻譯",
            auto: "自動偵測",
            source: "原文語言",
            target: "譯文語言",
            result: "譯文",
            privacy: "系統翻譯在本機處理，首次使用可能下載語言套件。AI 僅在主動翻譯時向設定的服務傳送文字。不儲存翻譯記錄。",
            systemRequirement: "系統翻譯需要 macOS 15 或更新版本，也可改用 AI 翻譯。",
            unsupported: "不支援此語言組合，請指定原文語言或切換服務。",
            configure: "請在命令列設定中設定 AI 網址、模型和 API Key。使用 HTTPS，僅本機網址允許 HTTP。",
            tooLong: "文字超過 10,000 字，請分段翻譯。",
            failed: "翻譯失敗，請檢查服務或語言設定後重試。",
            truncated: "譯文被截斷，請分段後重試。")
        case .ja: return Self(
            title: "翻訳",
            system: "Apple 翻訳",
            auto: "言語を検出",
            source: "原文の言語",
            target: "訳文の言語",
            result: "訳文",
            privacy: "Apple は端末上で翻訳します。初回は言語のダウンロードが必要な場合があります。AI は翻訳を実行した時だけ設定したサービスにテキストを送信します。履歴は保存しません。",
            systemRequirement: "Apple 翻訳には macOS 15 以降が必要です。AI も利用できます。",
            unsupported: "この言語の組み合わせは未対応です。原文の言語かサービスを変更してください。",
            configure: "コマンドバー設定で AI の URL、モデル、API キーを設定してください。HTTPS を使用します（HTTP は localhost のみ）。",
            tooLong: "10,000 文字を超えています。分割して翻訳してください。",
            failed: "翻訳に失敗しました。サービスと言語設定を確認して再試行してください。",
            truncated: "訳文が途中で切れました。分割して再試行してください。")
        case .ko: return Self(
            title: "번역",
            system: "Apple 번역",
            auto: "언어 감지",
            source: "원문 언어",
            target: "번역 언어",
            result: "번역문",
            privacy: "Apple은 기기에서 번역하며 처음에는 언어 다운로드가 필요할 수 있습니다. AI는 번역을 실행할 때만 설정된 서비스에 텍스트를 보냅니다. 기록은 저장하지 않습니다.",
            systemRequirement: "Apple 번역은 macOS 15 이상이 필요합니다. AI를 사용할 수도 있습니다.",
            unsupported: "지원하지 않는 언어 조합입니다. 원문 언어나 서비스를 변경하세요.",
            configure: "명령 막대 설정에서 AI URL, 모델, API 키를 설정하세요. HTTPS를 사용하세요(HTTP는 localhost만 허용).",
            tooLong: "10,000자를 초과했습니다. 나눠서 번역하세요.",
            failed: "번역에 실패했습니다. 서비스 또는 언어 설정을 확인하고 다시 시도하세요.",
            truncated: "번역이 잘렸습니다. 텍스트를 나눠서 다시 시도하세요.")
        case .de: return Self(
            title: "Übersetzen",
            system: "Apple Übersetzen",
            auto: "Sprache erkennen",
            source: "Ausgangssprache",
            target: "Zielsprache",
            result: "Übersetzung",
            privacy: "Apple übersetzt lokal; beim ersten Mal können Sprachdownloads nötig sein. AI sendet Text nur beim Übersetzen an den konfigurierten Dienst. Kein Verlauf wird gespeichert.",
            systemRequirement: "Apple Übersetzen benötigt macOS 15 oder neuer. Alternativ AI verwenden.",
            unsupported: "Dieses Sprachpaar wird nicht unterstützt. Ausgangssprache oder Dienst ändern.",
            configure: "AI-URL, Modell und API-Schlüssel in den Befehlsleisten-Einstellungen konfigurieren. HTTPS verwenden (HTTP nur für localhost).",
            tooLong: "Mehr als 10.000 Zeichen. Text zum Übersetzen aufteilen.",
            failed: "Übersetzung fehlgeschlagen. Dienst- oder Spracheinstellungen prüfen und erneut versuchen.",
            truncated: "Übersetzung abgeschnitten. Text aufteilen und erneut versuchen.")
        case .fr: return Self(
            title: "Traduire",
            system: "Traduction Apple",
            auto: "Détecter la langue",
            source: "Langue source",
            target: "Langue cible",
            result: "Traduction",
            privacy: "Apple traduit sur cet appareil ; des langues peuvent être téléchargées au premier usage. AI envoie le texte au service configuré uniquement à votre demande. Aucun historique conservé.",
            systemRequirement: "La traduction Apple nécessite macOS 15 ou ultérieur. Vous pouvez utiliser AI.",
            unsupported: "Cette paire de langues est indisponible. Choisissez la langue source ou un autre service.",
            configure: "Configurez URL, modèle et clé API dans les réglages de la barre de commandes. Utilisez HTTPS (HTTP uniquement pour localhost).",
            tooLong: "Plus de 10 000 caractères. Divisez le texte avant de traduire.",
            failed: "Échec de traduction. Vérifiez le service ou les langues et réessayez.",
            truncated: "Traduction tronquée. Divisez le texte et réessayez.")
        case .es: return Self(
            title: "Traducir",
            system: "Traducción de Apple",
            auto: "Detectar idioma",
            source: "Idioma de origen",
            target: "Idioma de destino",
            result: "Traducción",
            privacy: "Apple traduce en el dispositivo; puede descargar idiomas la primera vez. AI solo envía texto al servicio configurado al traducir. No se guarda historial.",
            systemRequirement: "La traducción de Apple requiere macOS 15 o posterior. También puedes usar AI.",
            unsupported: "Esta combinación de idiomas no es compatible. Selecciona el idioma de origen u otro servicio.",
            configure: "Configura URL, modelo y clave API en los ajustes de la barra de comandos. Usa HTTPS (HTTP solo para localhost).",
            tooLong: "Más de 10.000 caracteres. Divide el texto para traducir.",
            failed: "Error de traducción. Revisa el servicio o los idiomas e inténtalo de nuevo.",
            truncated: "Traducción truncada. Divide el texto e inténtalo de nuevo.")
        case .it: return Self(
            title: "Traduci",
            system: "Traduzione Apple",
            auto: "Rileva lingua",
            source: "Lingua di origine",
            target: "Lingua di destinazione",
            result: "Traduzione",
            privacy: "Apple traduce sul dispositivo; al primo uso potrebbe scaricare le lingue. AI invia il testo al servizio configurato solo quando traduci. Nessuna cronologia salvata.",
            systemRequirement: "La traduzione Apple richiede macOS 15 o successivo. Puoi usare AI.",
            unsupported: "Coppia di lingue non supportata. Seleziona la lingua di origine o un altro servizio.",
            configure: "Configura URL, modello e chiave API nelle impostazioni della barra dei comandi. Usa HTTPS (HTTP solo per localhost).",
            tooLong: "Oltre 10.000 caratteri. Dividi il testo prima di tradurre.",
            failed: "Traduzione non riuscita. Controlla il servizio o le lingue e riprova.",
            truncated: "Traduzione troncata. Dividi il testo e riprova.")
        case .ptBR: return Self(
            title: "Traduzir",
            system: "Tradução da Apple",
            auto: "Detectar idioma",
            source: "Idioma de origem",
            target: "Idioma de destino",
            result: "Tradução",
            privacy: "A Apple traduz no dispositivo; pode baixar idiomas no primeiro uso. AI envia texto ao serviço configurado somente ao traduzir. Nenhum histórico é salvo.",
            systemRequirement: "A tradução da Apple exige macOS 15 ou posterior. Você pode usar AI.",
            unsupported: "Par de idiomas não suportado. Selecione o idioma de origem ou outro serviço.",
            configure: "Configure URL, modelo e chave API nos ajustes da barra de comandos. Use HTTPS (HTTP somente para localhost).",
            tooLong: "Mais de 10.000 caracteres. Divida o texto para traduzir.",
            failed: "Falha na tradução. Confira o serviço ou os idiomas e tente novamente.",
            truncated: "Tradução truncada. Divida o texto e tente novamente.")
        case .ru: return Self(
            title: "Перевести",
            system: "Перевод Apple",
            auto: "Определить язык",
            source: "Исходный язык",
            target: "Язык перевода",
            result: "Перевод",
            privacy: "Apple переводит на устройстве; при первом запуске может потребоваться загрузка языков. AI отправляет текст выбранному сервису только по команде перевода. История не сохраняется.",
            systemRequirement: "Для перевода Apple нужна macOS 15 или новее. Можно использовать AI.",
            unsupported: "Эта пара языков не поддерживается. Выберите исходный язык или другой сервис.",
            configure: "Укажите URL, модель и API-ключ в настройках командной строки. Используйте HTTPS (HTTP только для localhost).",
            tooLong: "Более 10 000 символов. Разделите текст перед переводом.",
            failed: "Не удалось перевести. Проверьте сервис и языки, затем повторите.",
            truncated: "Перевод обрезан. Разделите текст и повторите.")
        case .uk: return Self(
            title: "Перекласти",
            system: "Переклад Apple",
            auto: "Визначити мову",
            source: "Вихідна мова",
            target: "Мова перекладу",
            result: "Переклад",
            privacy: "Apple перекладає на пристрої; спочатку може знадобитися завантаження мов. AI надсилає текст налаштованому сервісу лише за командою перекладу. Історія не зберігається.",
            systemRequirement: "Переклад Apple потребує macOS 15 або новішої. Можна використати AI.",
            unsupported: "Ця пара мов не підтримується. Виберіть вихідну мову або інший сервіс.",
            configure: "Укажіть URL, модель і API-ключ у налаштуваннях командного рядка. Використовуйте HTTPS (HTTP лише для localhost).",
            tooLong: "Понад 10 000 символів. Розділіть текст для перекладу.",
            failed: "Не вдалося перекласти. Перевірте сервіс і мови та повторіть.",
            truncated: "Переклад обрізано. Розділіть текст і повторіть.")
        case .sk: return Self(
            title: "Preložiť",
            system: "Preklad Apple",
            auto: "Zistiť jazyk",
            source: "Zdrojový jazyk",
            target: "Cieľový jazyk",
            result: "Preklad",
            privacy: "Apple prekladá na zariadení; pri prvom použití môže stiahnuť jazyky. AI odošle text nastavenému poskytovateľovi len pri preklade. História sa neukladá.",
            systemRequirement: "Preklad Apple vyžaduje macOS 15 alebo novší. Môžete použiť AI.",
            unsupported: "Táto dvojica jazykov nie je podporovaná. Vyberte zdrojový jazyk alebo inú službu.",
            configure: "Nastavte URL, model a API kľúč v nastaveniach panela príkazov. Použite HTTPS (HTTP len pre localhost).",
            tooLong: "Viac ako 10 000 znakov. Rozdeľte text pred prekladom.",
            failed: "Preklad zlyhal. Skontrolujte službu alebo jazyky a skúste znova.",
            truncated: "Preklad bol skrátený. Rozdeľte text a skúste znova.")
        case .tr: return Self(
            title: "Çevir",
            system: "Apple Çeviri",
            auto: "Dili algıla",
            source: "Kaynak dil",
            target: "Hedef dil",
            result: "Çeviri",
            privacy: "Apple aygıtta çevirir; ilk kullanımda diller indirilebilir. AI, metni yalnızca çeviri istediğinizde ayarlanan hizmete gönderir. Geçmiş kaydedilmez.",
            systemRequirement: "Apple Çeviri macOS 15 veya üstünü gerektirir. AI da kullanabilirsiniz.",
            unsupported: "Bu dil çifti desteklenmiyor. Kaynak dili veya hizmeti değiştirin.",
            configure: "Komut çubuğu ayarlarında AI URL, model ve API anahtarını yapılandırın. HTTPS kullanın (HTTP yalnızca localhost için).",
            tooLong: "10.000 karakter aşıldı. Çevirmeden önce metni bölün.",
            failed: "Çeviri başarısız. Hizmet veya dil ayarlarını kontrol edip tekrar deneyin.",
            truncated: "Çeviri kesildi. Metni bölüp tekrar deneyin.")
        }
    }
}
