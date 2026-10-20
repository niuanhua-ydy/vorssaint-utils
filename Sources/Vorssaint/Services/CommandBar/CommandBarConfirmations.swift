// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rows side of `CommandBarConfirmationSupport`: which rows take the
/// choice, and the rows rebuilt with it.
enum CommandBarConfirmations {
    /// Only commands take the choice: an app opening or a page showing has
    /// nothing worth a second thought, and a row that steps into a list or
    /// waits for a number already stops on its own.
    static func accepts(_ entry: CommandBarEntry) -> Bool {
        CommandBarPreferences.isActionRow(entry.id)
            && CommandBarPreferences.acceptsAlias(rowID: entry.id)
            && !entry.keepsBarOpen && entry.uninstallAppURL == nil
            && (entry.numericRange == nil || entry.numericIsOptional)
    }

    /// The rows as the person wants them: a prompt added where they asked
    /// for one, the built-in one dropped where they asked for none.
    static func applied(to entries: [CommandBarEntry], map: [String: Bool],
                        promptFormat: String) -> [CommandBarEntry] {
        guard !map.isEmpty else { return entries }
        return entries.map { entry in
            guard let asks = map[entry.stableKey], accepts(entry) else { return entry }
            let prompt = CommandBarConfirmationSupport.prompt(
                builtIn: entry.confirmationPrompt, asks: asks, title: entry.title, format: promptFormat)
            return prompt == entry.confirmationPrompt ? entry : entry.withConfirmationPrompt(prompt)
        }
    }
}

extension CommandBarEntry {
    func withConfirmationPrompt(_ prompt: String?) -> CommandBarEntry {
        CommandBarEntry(id: id, stableKey: stableKey, title: title, subtitle: subtitle,
                        keywords: keywords, icon: icon, shortcut: shortcut,
                        menuShortcut: menuShortcut, isActive: isActive, trouble: trouble,
                        numericRange: numericRange, numericIsOptional: numericIsOptional,
                        confirmationPrompt: prompt, answerValue: answerValue,
                        isAnswer: isAnswer, countsUsage: countsUsage,
                        matchTitle: matchTitle, keepsBarOpen: keepsBarOpen,
                        takesArgument: takesArgument, revealPath: revealPath,
                        uninstallAppURL: uninstallAppURL, run: run)
    }
}
