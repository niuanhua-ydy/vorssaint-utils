// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AppUsageRecordTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

        var history = AppUsageHistory()
        history.note(.screenshot, on: day(0), calendar: calendar)
        history.note(.screenshot, on: day(0), calendar: calendar)
        history.note(.clean, on: day(-1), bytes: 2_048, calendar: calendar)
        history.noteCommand(id: "action.translate", title: "翻译", on: day(-1), calendar: calendar)
        history.noteCommand(id: "action.translate", title: "Translate", on: day(-3), calendar: calendar)
        history.noteCommand(id: "app.safari", title: "Safari", on: day(-3), calendar: calendar)

        suite.expect(history.count(on: "2026-10-27", kinds: nil) == 2, "uses add up per day")
        suite.expect(history.count(on: "2026-10-26", kinds: [.commandBar]) == 1, "a filter keeps its kinds")
        suite.expect(history.count(on: "2026-10-24", kinds: nil) == 2, "every Command Bar run counts as a use")
        suite.expect(history.freedBytes["2026-10-26"] == 2_048, "a cleanup keeps what it freed")
        let top = history.topCommands(5)
        suite.expect(top.first?.id == "action.translate" && top.first?.command.count == 2, "the most run command leads")
        suite.expect(top.first?.command.title == "Translate", "a command keeps the title it last showed")

        let stats = AppUsageStats(history, kinds: nil, now: today, calendar: calendar)
        suite.expect(stats.total == 6, "the total covers every use")
        suite.expect(stats.peak?.key == "2026-10-27", "a tie for the busiest day goes to the later one")
        suite.expect(stats.favorite == .commandBar, "the most used kind is the favorite")
        suite.expect(stats.longestStreak == 2 && stats.currentStreak == 2, "streaks count days in a row")
        suite.expect(stats.freedBytes == 2_048, "freed space adds up")
        let capture = AppUsageStats(history, kinds: Set(AppUsageGroup.capture.kinds), now: today, calendar: calendar)
        suite.expect(capture.total == 2 && capture.freedBytes == 0, "a group counts only its own kinds")

        let streak = UsageStreaks.compute([day(-1), day(-2), day(-5)], now: today, calendar: calendar)
        suite.expect(streak.longest == 2 && streak.current == 2, "a streak still counts while today has no use yet")
        suite.expect(UsageStreaks.compute([day(-2)], now: today, calendar: calendar).current == 0,
                     "a missed day ends the current streak")

        let encoded = try? JSONEncoder().encode(history)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AppUsageHistory.self, from: $0) }
        suite.expect(decoded == history, "the record survives a save")
    }
}
