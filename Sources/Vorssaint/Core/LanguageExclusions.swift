// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// This build offers Chinese, English, Japanese and Korean only. The other
/// catalogs stay in the source so upstream merges keep applying cleanly; they
/// are just never picked, and strings added in this fork only need to be
/// written for the offered languages (the rest fall back to English).
extension AppLanguage {
    static let offered: [AppLanguage] = allCases.filter(\.isOffered)

    var isOffered: Bool {
        switch self {
        case .enUS, .zhHans, .ja, .ko: return true
        default: return false
        }
    }

    /// What a saved or system language not offered here becomes: Traditional
    /// Chinese reads Simplified more easily than English.
    var offeredFallback: AppLanguage {
        if isOffered { return self }
        switch self {
        case .zhTW, .zhHK: return .zhHans
        default: return .enUS
        }
    }
}
