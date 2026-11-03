// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Features this build leaves out. Their code stays in the tree, untouched,
/// so the upstream catalog keeps merging cleanly; what changes is that they
/// can never be installed. Launch writes them uninstalled
/// (`Defaults.enforceBuildExclusions`), the runtime refuses to install them,
/// and every list that offers features to install (the hub, the first-run
/// picker, Settings search, release notes) skips them. Taking a case out of
/// the set brings the feature back as an ordinary opt-in from the Features
/// page.
extension AppFeature {
    static let excludedFromBuild: Set<AppFeature> = [
        // Windows and Dock
        .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit, .spacesOrder,
        // Mouse and keyboard: the Super Key stays
        .scrollInverter, .scrollHorizontal, .focusFollowsMouse, .smoothScroll, .linearScroll,
        .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
        .mouseClickDebounce, .keyboardDebounce, .textSnippets, .quitWindowProtection,
        // Clipboard and files: plain paste and the shelf stay; ClipNote is the history now
        .clipboardHistory, .finderCutPaste, .finderRename, .urlCleaner, .diskImageInstaller,
        // Sound: the mixer stays
        .soundOutputSwitcher, .audioPriority, .micMute, .musicBlock,
        // Energy and display
        .keepAwake, .brightness, .extraBrightness, .bluetoothSleep,
        // Tools: the Command Bar is the launcher, so the quick panel goes;
        // media tools and the scratchpad stay for the island
        .quickLauncher, .cleaningMode, .cameraPreview, .radialMenu, .wallpaper,
        // Added upstream in 3.4.3; hidden like the rest of their groups.
        .scrollZoom, .quitApps,
    ]

    var isExcludedFromBuild: Bool { Self.excludedFromBuild.contains(self) }

    /// Upstream opt-ins this build installs anyway: the Command Bar is where
    /// they live here. Registered installed for a Mac that never chose, and
    /// part of the first-run set; a later uninstall from the hub still holds.
    static let installedByDefaultInBuild: Set<AppFeature> = [.killProcess, .portManager, .clipNote, .translator,
                                                                    .usageRecord]

    /// What a clean install starts with before onboarding, and what the
    /// first-run picker shows selected.
    static var firstRunFeatures: Set<AppFeature> {
        FeaturePreset.essential.features.subtracting(excludedFromBuild).union(installedByDefaultInBuild)
    }

    /// Every feature this build offers, in catalog order. Lists that show
    /// features someone could install read this instead of `allCases`; the
    /// catalog helpers stay whole, so their tests keep describing upstream.
    static var offered: [AppFeature] { allCases.filter { !$0.isExcludedFromBuild } }

    static func offeredFeatures(in group: FeatureGroup) -> [AppFeature] {
        features(in: group).filter { !$0.isExcludedFromBuild }
    }
}

extension FeatureGroup {
    /// Groups with at least one feature this build offers.
    static var offered: [FeatureGroup] {
        allCases.filter { !AppFeature.offeredFeatures(in: $0).isEmpty }
    }
}

extension FeaturePreset {
    /// Presets whose whole set this build still offers. One that leans on an
    /// excluded feature would install less than its description promises.
    static var offered: [FeaturePreset] {
        allCases.filter { $0.features.isDisjoint(with: AppFeature.excludedFromBuild) }
    }
}
