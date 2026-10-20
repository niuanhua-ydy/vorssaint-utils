// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The labels of the System tab's card dashboard. Everything else on it reuses
/// the monitor's existing strings; these are only the ones the cards add.
struct SystemDashboardStrings {
    let loadAverage: String
    let gpuIdle: String
    let gpuLight: String
    let gpuModerate: String
    let gpuHeavy: String
    let freeSpace: String
    let topProcesses: String
    let health: String
}

extension FeatureStrings {
    static func systemDashboard(_ language: AppLanguage) -> SystemDashboardStrings {
        switch language {
        case .zhHans: return .zhHans
        case .ja: return .ja
        case .ko: return .ko
        // Only the offered languages are written; see LanguageExclusions.
        default: return .enUS
        }
    }
}

extension SystemDashboardStrings {
    static let enUS = SystemDashboardStrings(
        loadAverage: "Load avg", gpuIdle: "Idle", gpuLight: "Light load", gpuModerate: "Moderate load",
        gpuHeavy: "Heavy load", freeSpace: "Free Space", topProcesses: "Top Processes", health: "Health")









    static let ja = SystemDashboardStrings(
        loadAverage: "平均負荷", gpuIdle: "アイドル", gpuLight: "低負荷", gpuModerate: "中負荷",
        gpuHeavy: "高負荷", freeSpace: "空き容量", topProcesses: "高負荷のプロセス", health: "状態")

    static let ko = SystemDashboardStrings(
        loadAverage: "평균 부하", gpuIdle: "유휴", gpuLight: "낮은 부하", gpuModerate: "보통 부하",
        gpuHeavy: "높은 부하", freeSpace: "여유 공간", topProcesses: "상위 프로세스", health: "상태")

    static let zhHans = SystemDashboardStrings(
        loadAverage: "平均负载", gpuIdle: "空闲", gpuLight: "低负载", gpuModerate: "中负载",
        gpuHeavy: "高负载", freeSpace: "可用空间", topProcesses: "高占用进程", health: "健康")



}
