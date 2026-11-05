// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ClipNoteCore
import SwiftUI

struct ClipNotePanelView: View {
    @ObservedObject var model: ClipNotePanelModel
    @ObservedObject private var l10n = L10n.shared
    static let cornerRadius: CGFloat = 14
    static let shape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius,
                                              style: .continuous)

    private var strings: ClipNoteStrings { FeatureStrings.clipNote(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            // Paste's layout: a 60 pt top bar (icons centered 30 from the top),
            // the strip 8 below it and 33 above the bottom, 32 at the sides, 24 between cards.
            ClipNoteTopBar(model: model, strings: strings)
                .padding(.horizontal, 20)
                .frame(height: 60)
            if model.items.isEmpty {
                ClipNoteEmptyState(model: model, strings: strings)
                    .transition(.opacity)
            } else {
                ClipNoteCardStrip(model: model, strings: strings)
                    .transition(.opacity)
            }
        }
        // Full width along the bottom, rounded at the top corners only, on the
        // system glass (following light and dark).
        .background(ClipNotePanelGlass(shape: Self.shape))
        .clipShape(Self.shape)
        // The whole panel slides up from below the screen's edge and fades in;
        // the window stays put, so moving the content one panel height down hides it.
        .opacity(model.isPresented ? 1 : 0)
        .offset(y: model.isPresented ? 0 : ClipNotePanelController.panelHeight)
    }
}

/// Liquid Glass on macOS 26 and later, the earlier blur before that.
private struct ClipNotePanelGlass: View {
    let shape: UnevenRoundedRectangle

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            ClipNoteVisualEffect(material: .popover)
        }
    }
}

// MARK: - Top bar

private struct ClipNoteTopBar: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings
    @ObservedObject private var preferences = ClipNotePreferences.shared
    @Namespace private var tabNamespace

    /// The trailing buttons' width; the centered part leaves as much on both sides so it really is centered.
    private static let trailingWidth: CGFloat = 96

    var body: some View {
        ZStack {
            // Search and pinboards centered together; when they do not fit, the pinboards scroll.
            HStack(spacing: 8) {
                searchControl
                if model.syncIndicator != .hidden {
                    ClipNoteSyncButton(model: model, strings: strings)
                }
                ViewThatFits(in: .horizontal) {
                    tabs
                    ScrollView(.horizontal, showsIndicators: false) { tabs }
                }
            }
            .padding(.horizontal, Self.trailingWidth)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.isSearchActive)
            .animation(.easeOut(duration: 0.2), value: model.pinboards.count)
            .animation(.easeOut(duration: 0.2), value: model.editor != nil)

            HStack(spacing: 14) {
                Spacer()
                if preferences.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                        .help(strings.pausedHelp)
                }
                ClipNoteMoreMenu(model: model, preferences: preferences, strings: strings)
            }
        }
    }

    /// Just the magnifier and the filter button until a click, typing or a
    /// filter opens the field (which is always first responder, zero wide
    /// while closed). Active filters sit in it as tokens, like Paste's.
    private var searchControl: some View {
        HStack(spacing: 6) {
            Button {
                if model.isSearchActive {
                    model.isSearchExpanded = false
                    model.query = ""
                    model.clearFilters()
                } else {
                    model.isSearchExpanded = true
                }
                model.onFocusSearch?()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.isSearchActive ? .secondary : .primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.searchHelp)

            if let filter = model.typeFilter {
                ClipNoteFilterToken(title: strings.typeName(filter.displayType), removeHelp: strings.removeFilterHelp) {
                    Image(systemName: filter.displayType.systemImage)
                } onRemove: {
                    model.typeFilter = nil
                    model.onFocusSearch?()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let app = model.appFilterApp {
                ClipNoteFilterToken(title: app.name, removeHelp: strings.removeFilterHelp) {
                    ClipNoteAppIcon(bundleID: app.bundleID, size: 14)
                } onRemove: {
                    model.appFilter = nil
                    model.onFocusSearch?()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            ClipNoteSearchField(text: $model.query, placeholder: strings.searchPlaceholder) { field in
                model.searchField = field
            }
            .frame(width: model.isSearchActive ? 190 : 0)
            .opacity(model.isSearchActive ? 1 : 0)

            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ClipNoteFilterButton(model: model, strings: strings)
        }
        .padding(.trailing, model.isSearchActive ? 2 : 0)
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(model.isSearchActive ? 0.07 : 0)))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.typeFilter)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.appFilter)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ClipNoteTabChip(title: strings.historyTab, systemImage: "clock.arrow.circlepath", color: nil,
                            isSelected: model.tab == .history, namespace: tabNamespace) {
                select(.history)
            }
            ForEach(model.pinboards) { board in
                if model.editor?.editingID == board.id {
                    ClipNotePinboardEditorView(model: model, strings: strings)
                } else {
                    ClipNoteTabChip(title: board.name, systemImage: nil, color: Color(clipNoteHex: board.color),
                                    isSelected: model.tab == .pinboard(board.id), namespace: tabNamespace) {
                        select(.pinboard(board.id))
                    }
                    .contextMenu {
                        Button(strings.rename) { model.beginRename(board) }
                        Menu(strings.color) {
                            ForEach(Pinboard.presetColors, id: \.self) { color in
                                Button {
                                    var updated = board
                                    updated.color = color
                                    model.store.updatePinboard(updated)
                                } label: {
                                    Label(color, systemImage: board.color == color ? "checkmark.circle.fill" : "circle.fill")
                                }
                            }
                        }
                        Divider()
                        Button(strings.deletePinboard, role: .destructive) { model.deletePinboard(board) }
                    }
                }
            }
            if let editor = model.editor, editor.editingID == nil {
                ClipNotePinboardEditorView(model: model, strings: strings)
            } else {
                Button { model.beginNewPinboard(name: strings.untitledPinboard) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.newPinboard)
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ tab: ClipNotePanelModel.Tab) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.tab = tab
        }
    }
}

/// Sync now: spins while syncing, shows a check for a moment after, a red dot on error.
private struct ClipNoteSyncButton: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings
    @State private var showDone = false

    private var isSyncing: Bool { model.syncIndicator == .syncing }

    private var tooltip: String {
        switch model.syncIndicator {
        case .error(let message): return String(format: strings.syncErrorHelpFormat, message)
        case .syncing: return strings.syncing
        default:
            let last = model.lastSync.map {
                String(format: strings.lastSyncFormat, ClipNoteFormatters.relativeTime($0, now: Date(), strings: strings))
            } ?? strings.neverSynced
            return String(format: strings.syncNowHelpFormat, last)
        }
    }

    var body: some View {
        Button {
            model.onSyncNow?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if showDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ClipNoteSpinningSyncIcon(isSpinning: isSyncing)
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)

                if case .error = model.syncIndicator {
                    Circle().fill(.red).frame(width: 7, height: 7).offset(x: -3, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onChange(of: model.syncIndicator) { old, new in
            // A finished sync shows a check for a moment.
            guard old == .syncing, new == .idle else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showDone = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.25)) { showDone = false }
            }
        }
    }
}

/// The system's rotate effect on macOS 15 and later, a plain rotation on 14.
private struct ClipNoteSpinningSyncIcon: View {
    let isSpinning: Bool
    @State private var angle: Double = 0

    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isSpinning)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(angle))
                .onChange(of: isSpinning, initial: true) { _, spinning in
                    if spinning {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { angle = 360 }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
                    }
                }
        }
    }
}

private struct ClipNoteTabChip: View {
    let title: String
    let systemImage: String?
    let color: Color?
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .medium)) }
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                // The selected background slides between tabs.
                if isSelected {
                    Capsule().fill(Color.primary.opacity(0.09))
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                } else if isHovered {
                    Capsule().fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

/// A pinboard named in place: a chip with a focus ring, its name selected;
/// Return or a click elsewhere saves, Escape cancels.
private struct ClipNotePinboardEditorView: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            // A click on the dot moves to the next color.
            Button {
                let colors = Pinboard.presetColors
                let current = colors.firstIndex(of: model.editor?.color ?? "") ?? -1
                model.editor?.color = colors[(current + 1) % colors.count]
            } label: {
                Circle().fill(Color(clipNoteHex: model.editor?.color ?? "#8E8E93")).frame(width: 10, height: 10)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.nextColorHelp)

            TextField("", text: Binding(
                get: { model.editor?.name ?? "" },
                set: { model.editor?.name = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 96)
            .focused($focused)
            .onSubmit { model.commitEditor() }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 3).padding(-3))
        .onAppear {
            DispatchQueue.main.async {
                focused = true
                // The default name is selected, so typing replaces it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
        .onChange(of: focused) { wasFocused, isFocused in
            if wasFocused && !isFocused && model.editor != nil { model.commitEditor() }
        }
    }
}

/// Opens the filter popover; tinted while a filter is on or the popover is open.
private struct ClipNoteFilterButton: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings

    var body: some View {
        Button {
            model.isFilterOpen.toggle()
            model.onFocusSearch?()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.hasActiveFilter || model.isFilterOpen ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(model.isFilterOpen ? 0.09 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(strings.filterHelp)
        // The popover is placed against this frame (in the panel, origin top left).
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { model.filterButtonFrame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, frame in model.filterButtonFrame = frame }
        })
    }
}

private struct ClipNoteMoreMenu: View {
    @ObservedObject var model: ClipNotePanelModel
    @ObservedObject var preferences: ClipNotePreferences
    let strings: ClipNoteStrings

    var body: some View {
        Menu {
            Toggle(strings.pauseRecording, isOn: $preferences.isPaused)
            Toggle(strings.autoPaste, isOn: $preferences.autoPaste)
            Divider()
            Button(strings.clearHistoryEllipsis) { model.onClearHistory?() }
            Button(strings.settingsEllipsis) { model.onOpenSettings?() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Cards

private struct ClipNoteCardStrip: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipNoteCardView(item: item,
                                         index: index,
                                         isSelected: item.id == model.selectedID,
                                         isEditingTitle: model.editingTitleID == item.id,
                                         showsShortcut: model.showShortcuts,
                                         now: model.now,
                                         content: model.content(for: item, strings: strings),
                                         terms: model.searchTerms,
                                         pinboard: model.pinboard(id: item.pinboardID),
                                         store: model.store,
                                         strings: strings,
                                         onBeginEditTitle: { model.beginEditingTitle(item) },
                                         onCommitTitle: { model.commitTitle(item, text: $0, strings: strings) })
                            .id(item.id)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                            .onTapGesture(count: 2) {
                                // A double click while editing a title selects a word; it never pastes.
                                if model.editingTitleID != item.id { model.paste(item) }
                            }
                            .simultaneousGesture(TapGesture().onEnded { model.select(item) })
                            .contextMenu { ClipNoteCardMenu(model: model, item: item, strings: strings) }
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: ClipNoteCardFramesKey.self,
                                                       value: [item.id: geometry.frame(in: .global)])
                            })
                            .onAppear { model.loadMoreIfNeeded(currentIndex: index) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 33)
            }
            .onPreferenceChange(ClipNoteCardFramesKey.self) { model.cardFrames = $0 }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { proxy.scrollTo(id) }
            }
        }
    }
}

private struct ClipNoteCardFramesKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ClipNoteCardMenu: View {
    @ObservedObject var model: ClipNotePanelModel
    let item: ClipItem
    let strings: ClipNoteStrings

    var body: some View {
        if let target = model.pasteTarget {
            Button { model.paste(item) } label: {
                Label {
                    Text(String(format: strings.pasteToFormat, target.name))
                } icon: {
                    if let icon = ClipNoteAppIcons.menuIcon(for: target.bundleID) { Image(nsImage: icon) }
                }
            }
        } else {
            Button(strings.paste) { model.paste(item) }
        }
        if item.type != .image {
            Button(strings.pasteAsPlainText) { model.paste(item, mode: .plainText) }
        }
        Button(strings.copy) { model.copy(item) }
        Button(strings.preview) { model.onPreview?(item) }
        if ClipNoteEditController.isAvailable(for: item) {
            Button(strings.editEllipsis) { model.onEdit?(item) }
        }
        Button(strings.rename) { model.beginEditingTitle(item) }

        let actions = ClipNoteTextAction.textCleaning.filter { $0.isAvailable(item) }
        if !actions.isEmpty {
            Menu(strings.cleanAndPaste) {
                ForEach(actions) { action in
                    Button { model.apply(action, to: item) } label: {
                        Label(action.title(strings), systemImage: action.systemImage)
                    }
                }
            }
        }
        if ClipNoteAIAction.isAvailable(for: item) {
            Menu(strings.aiActions) {
                ForEach(ClipNoteAIAction.all) { action in
                    Button { model.onAIAction?(item, action) } label: {
                        Label(action.title(strings), systemImage: action.systemImage)
                    }
                }
                Divider()
                Button { model.onAICustom?(item) } label: {
                    Label(strings.aiCustomEllipsis, systemImage: "text.bubble")
                }
            }
        }

        Divider()
        Menu(strings.pinToBoard) {
            ForEach(model.pinboards) { board in
                Button {
                    model.pin(item, to: board)
                } label: {
                    Label(board.name, systemImage: item.pinboardID == board.id ? "checkmark.circle.fill" : "circle")
                }
            }
            if model.pinboards.isEmpty {
                Text(strings.noPinboardsYet)
            }
        }
        if item.pinboardID != nil {
            Button(strings.removeFromBoard) { model.pin(item, to: nil) }
        }

        if item.type == .file || item.type == .image {
            Button(strings.revealInFinder) {
                let urls = item.type == .file
                    ? item.filePaths.map { URL(fileURLWithPath: $0) }
                    : [model.store.url(forRelativePath: item.content)]
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
        if item.type == .link, let url = URL(string: item.content) {
            Button(strings.openInBrowser) { NSWorkspace.shared.open(url) }
        }

        Divider()
        Button(strings.delete, role: .destructive) { model.delete(item) }
    }
}

private struct ClipNoteEmptyState: View {
    @ObservedObject var model: ClipNotePanelModel
    let strings: ClipNoteStrings

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyText).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        if !model.query.isEmpty || model.hasActiveFilter { return strings.noMatches }
        if case .pinboard = model.tab { return strings.emptyPinboard }
        return strings.emptyHistory
    }
}
