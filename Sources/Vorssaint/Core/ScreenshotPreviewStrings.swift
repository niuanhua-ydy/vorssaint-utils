// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Fork-only screenshot preview strings: how long the preview stays and the
/// keys that act on it while the pointer rests there.
struct ScreenshotPreviewStrings {
    let durationLabel: String
    let hoverKeysCaption: String

    static func strings(_ language: AppLanguage) -> Self {
        switch language {
        case .zhHans: return Self(
            durationLabel: "缩略图停留时长",
            hoverKeysCaption: "鼠标停在缩略图上即可直接按键，不用点击：E 编辑、⌘C 复制、⌘S 保存、⌘P 钉住、⌫ 删除、Esc 关闭。需要辅助功能权限，没有时先点一下缩略图。")
        case .ja: return Self(
            durationLabel: "プレビューの表示時間",
            hoverKeysCaption: "プレビューにポインタを置くと、クリックせずにキーで操作できます：E 編集、⌘C コピー、⌘S 保存、⌘P ピン留め、⌫ 削除、Esc 閉じる。アクセシビリティの許可が必要です。ない場合は先にプレビューをクリックしてください。")
        case .ko: return Self(
            durationLabel: "미리보기 표시 시간",
            hoverKeysCaption: "미리보기에 포인터를 올리면 클릭 없이 키로 조작할 수 있습니다: E 편집, ⌘C 복사, ⌘S 저장, ⌘P 고정, ⌫ 삭제, Esc 닫기. 손쉬운 사용 권한이 필요하며, 없으면 먼저 미리보기를 클릭하세요.")
        // Only the offered languages are written; see LanguageExclusions.
        default: return Self(
            durationLabel: "Preview stays",
            hoverKeysCaption: "Point at the preview to use its keys without clicking: E edit, ⌘C copy, ⌘S save, ⌘P pin, ⌫ delete, Esc close. Needs Accessibility; without it, click the preview first.")
        }
    }
}
