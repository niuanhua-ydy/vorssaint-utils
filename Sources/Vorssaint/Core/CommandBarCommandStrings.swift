// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command table in Command Bar settings, where the bar’s own commands
/// get their search names, shortcuts and whether they ask before running.
struct CommandBarCommandStrings {
    let title: String
    let caption: String
    let commandColumn: String
    let confirmColumn: String
    let confirmPromptFormat: String
    let askBeforeRunning: String
    let stopAsking: String
}

extension FeatureStrings {
    static func commandBarCommands(_ language: AppLanguage) -> CommandBarCommandStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension CommandBarCommandStrings {
    static let enUS = CommandBarCommandStrings(
        title: "Command shortcuts",
        caption: "Give the bar’s own commands search names and shortcuts, and choose which ones ask before they run.",
        commandColumn: "Command",
        confirmColumn: "Confirm",
        confirmPromptFormat: "Run “%@”?",
        askBeforeRunning: "Ask Before Running",
        stopAsking: "Stop Asking Before Running")

    static let ptBR = CommandBarCommandStrings(
        title: "Atalhos de comandos",
        caption: "Dê nomes de busca e atalhos aos comandos da barra e escolha quais pedem confirmação antes de rodar.",
        commandColumn: "Comando",
        confirmColumn: "Confirmar",
        confirmPromptFormat: "Executar “%@”?",
        askBeforeRunning: "Perguntar antes de executar",
        stopAsking: "Não perguntar antes de executar")

    static let tr = CommandBarCommandStrings(
        title: "Komut kısayolları",
        caption: "Çubuğun komutlarına arama adları ve kısayollar verin, hangilerinin çalışmadan önce soracağını seçin.",
        commandColumn: "Komut",
        confirmColumn: "Onay",
        confirmPromptFormat: "“%@” çalıştırılsın mı?",
        askBeforeRunning: "Çalıştırmadan önce sor",
        stopAsking: "Çalıştırmadan önce sorma")

    static let ru = CommandBarCommandStrings(
        title: "Сочетания для команд",
        caption: "Задайте командам панели имена для поиска и сочетания клавиш и выберите, какие из них спрашивают подтверждение.",
        commandColumn: "Команда",
        confirmColumn: "Подтверждение",
        confirmPromptFormat: "Выполнить «%@»?",
        askBeforeRunning: "Спрашивать перед запуском",
        stopAsking: "Не спрашивать перед запуском")

    static let es = CommandBarCommandStrings(
        title: "Atajos de comandos",
        caption: "Da nombres de búsqueda y atajos a los comandos de la barra y elige cuáles preguntan antes de ejecutarse.",
        commandColumn: "Comando",
        confirmColumn: "Confirmar",
        confirmPromptFormat: "¿Ejecutar “%@”?",
        askBeforeRunning: "Preguntar antes de ejecutar",
        stopAsking: "No preguntar antes de ejecutar")

    static let sk = CommandBarCommandStrings(
        title: "Skratky príkazov",
        caption: "Dajte príkazom lišty vyhľadávacie názvy a skratky a vyberte, ktoré sa pred spustením opýtajú.",
        commandColumn: "Príkaz",
        confirmColumn: "Potvrdenie",
        confirmPromptFormat: "Spustiť „%@“?",
        askBeforeRunning: "Pýtať sa pred spustením",
        stopAsking: "Nepýtať sa pred spustením")

    static let de = CommandBarCommandStrings(
        title: "Befehlskurzbefehle",
        caption: "Gib den Befehlen der Leiste Suchnamen und Kurzbefehle und wähle, welche vor dem Ausführen nachfragen.",
        commandColumn: "Befehl",
        confirmColumn: "Bestätigen",
        confirmPromptFormat: "„%@“ ausführen?",
        askBeforeRunning: "Vor dem Ausführen fragen",
        stopAsking: "Nicht mehr vor dem Ausführen fragen")

    static let fr = CommandBarCommandStrings(
        title: "Raccourcis des commandes",
        caption: "Donnez aux commandes de la barre des noms de recherche et des raccourcis, et choisissez lesquelles demandent confirmation.",
        commandColumn: "Commande",
        confirmColumn: "Confirmer",
        confirmPromptFormat: "Exécuter « %@ » ?",
        askBeforeRunning: "Demander avant d’exécuter",
        stopAsking: "Ne plus demander avant d’exécuter")

    static let it = CommandBarCommandStrings(
        title: "Scorciatoie dei comandi",
        caption: "Assegna ai comandi della barra nomi di ricerca e scorciatoie e scegli quali chiedono conferma prima di essere eseguiti.",
        commandColumn: "Comando",
        confirmColumn: "Conferma",
        confirmPromptFormat: "Eseguire “%@”?",
        askBeforeRunning: "Chiedi prima di eseguire",
        stopAsking: "Non chiedere prima di eseguire")

    static let ja = CommandBarCommandStrings(
        title: "コマンドのショートカット",
        caption: "バーのコマンドに検索名とショートカットを設定し、実行前に確認するものを選びます。",
        commandColumn: "コマンド",
        confirmColumn: "確認",
        confirmPromptFormat: "“%@”を実行しますか？",
        askBeforeRunning: "実行前に確認",
        stopAsking: "実行前に確認しない")

    static let ko = CommandBarCommandStrings(
        title: "명령 단축키",
        caption: "막대의 명령에 검색 이름과 단축키를 지정하고, 실행 전에 확인할 명령을 고릅니다.",
        commandColumn: "명령",
        confirmColumn: "확인",
        confirmPromptFormat: "‘%@’을(를) 실행할까요?",
        askBeforeRunning: "실행 전에 확인",
        stopAsking: "실행 전에 확인 안 함")

    static let zhHans = CommandBarCommandStrings(
        title: "命令别名与确认",
        caption: "为命令栏自带的命令设置搜索别名和快捷键，并选择哪些命令执行前需要二次确认。",
        commandColumn: "命令",
        confirmColumn: "二次确认",
        confirmPromptFormat: "确定要执行「%@」吗？",
        askBeforeRunning: "执行前确认",
        stopAsking: "执行前不再确认")

    static let zhTW = CommandBarCommandStrings(
        title: "指令別名與確認",
        caption: "為指令列內建的指令設定搜尋別名和快速鍵，並選擇哪些指令執行前需要再次確認。",
        commandColumn: "指令",
        confirmColumn: "再次確認",
        confirmPromptFormat: "確定要執行「%@」嗎？",
        askBeforeRunning: "執行前確認",
        stopAsking: "執行前不再確認")

    static let zhHK = CommandBarCommandStrings(
        title: "指令別名與確認",
        caption: "為指令列內建嘅指令設定搜尋別名同快速鍵，並揀選邊啲指令執行前需要再次確認。",
        commandColumn: "指令",
        confirmColumn: "再次確認",
        confirmPromptFormat: "確定要執行「%@」嗎？",
        askBeforeRunning: "執行前確認",
        stopAsking: "執行前不再確認")

    static let uk = CommandBarCommandStrings(
        title: "Сполучення для команд",
        caption: "Задайте командам панелі назви для пошуку й сполучення клавіш і виберіть, які з них питають підтвердження.",
        commandColumn: "Команда",
        confirmColumn: "Підтвердження",
        confirmPromptFormat: "Виконати «%@»?",
        askBeforeRunning: "Питати перед запуском",
        stopAsking: "Не питати перед запуском")
}
