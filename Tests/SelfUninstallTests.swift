// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production clear and uninstall bodies with the password request,
/// tccutil and every removal step replaced by doubles that log what ran.
enum SelfUninstallContract {
    static var events: [String] = []
    static var suspensionAllowed = true
    static var sleepRestoreAllowed = true
    static var ruleRemovalAllowed = true
    static var tccResetAllowed = true

    enum DispatchQueue {
        static let main = Queue()
        enum QoS { case userInitiated }
        static func global(qos: QoS) -> Queue { main }
        final class Queue {
            var pending: [() -> Void] = []
            func async(execute: @escaping () -> Void) { pending.append(execute) }
            func flush() {
                while !pending.isEmpty { pending.removeFirst()() }
            }
        }
    }
    enum Sudoers {
        static var ruleFilesPresent: Bool { true }
        static func isConfigured() -> Bool { true }
        static func remove(completion: @escaping (Bool) -> Void) {
            events.append("rule")
            DispatchQueue.main.async { completion(ruleRemovalAllowed) }
        }
    }
    enum Shell {
        static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
            events.append("tccutil")
            return (tccResetAllowed ? 0 : 1, "")
        }
    }
    struct Permissions {
        static let shared = Permissions()
        func refresh() { events.append("refresh permissions") }
    }
    struct BrightnessService {
        static let shared = BrightnessService()
        func resumeInputTaps() { events.append("resume brightness") }
    }
    enum SpacesOrderHold {
        static var restores = true
        static func restoreForRemoval() -> Bool { events.append("spaces"); return restores }
    }
    enum AppFeature: CaseIterable { case any }
    struct FeatureRuntime {
        static let shared = FeatureRuntime()
        func sync(_ features: [AppFeature]) { events.append("resume features") }
    }
    struct KeepAwakeManager {
        static let shared = KeepAwakeManager()
        func resumeAfterSystemTeardown() { events.append("restore keep awake") }
    }
    struct L10n {
        struct Text {
            let advancedUninstallFailedBody = "stopped"
            let advancedClearFailed = "rule kept"
        }
        static let shared = L10n()
        let s = Text()
    }

    static func run(_ suite: TestSuite) {
        func reset(allowRule: Bool, spacesRestore: Bool = true) {
            events = []
            suspensionAllowed = true
            sleepRestoreAllowed = true
            ruleRemovalAllowed = allowRule
            tccResetAllowed = true
            SpacesOrderHold.restores = spacesRestore
        }

        reset(allowRule: true)
        suspensionAllowed = false
        var cleared: Bool?
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == true
                        && events == ["suspend", "sleep", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "a mouse journal kept for a disconnected device does not block clearing permissions, found \(events)")

        reset(allowRule: true)
        sleepRestoreAllowed = false
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["suspend", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration keeps the recovery rule and permissions, found \(events)")

        reset(allowRule: false)
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["suspend", "sleep", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a refused password request reports partial clear and restores closed-lid mode, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["suspend", "sleep", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a failed TCC reset reports partial clear and restores closed-lid mode, found \(events)")

        reset(allowRule: true)
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == true
                        && events == ["suspend", "sleep", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "clear permissions succeeds when the rule and permissions are removed, found \(events)")

        reset(allowRule: false)
        var failure: String?
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["suspend", "spaces", "sleep", "rule", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a refused password request stops a full uninstall before anything is removed, found \(events)")

        reset(allowRule: true)
        sleepRestoreAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["suspend", "spaces", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration does not reset the closed-lid session, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["suspend", "spaces", "sleep", "rule", "tccutil", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed permission reset keeps login, found \(events)")

        reset(allowRule: true)
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == nil
                        && events == ["suspend", "spaces", "sleep", "rule", "tccutil", "login", "preferences", "trash"],
                     "a full uninstall resets permissions before detaching login, found \(events)")

        reset(allowRule: true)
        suspensionAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["suspend", "refresh permissions", "resume features", "resume brightness"],
                     "a full uninstall still waits for mouse acceleration before deleting its journal, found \(events)")

        reset(allowRule: true, spacesRestore: false)
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["suspend", "spaces", "refresh permissions", "resume features", "resume brightness"],
                     "a failed Space restore stops a full uninstall before sleep, the rule or anything else is touched, found \(events)")
    }
}
