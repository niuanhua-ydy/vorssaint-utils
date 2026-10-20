// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The labels of the command bar's detail pane, the column beside the list
/// that describes the selected row. Kept apart from the bar's own strings so
/// the fields added here never collide with the ones upstream adds there.
struct CommandBarDetailStrings {
    let path: String
    let version: String
    let created: String
    let modified: String
    let lastOpened: String
    let size: String
    let alias: String
    let shortcut: String
    let copyPath: String
}

extension FeatureStrings {
    static func commandBarDetail(_ language: AppLanguage) -> CommandBarDetailStrings {
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

extension CommandBarDetailStrings {
    static let enUS = CommandBarDetailStrings(
        path: "Path", version: "Version", created: "Created", modified: "Modified",
        lastOpened: "Last opened", size: "Size", alias: "Alias", shortcut: "Shortcut",
        copyPath: "Copy Path")

    static let ptBR = CommandBarDetailStrings(
        path: "Caminho", version: "Versão", created: "Criado", modified: "Modificado",
        lastOpened: "Última abertura", size: "Tamanho", alias: "Apelido", shortcut: "Atalho",
        copyPath: "Copiar caminho")

    static let tr = CommandBarDetailStrings(
        path: "Yol", version: "Sürüm", created: "Oluşturulma", modified: "Değiştirilme",
        lastOpened: "Son açılış", size: "Boyut", alias: "Takma ad", shortcut: "Kısayol",
        copyPath: "Yolu kopyala")

    static let ru = CommandBarDetailStrings(
        path: "Путь", version: "Версия", created: "Создано", modified: "Изменено",
        lastOpened: "Последнее открытие", size: "Размер", alias: "Псевдоним", shortcut: "Сочетание",
        copyPath: "Скопировать путь")

    static let es = CommandBarDetailStrings(
        path: "Ruta", version: "Versión", created: "Creado", modified: "Modificado",
        lastOpened: "Última apertura", size: "Tamaño", alias: "Alias", shortcut: "Atajo",
        copyPath: "Copiar ruta")

    static let sk = CommandBarDetailStrings(
        path: "Cesta", version: "Verzia", created: "Vytvorené", modified: "Zmenené",
        lastOpened: "Naposledy otvorené", size: "Veľkosť", alias: "Alias", shortcut: "Skratka",
        copyPath: "Kopírovať cestu")

    static let de = CommandBarDetailStrings(
        path: "Pfad", version: "Version", created: "Erstellt", modified: "Geändert",
        lastOpened: "Zuletzt geöffnet", size: "Größe", alias: "Alias", shortcut: "Kurzbefehl",
        copyPath: "Pfad kopieren")

    static let fr = CommandBarDetailStrings(
        path: "Chemin", version: "Version", created: "Création", modified: "Modification",
        lastOpened: "Dernière ouverture", size: "Taille", alias: "Alias", shortcut: "Raccourci",
        copyPath: "Copier le chemin")

    static let it = CommandBarDetailStrings(
        path: "Percorso", version: "Versione", created: "Creato", modified: "Modificato",
        lastOpened: "Ultima apertura", size: "Dimensione", alias: "Alias", shortcut: "Scorciatoia",
        copyPath: "Copia percorso")

    static let ja = CommandBarDetailStrings(
        path: "パス", version: "バージョン", created: "作成日", modified: "変更日",
        lastOpened: "最後に開いた日", size: "サイズ", alias: "エイリアス", shortcut: "ショートカット",
        copyPath: "パスをコピー")

    static let ko = CommandBarDetailStrings(
        path: "경로", version: "버전", created: "생성일", modified: "수정일",
        lastOpened: "마지막으로 열람", size: "크기", alias: "별칭", shortcut: "단축키",
        copyPath: "경로 복사")

    static let zhHans = CommandBarDetailStrings(
        path: "路径", version: "版本", created: "创建时间", modified: "修改时间",
        lastOpened: "上次打开", size: "大小", alias: "别名", shortcut: "快捷键",
        copyPath: "拷贝路径")

    static let zhTW = CommandBarDetailStrings(
        path: "路徑", version: "版本", created: "建立時間", modified: "修改時間",
        lastOpened: "上次打開", size: "大小", alias: "別名", shortcut: "快速鍵",
        copyPath: "拷貝路徑")

    static let zhHK = CommandBarDetailStrings(
        path: "路徑", version: "版本", created: "建立時間", modified: "修改時間",
        lastOpened: "上次開啟", size: "大小", alias: "別名", shortcut: "快速鍵",
        copyPath: "拷貝路徑")

    static let uk = CommandBarDetailStrings(
        path: "Шлях", version: "Версія", created: "Створено", modified: "Змінено",
        lastOpened: "Востаннє відкрито", size: "Розмір", alias: "Псевдонім", shortcut: "Сполучення",
        copyPath: "Скопіювати шлях")
}
