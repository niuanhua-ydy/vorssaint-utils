// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the uninstaller stops and unlinks beyond the files themselves:
/// launchd jobs, their labels, and command-line links into the bundle.
/// Links live in a disposable folder; no launchctl or real bin folder is used.
enum UninstallerBackgroundJobsTests {
    static func run(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        suite.expect(UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.vendor.editor.plist"),
                home: home) == .gui
            && UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Library/LaunchAgents/com.vendor.editor.agent.plist"),
                home: home) == .gui
            && UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Library/LaunchDaemons/com.vendor.editor.helper.plist"),
                home: home) == .system,
            "launchd folders map to the session or the system domain")
        suite.expect(UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Users/test/Library/Preferences/com.vendor.editor.plist"),
                home: home) == nil
            && UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Library/LaunchDaemons/com.vendor.editor"),
                home: home) == nil
            && UninstallerSupport.launchDomain(
                forLeftoverAt: URL(fileURLWithPath: "/Library/LaunchDaemons/Vendor/com.vendor.editor.plist"),
                home: home) == nil,
            "preferences, non-plists and nested plists are never treated as jobs")

        let app = URL(fileURLWithPath: "/Applications/Editor.app", isDirectory: true)
        suite.expect(UninstallerSupport.launchDomain(
                forEmbeddedPlistAt: app.appendingPathComponent("Contents/Library/LaunchAgents/com.vendor.editor.agent.plist"),
                in: app) == .gui
            && UninstallerSupport.launchDomain(
                forEmbeddedPlistAt: app.appendingPathComponent("Contents/Library/LaunchDaemons/com.vendor.editor.daemon.plist"),
                in: app) == .system
            && UninstallerSupport.launchDomain(
                forEmbeddedPlistAt: app.appendingPathComponent("Contents/Resources/com.vendor.editor.agent.plist"),
                in: app) == nil,
            "SMAppService plists are read only from the bundle's own launchd folders")

        let owners: Set<String> = ["com.vendor.editor"]
        suite.expect(UninstallerSupport.launchJobLabel(
                ["Label": "com.vendor.updater"], fileName: "com.vendor.updater.plist",
                ownerBundleIDs: owners) == "com.vendor.updater"
            && UninstallerSupport.launchJobLabel(
                ["Label": "com.vendor.editor.helper"], fileName: "helper.plist",
                ownerBundleIDs: owners) == "com.vendor.editor.helper"
            && UninstallerSupport.launchJobLabel(
                ["Label": "COM.VENDOR.EDITOR"], fileName: "agent.plist",
                ownerBundleIDs: owners) == "COM.VENDOR.EDITOR",
            "a label tied to its file name or an owned identifier is accepted")
        suite.expect(UninstallerSupport.launchJobLabel(
                ["Label": "com.other.daemon"], fileName: "com.vendor.editor.plist",
                ownerBundleIDs: owners) == nil
            && UninstallerSupport.launchJobLabel(
                ["Label": "com.vendor.editor2"], fileName: "agent.plist",
                ownerBundleIDs: owners) == nil,
            "a plist cannot point the removal at another product's job")
        suite.expect(UninstallerSupport.launchJobLabel(
                ["Label": "com.apple.Finder"], fileName: "com.apple.Finder.plist",
                ownerBundleIDs: ["com.apple.Finder"]) == nil,
            "Apple's jobs are never stopped")
        let hostile = ["com.vendor.editor; rm -rf ~", "com.vendor.editor$(id)", "com.vendor editor",
                       "com/vendor/editor", "..com.vendor.editor", "-com.vendor.editor",
                       "com.vendor..editor", "", String(repeating: "a", count: 256)]
        suite.expect(hostile.allSatisfy {
                UninstallerSupport.launchJobLabel(["Label": $0], fileName: $0 + ".plist",
                                                  ownerBundleIDs: [$0]) == nil
            } && UninstallerSupport.launchJobLabel(
                ["Label": 42], fileName: "com.vendor.editor.plist", ownerBundleIDs: owners) == nil
            && UninstallerSupport.launchJobLabel(
                [:], fileName: "com.vendor.editor.plist", ownerBundleIDs: owners) == nil,
            "labels outside plain reverse-DNS characters never reach launchctl")

        suite.expect(UninstallerSupport.launchJobLabel(
                ["Label": "net.unrelated.runner"], fileName: "runner.plist",
                ownerBundleIDs: owners, runsFromBundle: true) == "net.unrelated.runner"
            && UninstallerSupport.launchJobLabel(
                ["Label": "com.apple.runner"], fileName: "runner.plist",
                ownerBundleIDs: owners, runsFromBundle: true) == nil
            && UninstallerSupport.launchJobLabel(
                ["Label": "x; reboot"], fileName: "runner.plist",
                ownerBundleIDs: owners, runsFromBundle: true) == nil,
            "a job running the app's own program is the app's, still within the label rules")

        suite.expect(UninstallerSupport.privilegedHelperLabels(infoDictionary: [
                "SMPrivilegedExecutables": [
                    "com.vendor.editor.helper": "identifier \"com.vendor.editor.helper\"",
                    "com.apple.helper": "identifier \"com.apple.helper\"",
                    "not a label": "",
                ],
            ]) == ["com.vendor.editor.helper"]
            && UninstallerSupport.privilegedHelperLabels(infoDictionary: ["SMPrivilegedExecutables": "x"]).isEmpty
            && UninstallerSupport.privilegedHelperLabels(infoDictionary: nil).isEmpty,
            "SMJobBless helpers named in Info.plist become owned identifiers, protected ones excluded")

        suite.expect(UninstallerSupport.launchPlistRunsFromBundle(
                ["Program": "/Applications/Editor.app/Contents/Library/LaunchServices/helper"], appURL: app)
            && UninstallerSupport.launchPlistRunsFromBundle(
                ["ProgramArguments": ["/Applications/Editor.app/Contents/MacOS/Editor", "--agent"]], appURL: app),
            "a plist running a program from the bundle belongs to it")
        suite.expect(!UninstallerSupport.launchPlistRunsFromBundle(
                ["Program": "/Applications/Editor.app.old/Contents/MacOS/Editor"], appURL: app)
            && !UninstallerSupport.launchPlistRunsFromBundle(
                ["Program": "/Applications/Editor.app/../Other.app/Contents/MacOS/other"], appURL: app)
            && !UninstallerSupport.launchPlistRunsFromBundle(
                ["ProgramArguments": ["Editor.app/Contents/MacOS/Editor"]], appURL: app)
            && !UninstallerSupport.launchPlistRunsFromBundle(
                ["Program": "/Library/PrivilegedHelperTools/com.vendor.editor.helper"], appURL: app),
            "sibling names, escapes, relative paths and outside tools never claim a plist")

        suite.expect(UninstallerSupport.launchServiceTarget(
                label: "com.vendor.editor.agent", domain: .gui, uid: 501) == "gui/501/com.vendor.editor.agent"
            && UninstallerSupport.launchServiceTarget(
                label: "com.vendor.editor.helper", domain: .system, uid: 501) == "system/com.vendor.editor.helper",
            "service targets name the domain launchctl expects")
        suite.expect(UninstallerSupport.systemBootoutCommand(labels: []) == nil
            && UninstallerSupport.systemBootoutCommand(labels: ["com.vendor.a", "com.vendor.b"])
                == "/bin/launchctl bootout system/com.vendor.a; /bin/launchctl bootout system/com.vendor.b; true"
            && UninstallerSupport.systemBootoutCommand(labels: ["x; reboot"]) == nil,
            "running daemons share one administrator command that carries no shell syntax")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("uninstaller-links-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        do {
            let bundle = root.appendingPathComponent("Editor.app", isDirectory: true)
            let tool = bundle.appendingPathComponent("Contents/Resources/bin/editor")
            let other = root.appendingPathComponent("Other.app/Contents/MacOS/other")
            let bin = root.appendingPathComponent("bin", isDirectory: true)
            let nested = bin.appendingPathComponent("nested", isDirectory: true)
            for dir in [tool.deletingLastPathComponent(), other.deletingLastPathComponent(), nested] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try Data("#!/bin/sh\n".utf8).write(to: other)
            let link = bin.appendingPathComponent("editor")
            let relative = bin.appendingPathComponent("editor-relative")
            let foreign = bin.appendingPathComponent("other")
            let copy = bin.appendingPathComponent("editor-copy")
            let deep = nested.appendingPathComponent("editor")
            try fm.createSymbolicLink(at: link, withDestinationURL: tool)
            try fm.createSymbolicLink(atPath: relative.path,
                                      withDestinationPath: "../Editor.app/Contents/Resources/bin/editor")
            try fm.createSymbolicLink(at: foreign, withDestinationURL: other)
            try fm.copyItem(at: tool, to: copy)
            try fm.createSymbolicLink(at: deep, withDestinationURL: tool)
            let folders = [bin]
            suite.expect(UninstallerSupport.commandLinkPointsInto(link, appURL: bundle, folders: folders)
                && UninstallerSupport.commandLinkPointsInto(relative, appURL: bundle, folders: folders),
                "absolute and relative links into the bundle belong to the app")
            suite.expect(!UninstallerSupport.commandLinkPointsInto(foreign, appURL: bundle, folders: folders)
                && !UninstallerSupport.commandLinkPointsInto(copy, appURL: bundle, folders: folders)
                && !UninstallerSupport.commandLinkPointsInto(deep, appURL: bundle, folders: folders)
                && !UninstallerSupport.commandLinkPointsInto(link, appURL: bundle, folders: []),
                "links elsewhere, copied tools, nested links and unlisted folders are left alone")

            // Once the bundle has gone the link dangles; its location alone
            // stays checkable, which is what the removal pass relies on.
            try fm.removeItem(at: bundle)
            suite.expect(UninstallerSupport.commandLinkLocationIsSafe(link, folders: folders)
                && !UninstallerSupport.commandLinkLocationIsSafe(copy, folders: folders),
                "a dangling link stays removable while a regular file never passes as one")

            let linkedBin = root.appendingPathComponent("linked-bin")
            try fm.createSymbolicLink(at: linkedBin, withDestinationURL: bin)
            suite.expect(!UninstallerSupport.commandLinkLocationIsSafe(
                    linkedBin.appendingPathComponent("editor"), folders: [linkedBin]),
                "a command folder that has become a link is never trusted")
        } catch {
            suite.expect(false, "command link fixture failed: \(error)")
        }
    }
}
