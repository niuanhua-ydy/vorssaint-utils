// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        // ClipNote's storage, search, sync and backup, kept apart from the UI.
        .target(
            name: "ClipNoteCore",
            path: "Sources/ClipNoteCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Vorssaint",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem", "ClipNoteCore"],
            path: "Sources/Vorssaint"
        )
    ]
)
