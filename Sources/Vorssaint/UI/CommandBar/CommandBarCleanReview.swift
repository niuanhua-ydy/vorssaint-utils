// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The junk cleaner in place, for `.cleanReview`: the same groups, defaults,
/// captions and Clean the Settings page shows, driven by the same
/// `JunkCleaner`, so a choice made here is the one the panel and Settings
/// see. Laid out like the uninstall review: the groups scroll, the footer
/// with the selected total and the Clean button stays put. Each group opens
/// to its files, because the leftovers' promise is that the path is checked
/// before anything is ticked.
struct CommandBarCleanReview: View {
    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var cleaner = JunkCleaner.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.cleanerScreenshotAgeDays)
    private var screenshotAgeDays = CleanerPolicy.defaultScreenshotAgeDays
    @State private var expanded: Set<CleanerSupport.DisplayGroup> = []

    private typealias DisplayGroup = CleanerSupport.DisplayGroup

    var body: some View {
        content
            // The panel fits its content; a state that changes height under
            // it (results arriving, a group opening) asks for a re-fit that
            // keeps the field where it is.
            .onChange(of: cleaner.phase) { _, _ in service.refreshPanelLayout() }
            .onChange(of: expanded) { _, _ in service.refreshPanelLayout() }
    }

    @ViewBuilder
    private var content: some View {
        switch cleaner.phase {
        case .idle:
            // Only reached when another surface (or the schedule) put the
            // cleaner back at rest while the review was up.
            VStack(spacing: 12) {
                Text(l10n.s.cleanerIntroCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                Button(l10n.s.cleanerScan) { service.runSelected() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        case .scanning:
            busy(l10n.s.cleanerScanning, detail: scanningDetail)
        case .results:
            if cleaner.items.isEmpty { empty } else { checklist }
        case .cleaning:
            busy(l10n.s.cleanerCleaning, detail: nil)
        case let .done(freed, failed):
            done(freed: freed, failed: failed)
        }
    }

    private var scanningDetail: String? {
        cleaner.scanningCategory.flatMap { category in
            DisplayGroup.allCases.first { $0.categories.contains(category) }
        }.map { $0.title(l10n.s) }
    }

    private func busy(_ message: String, detail: String?) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            // A scan can be called off, as on the Settings page; a clean
            // already moving files cannot.
            if cleaner.phase == .scanning {
                Button(l10n.s.uninstallerCancel) { service.stepBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.green)
            Text(l10n.s.cleanerNothingFound)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            // Nothing found can also mean nothing could be read.
            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: true)
                    .padding(.horizontal, 17)
            }
            Button(l10n.s.supportIntroDoneButton) { service.runSelected() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    section(l10n.s.cleanerSafeSection, groups: DisplayGroup.allCases.filter(\.isSafe))
                    section(l10n.s.cleanerOptionalSection, groups: DisplayGroup.allCases.filter { !$0.isSafe })
                    if !permissions.fullDiskAccess {
                        FullDiskAccessNote(compact: true)
                    }
                }
                .padding(.horizontal, 17)
            }
            .frame(maxHeight: CommandBarView.listCeiling - 90)
            Divider().padding(.horizontal, 17)
            footer
        }
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
            Text(l10n.s.cleanerName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.byteString(cleaner.totalSize))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(l10n.s.uninstallerFoundTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 17)
    }

    @ViewBuilder
    private func section(_ title: String, groups: [DisplayGroup]) -> some View {
        let visible = groups.filter { !cleaner.items(in: $0).isEmpty }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                ForEach(visible) { group in
                    groupRow(group)
                }
            }
        }
    }

    private func groupRow(_ group: DisplayGroup) -> some View {
        let found = cleaner.items(in: group)
        let isOpen = expanded.contains(group)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Button {
                    if isOpen { expanded.remove(group) } else { expanded.insert(group) }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Toggle(group.title(l10n.s), isOn: groupBinding(group))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .focusable(interactions: .edit)
                    .onKeyPress(.space) {
                        cleaner.setInclude(!cleaner.isIncluded(group), forGroup: group)
                        return .handled
                    }
                Image(systemName: group.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title(l10n.s))
                        .font(.system(size: 11.5, weight: .medium))
                    Text(group.caption(l10n.s, screenshotAgeDays: screenshotAgeDays))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(Self.byteString(found.reduce(0) { $0 + $1.size }))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 3) {
                    if group == .leftovers {
                        Text(l10n.s.cleanerLeftoversNote)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if group == .loginItems {
                        Text(l10n.s.cleanerLoginItemsNote)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(found) { item in itemRow(item) }
                }
                .padding(.leading, 17)
            }
        }
    }

    private func itemRow(_ item: JunkCleaner.Item) -> some View {
        HStack(spacing: 7) {
            Toggle(item.name, isOn: includeBinding(item))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .focusable(interactions: .edit)
                .onKeyPress(.space) {
                    let included = cleaner.items.first(where: { $0.id == item.id })?.include ?? false
                    cleaner.setInclude(!included, for: item.id)
                    return .handled
                }
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)
            .accessibilityLabel(l10n.s.cleanerRevealInFinder)
            Text(Self.byteString(item.size))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 22)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            cleaner.selectedCount, cleaner.items.count))
                    .font(.system(size: 11, weight: .medium))
                Text(Self.byteString(cleaner.selectedSize))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.s.uninstallerCancel) { service.stepBack() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                service.runSelected()
            } label: {
                Label(l10n.s.cleanerClean, systemImage: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(cleaner.selectedCount == 0)
        }
        .padding(.horizontal, 17)
    }

    // MARK: Done

    private func done(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text(l10n.s.uninstallerDoneTitle)
                .font(.system(size: 13, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(l10n.s.cleanerDoneNote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            if failed > 0 {
                Text(l10n.s.uninstallerSomeFailed)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            Button(l10n.s.supportIntroDoneButton) { service.runSelected() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    // MARK: Helpers

    private func groupBinding(_ group: DisplayGroup) -> Binding<Bool> {
        Binding(
            get: { cleaner.isIncluded(group) },
            set: { cleaner.setInclude($0, forGroup: group) }
        )
    }

    private func includeBinding(_ item: JunkCleaner.Item) -> Binding<Bool> {
        Binding(
            get: { cleaner.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { cleaner.setInclude($0, for: item.id) }
        )
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
