// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarConfirmationTests {
    static func run(_ suite: TestSuite) {
        let format = "Run “%@”?"
        suite.expect(CommandBarConfirmationSupport.prompt(builtIn: "Empty the Trash?", asks: nil,
                                                         title: "Empty Trash", format: format) == "Empty the Trash?",
                     "a command nobody chose for keeps the question it was built with")
        suite.expect(CommandBarConfirmationSupport.prompt(builtIn: nil, asks: nil,
                                                         title: "Sleep", format: format) == nil,
                     "a command nobody chose for still runs at once when it always did")
        suite.expect(CommandBarConfirmationSupport.prompt(builtIn: "Empty the Trash?", asks: false,
                                                         title: "Empty Trash", format: format) == nil,
                     "turning the question off runs even a command built to ask")
        suite.expect(CommandBarConfirmationSupport.prompt(builtIn: nil, asks: true,
                                                         title: "Sleep", format: format) == "Run “Sleep”?",
                     "turning it on gives a command that never asked the plain question")
        suite.expect(CommandBarConfirmationSupport.prompt(builtIn: "Restart now?", asks: true,
                                                         title: "Restart", format: format) == "Restart now?",
                     "asking again keeps a command's own wording")

        let map = ["action.emptyTrash": false, "action.power.sleep": true]
        suite.expect(CommandBarConfirmationSupport.decode(CommandBarConfirmationSupport.encode(map)) == map,
                     "the choices survive being written to preferences and read back")
        suite.expect(CommandBarConfirmationSupport.encode([:]).isEmpty,
                     "no choices write the empty default instead of an empty object")
        suite.expect(CommandBarConfirmationSupport.decode("not json").isEmpty
                     && CommandBarConfirmationSupport.decode(nil).isEmpty,
                     "a damaged or missing preference reads as no choices")

        for language in AppLanguage.allCases {
            let prompt = FeatureStrings.commandBarCommands(language).confirmPromptFormat
            suite.expect(prompt.components(separatedBy: "%@").count == 2,
                         "the \(language.rawValue) question names the command exactly once")
        }
    }
}
