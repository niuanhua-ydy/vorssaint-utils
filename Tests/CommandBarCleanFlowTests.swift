// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine

/// The command bar's in-place Cleaner: the production mode transitions, key
/// decisions and group selection run against a recording cleaner. Nothing is
/// scanned or cleaned.
enum CommandBarCleanFlowTests {
    struct Item: Identifiable {
        let id = UUID()
        let category: CleanerSupport.Category
        let size: Int64
        let recommended: Bool
        var include: Bool
        init(_ category: CleanerSupport.Category, recommended: Bool, include: Bool? = nil) {
            self.category = category
            self.size = 1
            self.recommended = recommended
            self.include = include ?? recommended
        }
    }
    class CleanerState {
        var phase: Phase = .idle
        var items: [Item] = []
        var scans: [Bool] = []
        var cleans: [Bool] = []
        var resets = 0
        var selectedCount: Int { items.filter(\.include).count }
        func scan(attended: Bool) {
            scans.append(attended)
            items = []
            phase = .scanning
        }
        func cleanSelected(escalate: Bool) {
            cleans.append(escalate)
            phase = .cleaning
        }
        func reset() {
            resets += 1
            items = []
            phase = .idle
        }
    }
    final class Uninstaller {
        enum Phase { case empty, done }
        static let shared = Uninstaller()
        var phase = Phase.empty
        var isRemoving = false
        func reset() {}
    }
    enum Feature {
        case cleaner
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    enum Sound {
        static var beeps = 0
        static func beep() { beeps += 1 }
    }
    class ServiceState {
        typealias JunkCleaner = Cleaner
        typealias AppUninstaller = Uninstaller
        typealias AppFeature = Feature
        typealias NSSound = Sound
        var mode: Mode = .search
        var uninstallWarning: String?
        var uninstallFinderRequestID: UUID?
        var queryBeforeCompletion: String?
        var completedQuery: String?
        var savedQuery = ""
        var cleanReviewOwnsCleaner = false
        var aliasWarning: String?
        var activeCategory: String?
        var isPeekingHome = false
        var submissions = 0
        func refreshResults() {}
        func refreshPanelLayout() {}
        func entry(withID: String) -> (id: String, other: Bool)? { nil }
        func leaveActions() { mode = .search }
        func endCapturingShortcut() {}
        func setCategory(_ value: String?) { activeCategory = value }
        func hide() { mode = .search }
        func runSelected() { submissions += 1 }
        func finishUninstallReview() { mode = .search }
    }

    static func run(_ suite: TestSuite) {
        groups(suite)
        flow(suite)
    }

    private static func groups(_ suite: TestSuite) {
        typealias Group = CleanerSupport.DisplayGroup
        for category in CleanerSupport.Category.allCases {
            for recommended in [true, false] {
                let holders = Group.allCases.filter { $0.holds(category, recommended: recommended) }
                suite.expect(holders.count == 1 && holders[0].categories.contains(category),
                             "every \(category) find, recommended or not, is shown in exactly one group")
            }
        }
        suite.expect(Group.allCases.filter(\.isSafe) == [.loginItems, .safeCaches, .logs, .developer],
                     "the safe section is the groups the scan pre-checks")
        suite.expect(Group.safeCaches.holds(.caches, recommended: true)
                     && Group.otherCaches.holds(.caches, recommended: false),
                     "caches split on the scan's own recommendation")

        let cleaner = Cleaner.shared
        defer { cleaner.items = [] }
        cleaner.items = [Item(.caches, recommended: true), Item(.caches, recommended: false),
                         Item(.logs, recommended: true), Item(.logs, recommended: true, include: false)]
        suite.expect(cleaner.items(in: .safeCaches).count == 1 && cleaner.items(in: .otherCaches).count == 1
                     && cleaner.items(in: .trash).isEmpty,
                     "a group lists exactly the finds it holds")
        suite.expect(cleaner.isIncluded(.safeCaches) && !cleaner.isIncluded(.otherCaches)
                     && !cleaner.isIncluded(.logs) && !cleaner.isIncluded(.trash),
                     "a group's checkbox is on only while every find in it is, and off when it is empty")
        cleaner.setInclude(true, forGroup: .logs)
        suite.expect(cleaner.isIncluded(.logs) && cleaner.selectedCount == 3,
                     "checking a half picked group selects all of it")
        cleaner.setInclude(false, forGroup: .safeCaches)
        suite.expect(!cleaner.isIncluded(.safeCaches) && !cleaner.items[1].include && cleaner.selectedCount == 2,
                     "unchecking the safe caches leaves the other caches as they were")
    }

    private static func flow(_ suite: TestSuite) {
        let cleaner = Cleaner.shared
        func fresh(_ phase: Phase, items: [Item] = []) {
            cleaner.phase = phase
            cleaner.items = items
            cleaner.scans = []
            cleaner.cleans = []
            cleaner.resets = 0
            Sound.beeps = 0
        }
        defer {
            fresh(.idle)
            Feature.available = true
        }
        let picked = [Item(.caches, recommended: true), Item(.trash, recommended: false)]

        suite.expect(Mode.cleanReview(entryID: "c").isChecklist && Mode.uninstallReview(entryID: "u").isChecklist
                     && !Mode.search.isChecklist && !Mode.confirm(entryID: "c").isChecklist
                     && !Mode.cleanReview(entryID: "c").isUninstallFlow,
                     "the clean review is a checklist without joining the uninstall flow")

        let service = Service()
        fresh(.idle)
        service.query = "clean"
        service.beginCleanReview(entryID: "action.cleaner")
        suite.expect(service.mode == .cleanReview(entryID: "action.cleaner") && cleaner.scans == [true]
                     && service.savedQuery == "clean",
                     "the Cleaner row opens its review with an attended scan, as the Scan button does")

        service.mode = .search
        fresh(.results, items: picked)
        cleaner.items[0].include = false
        service.beginCleanReview(entryID: "action.cleaner")
        suite.expect(cleaner.scans.isEmpty && cleaner.items.count == 2 && !cleaner.items[0].include,
                     "a review already open elsewhere is joined with its choices intact")
        service.mode = .search
        fresh(.cleaning)
        service.beginCleanReview(entryID: "action.cleaner")
        suite.expect(cleaner.scans.isEmpty && cleaner.resets == 0 && cleaner.phase == .cleaning,
                     "a clean already moving files is joined, never restarted")
        service.mode = .search
        fresh(.done(freed: 1, failed: 0))
        service.beginCleanReview(entryID: "action.cleaner")
        suite.expect(cleaner.scans == [true], "a finished session gives way to a fresh scan")
        service.mode = .search
        fresh(.idle)
        Feature.available = false
        service.beginCleanReview(entryID: "action.cleaner")
        suite.expect(service.mode == .search && cleaner.scans.isEmpty,
                     "a removed Cleaner turns down a row offered before it went")
        Feature.available = true

        service.mode = .cleanReview(entryID: "action.cleaner")
        fresh(.results, items: picked)
        service.runCleanReview()
        suite.expect(cleaner.cleans == [true],
                     "Clean asks for the administrator prompt like the Settings page, never silently")
        fresh(.results, items: picked.map { var item = $0; item.include = false; return item })
        service.runCleanReview()
        suite.expect(cleaner.cleans.isEmpty && Sound.beeps == 1 && service.mode == .cleanReview(entryID: "action.cleaner"),
                     "Clean with nothing selected cleans nothing and stays in the review")
        for phase in [Phase.scanning, .cleaning] {
            fresh(phase)
            service.runCleanReview()
            suite.expect(cleaner.cleans.isEmpty && cleaner.scans.isEmpty && cleaner.resets == 0
                         && service.mode == .cleanReview(entryID: "action.cleaner"),
                         "Return while \(phase) does nothing")
        }
        fresh(.idle)
        service.runCleanReview()
        suite.expect(cleaner.scans == [true], "Return at rest scans again")
        service.query = "typed"
        service.mode = .cleanReview(entryID: "action.cleaner")
        service.cleanReviewOwnsCleaner = true
        fresh(.results)
        service.runCleanReview()
        suite.expect(service.mode == .search && service.query.isEmpty && cleaner.resets == 1,
                     "Return on nothing to clean goes home")
        service.mode = .cleanReview(entryID: "action.cleaner")
        service.cleanReviewOwnsCleaner = true
        fresh(.done(freed: 5, failed: 1))
        service.runCleanReview()
        suite.expect(service.mode == .search && service.query.isEmpty && cleaner.resets == 1,
                     "Done goes home with an empty field and puts the cleaner at rest")

        service.mode = .search
        service.query = "clean"
        fresh(.idle)
        service.beginCleanReview(entryID: "action.cleaner")
        service.stepBack()
        suite.expect(service.mode == .search && service.query == "clean" && cleaner.phase == .idle
                     && cleaner.resets == 1,
                     "Escape while scanning cancels the scan and returns to the search as it was")
        service.mode = .cleanReview(entryID: "action.cleaner")
        fresh(.cleaning)
        service.stepBack()
        suite.expect(service.mode == .search && cleaner.phase == .cleaning && cleaner.resets == 0,
                     "Escape during a clean leaves the bar but never cuts the clean short")
        service.mode = .cleanReview(entryID: "action.cleaner")
        service.cleanReviewOwnsCleaner = true
        fresh(.done(freed: 1, failed: 0))
        service.stepBack()
        suite.expect(service.mode == .search && service.query.isEmpty && cleaner.phase == .idle,
                     "Escape after the clean goes home like Done")

        service.mode = .cleanReview(entryID: "action.cleaner")
        service.cleanReviewOwnsCleaner = true
        fresh(.results, items: picked)
        service.query = "something else"
        suite.expect(service.mode == .search && service.query == "something else" && cleaner.resets == 1,
                     "typing a new search leaves the review and drops its unreviewed results")
        service.mode = .cleanReview(entryID: "action.cleaner")
        fresh(.cleaning)
        service.query = "again"
        suite.expect(service.mode == .search && cleaner.phase == .cleaning && cleaner.resets == 0,
                     "typing during a clean leaves the review without stopping the clean")

        service.mode = .search
        service.query = "clean"
        fresh(.results, items: picked)
        service.beginCleanReview(entryID: "action.cleaner")
        service.stepBack()
        suite.expect(service.mode == .search && cleaner.resets == 0 && cleaner.items.count == 2
                     && cleaner.phase == .results,
                     "leaving a review joined from Settings or the panel keeps its results and choices")
        fresh(.scanning)
        service.beginCleanReview(entryID: "action.cleaner")
        service.query = "elsewhere"
        suite.expect(service.mode == .search && cleaner.resets == 0 && cleaner.phase == .scanning,
                     "leaving a scan the bar only joined, such as a scheduled one, never cancels it")

        service.mode = .cleanReview(entryID: "action.cleaner")
        fresh(.results, items: picked)
        service.submissions = 0
        for key in [kVK_Tab, kVK_Space, kVK_UpArrow, kVK_DownArrow] {
            suite.expect(!service.handleChecklistKey(key, searchFieldFocused: false),
                         "key \(key) reaches the clean review's native controls")
        }
        suite.expect(!service.handleChecklistKey(kVK_Return, searchFieldFocused: false) && service.submissions == 0,
                     "Return on a focused checkbox cannot start the clean")
        suite.expect(service.handleChecklistKey(kVK_Return, searchFieldFocused: true) && service.submissions == 1,
                     "Return in the field is the review's Clean")
        suite.expect(service.handleChecklistKey(kVK_Escape, searchFieldFocused: false) && service.mode == .search,
                     "Escape steps back out of the review")
    }
}
