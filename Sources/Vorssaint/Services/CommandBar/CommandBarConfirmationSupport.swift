// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which of the bar's own commands ask before they run. Every command keeps
/// the habit it was built with (emptying the Trash asks, sleeping does not)
/// until the person says otherwise, and what they said is kept by the row's
/// stable key, so it outlives the language and the row's position.
enum CommandBarConfirmationSupport {
    static func decode(_ raw: String?) -> [String: Bool] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        return map
    }

    static func encode(_ map: [String: Bool]) -> String {
        guard !map.isEmpty, let data = try? JSONEncoder().encode(map) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The question a row asks before running, or nil when it runs at once.
    /// A row that already had its own question keeps its wording when the
    /// person asks for one; the others get the plain "Run …?".
    static func prompt(builtIn: String?, asks: Bool?, title: String, format: String) -> String? {
        guard let asks else { return builtIn }
        guard asks else { return nil }
        return builtIn ?? String(format: format, title)
    }
}
