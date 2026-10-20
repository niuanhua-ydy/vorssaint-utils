// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsNewStrings {
    /// The %@ is the version the person updated from, such as 3.4.1.
    let updatedFromFormat: String
    let newFeatures: String
    /// Installed features that changed in this update.
    let yourFeatures: String
    let notInstalled: String
    /// The three kinds head a feature's list of changes and label the counts on
    /// the overview, so they must read well both above a list and under a number.
    let kindNew: String
    let kindChanged: String
    let kindFixed: String
    /// VoiceOver value for a sidebar row whose unread dot is showing.
    let updated: String
    let chooseFeatureHint: String
}

extension FeatureStrings {
    static func whatsNew(_ language: AppLanguage) -> WhatsNewStrings {
        switch language {
        case .enUS:
            return WhatsNewStrings(
                updatedFromFormat: "Updated from %@",
                newFeatures: "New features",
                yourFeatures: "Your features",
                notInstalled: "Not installed",
                kindNew: "New",
                kindChanged: "Changed",
                kindFixed: "Fixed",
                updated: "Updated",
                chooseFeatureHint: "Choose a feature to see what changed in it.")
        case .ptBR:
            return WhatsNewStrings(
                updatedFromFormat: "Atualizado da versão %@",
                newFeatures: "Novos recursos",
                yourFeatures: "Seus recursos",
                notInstalled: "Não instalados",
                kindNew: "Novidades",
                kindChanged: "Mudanças",
                kindFixed: "Correções",
                updated: "Atualizado",
                chooseFeatureHint: "Escolha um recurso para ver o que mudou nele.")
        case .tr:
            return WhatsNewStrings(
                updatedFromFormat: "%@ sürümünden güncellendi",
                newFeatures: "Yeni özellikler",
                yourFeatures: "Özellikleriniz",
                notInstalled: "Yüklü olmayanlar",
                kindNew: "Yeni",
                kindChanged: "Değişen",
                kindFixed: "Düzeltilen",
                updated: "Güncellendi",
                chooseFeatureHint: "Neyin değiştiğini görmek için bir özellik seçin.")
        case .ru:
            return WhatsNewStrings(
                updatedFromFormat: "Обновлено с версии %@",
                newFeatures: "Новые функции",
                yourFeatures: "Ваши функции",
                notInstalled: "Не установлено",
                kindNew: "Новое",
                kindChanged: "Изменено",
                kindFixed: "Исправлено",
                updated: "Обновлено",
                chooseFeatureHint: "Выберите функцию, чтобы увидеть, что в ней изменилось.")
        case .es:
            return WhatsNewStrings(
                updatedFromFormat: "Actualizado desde la versión %@",
                newFeatures: "Nuevas funciones",
                yourFeatures: "Tus funciones",
                notInstalled: "No instaladas",
                kindNew: "Novedades",
                kindChanged: "Cambios",
                kindFixed: "Correcciones",
                updated: "Actualizada",
                chooseFeatureHint: "Elige una función para ver sus cambios.")
        case .sk:
            return WhatsNewStrings(
                updatedFromFormat: "Aktualizované z verzie %@",
                newFeatures: "Nové funkcie",
                yourFeatures: "Vaše funkcie",
                notInstalled: "Nenainštalované",
                kindNew: "Nové",
                kindChanged: "Zmenené",
                kindFixed: "Opravené",
                updated: "Aktualizované",
                chooseFeatureHint: "Vyberte funkciu a pozrite si, čo sa v nej zmenilo.")
        case .de:
            return WhatsNewStrings(
                updatedFromFormat: "Aktualisiert von Version %@",
                newFeatures: "Neue Funktionen",
                yourFeatures: "Deine Funktionen",
                notInstalled: "Nicht installiert",
                kindNew: "Neu",
                kindChanged: "Geändert",
                kindFixed: "Behoben",
                updated: "Aktualisiert",
                chooseFeatureHint: "Wähle eine Funktion, um zu sehen, was sich geändert hat.")
        case .fr:
            return WhatsNewStrings(
                updatedFromFormat: "Mis à jour depuis la version %@",
                newFeatures: "Nouvelles fonctions",
                yourFeatures: "Vos fonctions",
                notInstalled: "Non installées",
                kindNew: "Nouveautés",
                kindChanged: "Modifications",
                kindFixed: "Corrections",
                updated: "Mise à jour",
                chooseFeatureHint: "Choisissez une fonction pour voir ce qui a changé.")
        case .it:
            return WhatsNewStrings(
                updatedFromFormat: "Aggiornato dalla versione %@",
                newFeatures: "Nuove funzioni",
                yourFeatures: "Le tue funzioni",
                notInstalled: "Non installate",
                kindNew: "Novità",
                kindChanged: "Modifiche",
                kindFixed: "Correzioni",
                updated: "Aggiornata",
                chooseFeatureHint: "Scegli una funzione per vedere cosa è cambiato.")
        case .ja:
            return WhatsNewStrings(
                updatedFromFormat: "バージョン%@からアップデート",
                newFeatures: "新しい機能",
                yourFeatures: "インストール済みの機能",
                notInstalled: "未インストール",
                kindNew: "新規",
                kindChanged: "変更",
                kindFixed: "修正",
                updated: "アップデート済み",
                chooseFeatureHint: "機能を選択すると、変更内容が表示されます。")
        case .ko:
            return WhatsNewStrings(
                updatedFromFormat: "버전 %@에서 업데이트됨",
                newFeatures: "새 기능",
                yourFeatures: "설치된 기능",
                notInstalled: "설치되지 않음",
                kindNew: "신규",
                kindChanged: "변경",
                kindFixed: "수정",
                updated: "업데이트됨",
                chooseFeatureHint: "기능을 선택하면 변경된 내용을 볼 수 있습니다.")
        case .uk:
            return WhatsNewStrings(
                updatedFromFormat: "Оновлено з версії %@",
                newFeatures: "Нові функції",
                yourFeatures: "Ваші функції",
                notInstalled: "Не встановлено",
                kindNew: "Нове",
                kindChanged: "Змінено",
                kindFixed: "Виправлено",
                updated: "Оновлено",
                chooseFeatureHint: "Виберіть функцію, щоб побачити, що в ній змінилося.")
        case .zhHans:
            return WhatsNewStrings(
                updatedFromFormat: "已从版本 %@ 更新",
                newFeatures: "新增功能",
                yourFeatures: "已安装的功能",
                notInstalled: "未安装",
                kindNew: "新增",
                kindChanged: "变更",
                kindFixed: "修复",
                updated: "已更新",
                chooseFeatureHint: "选择一个功能以查看其中的变化。")
        case .zhTW, .zhHK:
            return WhatsNewStrings(
                updatedFromFormat: "已從版本 %@ 更新",
                newFeatures: "新增功能",
                yourFeatures: "已安裝的功能",
                notInstalled: "未安裝",
                kindNew: "新增",
                kindChanged: "變更",
                kindFixed: "修正",
                updated: "已更新",
                chooseFeatureHint: "選擇一個功能以查看其中的變化。")
        }
    }
}
