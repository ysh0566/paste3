//
//  ContentView.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum HistoryDisplayMode {
    case window
    case floatingPanel

    var minimumSize: CGSize {
        switch self {
        case .window:
            CGSize(width: 980, height: 430)
        case .floatingPanel:
            .zero
        }
    }
}

private enum HistoryLayout {
    static let cardSide: CGFloat = 220
    static let cardVerticalInset: CGFloat = 8
    static let cardContentHeight = cardSide + cardVerticalInset * 2
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Query(sort: [SortDescriptor(\Pinboard.sortOrder), SortDescriptor(\Pinboard.createdAt, order: .forward)]) private var pinboards: [Pinboard]
    @Query(sort: \PinnedClipboardItem.createdAt, order: .reverse) private var pinnedItems: [PinnedClipboardItem]

    private let displayMode: HistoryDisplayMode
    private let onDismiss: (() -> Void)?
    private let onPasteRequest: (() -> Void)?

    @State private var selectedFilter: ClipboardFilter = .all
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var selectedPinboardID: UUID?
    @State private var deletePinboard: Pinboard?
    @State private var isShowingDeletePinboardAlert = false
    @State private var draggingPinboardID: UUID?
    @State private var lastReorderTargetPinboardID: UUID?
    @State private var pinboardFrames: [UUID: CGRect] = [:]
    @State private var copiedItemID: UUID?
    @State private var isCommandKeyPressed = false
#if os(macOS)
    @State private var commandShortcutMonitor: Any?
#endif
    @FocusState private var historyHasKeyboardFocus: Bool

    init(
        displayMode: HistoryDisplayMode = .window,
        onDismiss: (() -> Void)? = nil,
        onPasteRequest: (() -> Void)? = nil
    ) {
        self.displayMode = displayMode
        self.onDismiss = onDismiss
        self.onPasteRequest = onPasteRequest
    }

    private var palette: Paste3Theme.Palette {
        Paste3Theme.palette(for: colorScheme)
    }

    @ViewBuilder
    private var outerBackground: some View {
        switch displayMode {
        case .window:
            Paste3LiquidBackdrop(palette: palette)
        case .floatingPanel:
            Color.clear
        }
    }

    private var shellPadding: EdgeInsets {
        switch displayMode {
        case .window:
            EdgeInsets(
                top: Paste3Theme.margin,
                leading: Paste3Theme.margin,
                bottom: Paste3Theme.margin,
                trailing: Paste3Theme.margin
            )
        case .floatingPanel:
            // Floating mode already has its screen inset from QuickPanelController.
            // Extra horizontal/bottom padding becomes visible empty space around the panel.
            EdgeInsets(
                top: Paste3Theme.margin,
                leading: 0,
                bottom: 0,
                trailing: 0
            )
        }
    }

    private var historySnapshot: HistorySnapshot {
        let recentItems = items
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceDate = Date()
        let pinsByItemID = Dictionary(grouping: pinnedItems, by: \.clipboardItemID)
        let sourceItems: [ClipboardItem]

        if let selectedPinboardID {
            // Pin records are stored separately from clipboard history, so the
            // selected board view resolves pins back to the shared history items.
            let boardPins = pinnedItems.filter { $0.pinboardID == selectedPinboardID }
            var pinOrder: [UUID: Int] = [:]
            for (index, pin) in boardPins.enumerated() where pinOrder[pin.clipboardItemID] == nil {
                pinOrder[pin.clipboardItemID] = index
            }
            sourceItems = recentItems
                .filter { pinOrder[$0.id] != nil }
                .sorted { lhs, rhs in
                    (pinOrder[lhs.id] ?? Int.max) < (pinOrder[rhs.id] ?? Int.max)
                }
        } else {
            sourceItems = recentItems
        }

        let filteredItems = sourceItems.filter { item in
            selectedFilter.matches(item) &&
                (trimmedQuery.isEmpty || ClipboardClassifier.matches(item, query: trimmedQuery))
        }

        // Build the card display strings once per body pass so rendering does not
        // redo filter and formatter work independently in every card.
        return HistorySnapshot(
            recentCount: sourceItems.count,
            isPinboardSelected: selectedPinboardID != nil,
            selectedPinboardName: selectedPinboard?.name,
            cards: filteredItems.map { item in
                ClipboardCardSnapshot(
                    item: item,
                    detailText: ClipboardCardFormatters.detailText(for: item),
                    createdAtText: ClipboardCardFormatters.relativeTimestamp(for: item.createdAt, relativeTo: referenceDate),
                    pinnedPinboardIDs: Set((pinsByItemID[item.id] ?? []).map(\.pinboardID))
                )
            }
        )
    }

    private var selectedPinboard: Pinboard? {
        guard let selectedPinboardID else {
            return nil
        }

        return pinboards.first { $0.id == selectedPinboardID }
    }

    var body: some View {
        let snapshot = historySnapshot
        let cardIDs = snapshot.cards.map(\.id)

        ZStack(alignment: .bottom) {
            outerBackground

            VStack(spacing: 0) {
                header
                historyContent(snapshot: snapshot)
                footer(recentCount: snapshot.recentCount)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paste3GlassShell()
            .padding(shellPadding)
        }
        .frame(minWidth: displayMode.minimumSize.width, minHeight: displayMode.minimumSize.height)
        .focusable()
        .focused($historyHasKeyboardFocus)
        .focusEffectDisabled()
        .onAppear {
            pruneExpiredHistory()
            resetSelection(to: cardIDs)
            focusHistory()
            installCommandShortcutMonitor(cards: snapshot.cards)
        }
        .onDisappear {
            uninstallCommandShortcutMonitor()
        }
        .onChange(of: cardIDs) { _, newIDs in
            normalizeSelection(in: newIDs)
            installCommandShortcutMonitor(cards: snapshot.cards)
        }
        .onChange(of: pinboards.map(\.id)) { _, pinboardIDs in
            if let selectedPinboardID, !pinboardIDs.contains(selectedPinboardID) {
                self.selectedPinboardID = nil
            }
        }
        .onKeyPress(.leftArrow) {
            moveSelection(.previous, in: cardIDs)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(.next, in: cardIDs)
            return .handled
        }
        .onKeyPress(.return) {
            pasteSelectedItem(in: snapshot.cards)
            return .handled
        }
        .onExitCommand {
            onDismiss?()
        }
        .alert("删除 Pinboard?", isPresented: $isShowingDeletePinboardAlert) {
            Button("删除", role: .destructive, action: commitPinboardDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除 Pinboard 和其中的 pin 记录，不会删除剪贴板历史。")
        }
    }

    private var header: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)
            let pinboardMaxWidth = contentWidth / 2

            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    Text("Paste3")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.text, palette.secondaryText],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    filterTabs

                    searchField
                }

                Spacer(minLength: 16)

                pinboardBar(maxWidth: pinboardMaxWidth)
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: 64)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            palette.edgeHighlight.opacity(colorScheme == .dark ? 0.10 : 0.36),
                            palette.topBarFill,
                            palette.glassGlow.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [palette.edgeHighlight.opacity(0.65), palette.border.opacity(0.40)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
    }

    private func pinboardBar(maxWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            pinboardControls(isScrollable: false, listWidth: maxWidth)
            pinboardControls(isScrollable: true, listWidth: maxWidth)
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
    }

    private func pinboardControls(isScrollable: Bool, listWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            pinboardList(isScrollable: isScrollable, listWidth: listWidth)

            Button(action: createPinboard) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新建 Pinboard")
        }
    }

    @ViewBuilder
    private func pinboardList(isScrollable: Bool, listWidth: CGFloat) -> some View {
        if isScrollable {
            ScrollView(.horizontal) {
                pinboardChipRow
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(width: max(0, listWidth - 44))
        } else {
            pinboardChipRow
        }
    }

    private var pinboardChipRow: some View {
        HStack(spacing: 10) {
            ForEach(pinboards) { pinboard in
                PinboardChip(
                    pinboard: pinboard,
                    isSelected: selectedPinboardID == pinboard.id,
                    isDragging: draggingPinboardID == pinboard.id,
                    selectAction: {
                        selectedPinboardID = pinboard.id
                        focusHistory()
                    },
                    renameAction: { name in
                        rename(pinboard, to: name)
                    },
                    deleteAction: {
                        beginPinboardDelete(pinboard)
                    },
                    setColorAction: { color in
                        setColor(color, for: pinboard)
                    }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PinboardFramePreferenceKey.self,
                            value: [pinboard.id: proxy.frame(in: .named("pinboardRow"))]
                        )
                    }
                }
            }
        }
        .coordinateSpace(name: "pinboardRow")
        .gesture(pinboardReorderGesture)
        .onPreferenceChange(PinboardFramePreferenceKey.self) { frames in
            pinboardFrames = frames
        }
    }

    private var pinboardReorderGesture: some Gesture {
        // Long press marks reorder intent; drag locations are then matched against
        // measured chip frames so the gesture also works inside the horizontal list.
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 4, coordinateSpace: .named("pinboardRow")))
            .onChanged { value in
                guard case let .second(true, drag?) = value else {
                    return
                }

                if draggingPinboardID == nil {
                    draggingPinboardID = pinboardID(at: drag.startLocation)
                }

                guard let draggingPinboardID,
                      let targetPinboardID = pinboardID(at: drag.location),
                      targetPinboardID != draggingPinboardID,
                      targetPinboardID != lastReorderTargetPinboardID,
                      let draggingPinboard = pinboards.first(where: { $0.id == draggingPinboardID }),
                      let targetPinboard = pinboards.first(where: { $0.id == targetPinboardID })
                else {
                    return
                }

                lastReorderTargetPinboardID = targetPinboardID
                swapPinboard(draggingPinboard, with: targetPinboard)
            }
            .onEnded { _ in
                draggingPinboardID = nil
                lastReorderTargetPinboardID = nil
            }
    }

    private func pinboardID(at location: CGPoint) -> UUID? {
        pinboardFrames.first { _, frame in
            frame.contains(location)
        }?.key
    }

    private var filterTabs: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                    selectedPinboardID = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filter.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(filter.title)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selectedFilter == filter ? palette.primaryText : palette.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if selectedFilter == filter {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            palette.primary.opacity(0.94),
                                            palette.primary.opacity(0.70)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(alignment: .topLeading) {
                                    Capsule()
                                        .stroke(palette.edgeHighlight.opacity(0.55), lineWidth: 0.8)
                                }
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .paste3GlassSurface(
            cornerRadius: 18,
            fill: colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.20)
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(palette.text)
        }
        .padding(.horizontal, 10)
        .frame(width: 238, height: 34)
        .paste3GlassSurface(
            cornerRadius: Paste3Theme.controlRadius,
            fill: palette.insetFill.opacity(colorScheme == .dark ? 0.82 : 0.70)
        )
    }

    private func createPinboard() {
        do {
            let pinboard = try PinboardStore(modelContext: modelContext).createPinboard(existingCount: pinboards.count)
            selectedPinboardID = pinboard.id
            focusHistory()
        } catch {
            assertionFailure("Failed to create pinboard: \(error)")
        }
    }

    private func beginPinboardDelete(_ pinboard: Pinboard) {
        deletePinboard = pinboard
        isShowingDeletePinboardAlert = true
    }

    private func rename(_ pinboard: Pinboard, to name: String) {
        do {
            try PinboardStore(modelContext: modelContext).rename(pinboard, to: name)
        } catch {
            assertionFailure("Failed to rename pinboard: \(error)")
        }
    }

    private func setColor(_ color: PinboardColor, for pinboard: Pinboard) {
        do {
            try PinboardStore(modelContext: modelContext).setColor(color, for: pinboard)
        } catch {
            assertionFailure("Failed to set pinboard color: \(error)")
        }
    }

    private func swapPinboard(_ lhs: Pinboard, with rhs: Pinboard) {
        do {
            try PinboardStore(modelContext: modelContext).swap(lhs, with: rhs, in: pinboards)
        } catch {
            assertionFailure("Failed to reorder pinboards: \(error)")
        }
    }

    private func commitPinboardDelete() {
        guard let deletePinboard else {
            return
        }

        do {
            if selectedPinboardID == deletePinboard.id {
                selectedPinboardID = nil
            }
            try PinboardStore(modelContext: modelContext).delete(deletePinboard)
            self.deletePinboard = nil
        } catch {
            assertionFailure("Failed to delete pinboard: \(error)")
        }
    }

    private func pin(_ item: ClipboardItem, to pinboard: Pinboard) {
        do {
            try PinboardStore(modelContext: modelContext).pin(item, to: pinboard)
        } catch {
            assertionFailure("Failed to pin clipboard item: \(error)")
        }
    }

    private func unpin(_ item: ClipboardItem, from pinboard: Pinboard) {
        do {
            try PinboardStore(modelContext: modelContext).unpin(item, from: pinboard)
        } catch {
            assertionFailure("Failed to unpin clipboard item: \(error)")
        }
    }

    @ViewBuilder
    private func historyContent(snapshot: HistorySnapshot) -> some View {
        let cards = snapshot.cards

        if cards.isEmpty {
            emptyState(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .frame(minHeight: HistoryLayout.cardContentHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Paste3Theme.gutter) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            ClipboardCard(
                                snapshot: card,
                                isSelected: selectedItemID == card.id,
                                isCopied: copiedItemID == card.id,
                                shortcutNumber: shortcutNumber(forCardAt: index),
                                selectAction: {
                                    selectedItemID = card.id
                                    focusHistory()
                                },
                                copyAction: {
                                    copy(card, shouldPaste: false)
                                },
                                deleteAction: {
                                    if selectedItemID == card.id {
                                        selectedItemID = nil
                                    }
                                    delete(card.item)
                                },
                                pinboards: pinboards,
                                selectedPinboard: selectedPinboard,
                                pinAction: { pinboard in
                                    pin(card.item, to: pinboard)
                                },
                                unpinAction: { pinboard in
                                    unpin(card.item, from: pinboard)
                                }
                            )
                            .id(card.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(minHeight: HistoryLayout.cardContentHeight)
                .onChange(of: selectedItemID) { _, selectedID in
                    guard let selectedID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private func emptyState(snapshot: HistorySnapshot) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(palette.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 62, height: 62)

                Image(systemName: snapshot.recentCount == 0 ? ClipboardFilter.all.emptyStateImage : selectedFilter.emptyStateImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette.primary)
            }

            VStack(spacing: 5) {
                Text(emptyStateTitle(snapshot: snapshot))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.text)

                Text(emptyStateMessage(snapshot: snapshot))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 420)
    }

    private func emptyStateTitle(snapshot: HistorySnapshot) -> String {
        if snapshot.isPinboardSelected && snapshot.recentCount == 0 {
            return "Pinboard 为空"
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching clips"
        }

        return snapshot.recentCount == 0 ? ClipboardFilter.all.emptyTitle : selectedFilter.emptyTitle
    }

    private func emptyStateMessage(snapshot: HistorySnapshot) -> String {
        if snapshot.isPinboardSelected && snapshot.recentCount == 0 {
            return "点击左侧分类回到历史后，在卡片上右键将内容 pin 到 \(snapshot.selectedPinboardName ?? "这个 Pinboard")。"
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search term or switch to another category."
        }

        if snapshot.recentCount > 0 {
            return "Switch to All Items to browse the rest of your clipboard history."
        }

        return "Copy text, URLs, images, files, rich text, commands, or app data in another app. They will appear here."
    }

    private func footer(recentCount: Int) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 8) {
                Text("RETENTION:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.tertiaryText)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)

                Text("\(ClipboardRetentionPreference.shared.period.title) · \(recentCount) items")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            Text("Press ⌘⇧V to open the quick panel")
                .font(.system(size: 12))
                .foregroundStyle(palette.tertiaryText)

            Text(recentCount == 0 ? "Right-click the status item for settings" : "Right-click the status item to manage history")
                .font(.system(size: 12))
                .foregroundStyle(palette.tertiaryText)
        }
        .padding(.horizontal, 24)
        .frame(height: 46)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            palette.topBarFill.opacity(0.88),
                            palette.glassGlow.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.edgeHighlight.opacity(colorScheme == .dark ? 0.16 : 0.44))
                .frame(height: 0.5)
        }
    }

    private func delete(_ item: ClipboardItem) {
        do {
            try ClipboardStore(modelContext: modelContext).delete(item)
        } catch {
            assertionFailure("Failed to delete clipboard item: \(error)")
        }
    }

    private func touch(_ item: ClipboardItem) {
        do {
            try ClipboardStore(modelContext: modelContext).touch(item)
        } catch {
            assertionFailure("Failed to update clipboard item recency: \(error)")
        }
    }

    private func pruneExpiredHistory() {
        do {
            try ClipboardStore(modelContext: modelContext).pruneExpiredItemsIfNeeded()
        } catch {
            assertionFailure("Failed to prune expired clipboard history: \(error)")
        }
    }

    private func focusHistory() {
        Task { @MainActor in
            historyHasKeyboardFocus = true
        }
    }

    private func resetSelection(to cardIDs: [UUID]) {
        selectedItemID = cardIDs.first
    }

    private func normalizeSelection(in cardIDs: [UUID]) {
        guard !cardIDs.isEmpty else {
            selectedItemID = nil
            return
        }

        if selectedItemID.map({ cardIDs.contains($0) }) != true {
            selectedItemID = cardIDs.first
        }
    }

    private func moveSelection(_ direction: HistorySelectionDirection, in cardIDs: [UUID]) {
        guard !cardIDs.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = selectedItemID.flatMap { cardIDs.firstIndex(of: $0) } ?? 0
        let nextIndex: Int
        switch direction {
        case .previous:
            nextIndex = max(currentIndex - 1, 0)
        case .next:
            nextIndex = min(currentIndex + 1, cardIDs.count - 1)
        }

        selectedItemID = cardIDs[nextIndex]
        copiedItemID = nil
        focusHistory()
    }

    private func pasteSelectedItem(in cards: [ClipboardCardSnapshot]) {
        let selectedCard = selectedItemID
            .flatMap { selectedID in cards.first(where: { $0.id == selectedID }) } ?? cards.first

        guard let selectedCard else {
            return
        }

        copy(selectedCard, shouldPaste: true)
    }

    private func shortcutNumber(forCardAt index: Int) -> Int? {
        guard displayMode == .floatingPanel, isCommandKeyPressed, index < 9 else {
            return nil
        }

        return index + 1
    }

    private func installCommandShortcutMonitor(cards: [ClipboardCardSnapshot]) {
#if os(macOS)
        guard displayMode == .floatingPanel else {
            return
        }

        uninstallCommandShortcutMonitor()
        isCommandKeyPressed = Self.commandKeyIsPressed(in: NSEvent.modifierFlags)
        commandShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            switch event.type {
            case .flagsChanged:
                isCommandKeyPressed = Self.commandKeyIsPressed(in: event.modifierFlags)
                return event
            case .keyDown:
                guard Self.commandKeyIsPressed(in: event.modifierFlags),
                      let cardIndex = Self.cardShortcutIndex(for: event),
                      cards.indices.contains(cardIndex) else {
                    return event
                }

                copy(cards[cardIndex], shouldPaste: false)
                return nil
            default:
                return event
            }
        }
#else
        _ = cards
#endif
    }

    private func uninstallCommandShortcutMonitor() {
#if os(macOS)
        if let commandShortcutMonitor {
            NSEvent.removeMonitor(commandShortcutMonitor)
            self.commandShortcutMonitor = nil
        }
        isCommandKeyPressed = false
#endif
    }

#if os(macOS)
    private static func commandKeyIsPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    private static func cardShortcutIndex(for event: NSEvent) -> Int? {
        // Accept both the top-row number keys and numeric keypad keys so Cmd+1..9
        // behaves consistently across compact and full-size keyboards.
        switch event.keyCode {
        case 18, 83:
            0
        case 19, 84:
            1
        case 20, 85:
            2
        case 21, 86:
            3
        case 23, 87:
            4
        case 22, 88:
            5
        case 26, 89:
            6
        case 28, 91:
            7
        case 25, 92:
            8
        default:
            nil
        }
    }
#endif

    private func copy(_ card: ClipboardCardSnapshot, shouldPaste: Bool) {
        ClipboardWriter.copyBack(card.item)
        selectedItemID = card.id
        copiedItemID = card.id
        touch(card.item)

        if shouldPaste, let onPasteRequest {
            onPasteRequest()
        } else {
            onDismiss?()
        }
    }
}

private enum HistorySelectionDirection {
    case previous
    case next
}

private enum ClipboardFilter: CaseIterable, Identifiable {
    case all
    case text
    case links
    case media
    case files
    case rich
    case commands

    var id: String { title }

    var title: String {
        switch self {
        case .all:
            "All Items"
        case .text:
            "Text"
        case .links:
            "Links"
        case .media:
            "Media"
        case .files:
            "Files"
        case .rich:
            "Rich"
        case .commands:
            "Commands"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "square.stack.3d.up"
        case .text:
            "text.alignleft"
        case .links:
            "link"
        case .media:
            "photo"
        case .files:
            "doc"
        case .rich:
            "textformat"
        case .commands:
            "terminal"
        }
    }

    var emptyStateImage: String {
        switch self {
        case .all:
            "doc.on.clipboard"
        case .text:
            "text.alignleft"
        case .links:
            "link"
        case .media:
            "photo.on.rectangle"
        case .files:
            "doc"
        case .rich:
            "textformat"
        case .commands:
            "terminal"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            "No clipboard history"
        case .text:
            "No text clips"
        case .links:
            "No links"
        case .media:
            "No media clips"
        case .files:
            "No files"
        case .rich:
            "No rich clips"
        case .commands:
            "No commands"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            true
        case .text:
            item.kind == .text
        case .links:
            item.kind == .url
        case .media:
            item.kind == .image
        case .files:
            item.kind == .file
        case .rich:
            item.kind == .html || item.kind == .richText || item.kind == .data
        case .commands:
            item.kind == .command
        }
    }
}

private struct HistorySnapshot {
    let recentCount: Int
    let isPinboardSelected: Bool
    let selectedPinboardName: String?
    let cards: [ClipboardCardSnapshot]
}

private struct ClipboardCardSnapshot: Identifiable {
    var id: UUID { item.id }

    let item: ClipboardItem
    let detailText: String
    let createdAtText: String
    let pinnedPinboardIDs: Set<UUID>
}

@MainActor
private enum ClipboardCardFormatters {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func detailText(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image, .data:
            return byteCount(item.byteSize)
        case .file:
            let count = item.text.split(separator: "\n", omittingEmptySubsequences: true).count
            return "\(count) 个文件"
        case .text, .url, .command, .richText, .html:
            return "\(item.text.count) 个字符"
        }
    }

    static func relativeTimestamp(for date: Date, relativeTo referenceDate: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private static func byteCount(_ byteSize: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteSize))
    }
}

private struct PinboardChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let pinboard: Pinboard
    let isSelected: Bool
    let isDragging: Bool
    let selectAction: () -> Void
    let renameAction: (String) -> Void
    let deleteAction: () -> Void
    let setColorAction: (PinboardColor) -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var shouldSkipBlurCommit = false
    @FocusState private var renameFieldIsFocused: Bool

    private var palette: Paste3Theme.Palette {
        Paste3Theme.palette(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pinboard.colorKind.color)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(palette.edgeHighlight.opacity(0.70), lineWidth: 0.7)
                }

            if isRenaming {
                TextField("未命名", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .focused($renameFieldIsFocused)
                    .frame(width: renameFieldWidth, height: 20)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(pinboard.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.text : palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background {
            Capsule()
                .fill(isSelected || isRenaming ? palette.insetFill.opacity(0.92) : Color.clear)
        }
        .overlay {
            if isRenaming {
                Capsule()
                    .stroke(pinboard.colorKind.color.opacity(0.70), lineWidth: 1.8)
            } else if isDragging {
                Capsule()
                    .stroke(pinboard.colorKind.color.opacity(0.55), lineWidth: 1.4)
            }
        }
        .scaleEffect(isDragging ? 0.96 : 1)
        .opacity(isDragging ? 0.76 : 1)
        .contentShape(Capsule())
        .gesture(
            // Keep single-select and double-rename mutually exclusive so a double click does not also run selection.
            TapGesture(count: 2)
                .onEnded(beginRename)
                .exclusively(before: TapGesture().onEnded {
                    guard !isRenaming else {
                        return
                    }

                    selectAction()
                })
        )
        .onChange(of: renameFieldIsFocused) { _, isFocused in
            guard isRenaming, !isFocused else {
                return
            }

            if shouldSkipBlurCommit {
                shouldSkipBlurCommit = false
            } else {
                commitRename()
            }
        }
        .onChange(of: pinboard.name) { _, newName in
            if !isRenaming {
                draftName = newName
            }
        }
        .contextMenu {
            Button(action: beginRename) {
                Label("重命名", systemImage: "pencil")
            }

            Button(role: .destructive, action: deleteAction) {
                Label("删除...", systemImage: "trash")
            }

            Divider()

            Picker(
                "",
                selection: Binding(
                    get: { pinboard.colorKind },
                    set: setColorAction
                )
            ) {
                ForEach(PinboardColor.allCases) { color in
                    Image(systemName: "circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(color.color)
                        .frame(width: 16, height: 16)
                        .tag(color)
                        .help(color.title)
                }
            }
            .pickerStyle(.palette)
            .controlSize(.mini)
            .labelsHidden()
        }
        .help("点击查看 Pinboard，双击重命名，右键选择颜色")
    }

    private var renameFieldWidth: CGFloat {
        let characterWidth: CGFloat = 8
        let width = CGFloat(max(draftName.count, 3)) * characterWidth + 14
        return min(max(width, 42), 150)
    }

    private func beginRename() {
        draftName = pinboard.name
        isRenaming = true

        DispatchQueue.main.async {
            renameFieldIsFocused = true
        }
    }

    private func commitRename() {
        guard isRenaming else {
            return
        }

        renameAction(draftName)
        isRenaming = false
        renameFieldIsFocused = false
    }

    private func cancelRename() {
        shouldSkipBlurCommit = true
        draftName = pinboard.name
        isRenaming = false
        renameFieldIsFocused = false
    }
}

private struct PinboardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct ClipboardCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: ClipboardCardSnapshot
    let isSelected: Bool
    let isCopied: Bool
    let shortcutNumber: Int?
    let selectAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void
    let pinboards: [Pinboard]
    let selectedPinboard: Pinboard?
    let pinAction: (Pinboard) -> Void
    let unpinAction: (Pinboard) -> Void

    @State private var isHovering = false

    private var palette: Paste3Theme.Palette {
        Paste3Theme.palette(for: colorScheme)
    }

    private let iconSize: CGFloat = 42
    private let footerHeight: CGFloat = 26
    private let previewPadding: CGFloat = 14

    private var headerHeight: CGFloat {
        HistoryLayout.cardSide / 5
    }

    private var imagePreviewSize: CGSize {
        CGSize(
            width: HistoryLayout.cardSide - previewPadding * 2,
            height: HistoryLayout.cardSide - headerHeight - footerHeight - previewPadding * 2
        )
    }

    private var cardFill: Color {
        if isCopied {
            return Paste3Theme.success.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }

        if isSelected {
            return palette.primary.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }

        return isHovering ? palette.primary.opacity(colorScheme == .dark ? 0.13 : 0.10) : palette.cardFill
    }

    private var cardStroke: Color {
        if isCopied {
            return Paste3Theme.success.opacity(0.72)
        }

        if isSelected {
            return palette.primary.opacity(0.82)
        }

        return isHovering ? palette.primary.opacity(0.58) : palette.border
    }

    private var tapGesture: some Gesture {
        // Double-click keeps the previous copy-back behavior, while a single
        // click only changes selection.
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                switch result {
                case .first:
                    copyAction()
                case .second:
                    selectAction()
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            cardHeader

            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            cardFooter
        }
        .frame(width: HistoryLayout.cardSide, height: HistoryLayout.cardSide, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: Paste3Theme.cardRadius, style: .continuous))
        .paste3GlassSurface(
            cornerRadius: Paste3Theme.cardRadius,
            fill: cardFill,
            isProminent: isSelected || isHovering || isCopied
        )
        .overlay {
            RoundedRectangle(cornerRadius: Paste3Theme.cardRadius, style: .continuous)
                .stroke(cardStroke, lineWidth: isSelected ? 1.5 : 0.7)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Paste3Theme.cardRadius, style: .continuous)
                .stroke(palette.edgeHighlight.opacity(colorScheme == .dark ? 0.12 : 0.40), lineWidth: 1)
                .padding(1)
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .bottomTrailing) {
            if let shortcutNumber {
                shortcutBadge(shortcutNumber)
            }
        }
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .animation(.easeOut(duration: 0.10), value: shortcutNumber)
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(tapGesture)
        .contextMenu {
            if !pinboards.isEmpty {
                Menu("Pin 到 Pinboard") {
                    ForEach(pinboards) { pinboard in
                        Button {
                            pinAction(pinboard)
                        } label: {
                            Label(
                                pinboard.name,
                                systemImage: snapshot.pinnedPinboardIDs.contains(pinboard.id) ? "checkmark.circle.fill" : "pin"
                            )
                        }
                        .disabled(snapshot.pinnedPinboardIDs.contains(pinboard.id))
                    }
                }
            }

            if let selectedPinboard, snapshot.pinnedPinboardIDs.contains(selectedPinboard.id) {
                Button {
                    unpinAction(selectedPinboard)
                } label: {
                    Label("从当前 Pinboard 移除", systemImage: "pin.slash")
                }
            }

            if !pinboards.isEmpty || selectedPinboard != nil {
                Divider()
            }

            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
        }
        .help("Click to select. Double-click to copy. Right-click to pin or delete.")
    }

    private func shortcutBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .frame(width: 28, height: 28)
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.primary.opacity(0.98),
                                palette.primary.opacity(0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(palette.edgeHighlight.opacity(0.70), lineWidth: 0.9)
                    }
            }
            .shadow(color: palette.glassShadow.opacity(0.38), radius: 8, x: 0, y: 4)
            .padding(10)
            .accessibilityLabel("Shortcut \(number)")
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.item.kind.cardTitle)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(snapshot.createdAtText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            sourceIcon
                .frame(width: iconSize, height: iconSize)
                .padding(6)
                .background {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.34), lineWidth: 0.8)
                        }
                }
                .overlay(alignment: .topTrailing) {
                    if isCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                    }
                }
        }
        .padding(.horizontal, 14)
        .frame(height: headerHeight)
        .background {
            RoundedRectangle(cornerRadius: Paste3Theme.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            headerFill.opacity(0.92),
                            headerFill.opacity(0.70),
                            .white.opacity(colorScheme == .dark ? 0.07 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [.white.opacity(0.42), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
                .overlay(alignment: .trailing) {
                    Circle()
                        .stroke(.white.opacity(0.26), lineWidth: 1)
                        .frame(width: 78, height: 78)
                        .offset(x: 24)
                }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Paste3Theme.cardRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Paste3Theme.cardRadius,
                style: .continuous
            )
        )
    }

    private var cardFooter: some View {
        HStack {
            Spacer()
            Text(snapshot.detailText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: footerHeight)
    }

    private var headerFill: Color {
#if os(macOS)
        if let color = AppIconAppearanceCache.shared.headerColor(
            for: snapshot.item.sourceBundleIdentifier,
            colorScheme: colorScheme
        ) {
            return color
        }
#endif

        return snapshot.item.kind.headerFill(for: colorScheme)
    }

    @ViewBuilder
    private var sourceIcon: some View {
#if os(macOS)
        if let icon = AppIconAppearanceCache.shared.icon(for: snapshot.item.sourceBundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            fallbackSourceIcon
        }
#else
        fallbackSourceIcon
#endif
    }

    private var fallbackSourceIcon: some View {
        Image(systemName: snapshot.item.kind.sourceSymbolName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .padding(8)
    }

    private var contentText: some View {
        Text(snapshot.item.text)
            .font(snapshot.item.kind == .command ? .system(size: 12, weight: .semibold, design: .monospaced) : .system(size: 13, weight: .medium))
            .foregroundStyle(palette.text)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch snapshot.item.kind {
        case .image:
            imagePreview
        case .file:
            filePreview
        case .data:
            dataPreview
        case .text, .url, .command, .richText, .html:
            textPreview
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if snapshot.item.text.count > 180 || snapshot.item.text.contains("\n") {
            ScrollView {
                contentText
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, 14)
            .padding(.top, 14)
        } else {
            contentText
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.top, 14)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
#if os(macOS)
        if let image = snapshot.item.previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: imagePreviewSize.width, height: imagePreviewSize.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                        .stroke(palette.edgeHighlight.opacity(0.42), lineWidth: 0.8)
                }
                .padding(previewPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            dataPreview
        }
#else
        dataPreview
#endif
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.item.fileDisplayNames.prefix(4), id: \.self) { name in
                HStack(spacing: 7) {
                    Image(systemName: "doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                }
            }

            if snapshot.item.fileDisplayNames.count > 4 {
                Text("+ \(snapshot.item.fileDisplayNames.count - 4) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dataPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: snapshot.item.kind.sourceSymbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.primary)

            Text(snapshot.item.payloadType ?? snapshot.item.kind.cardTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(2)

            Text(snapshot.item.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

private extension ClipboardItem {
    var fileDisplayNames: [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)).lastPathComponent }
    }

#if os(macOS)
    var previewImage: NSImage? {
        guard let payloadData else {
            return nil
        }

        return NSImage(data: payloadData)
    }
#endif
}

#if os(macOS)
@MainActor
private final class AppIconAppearanceCache {
    static let shared = AppIconAppearanceCache()

    private struct Entry {
        let icon: NSImage
        let dominantColor: NSColor?
    }

    private var entries: [String: Entry] = [:]

    func icon(for bundleIdentifier: String?) -> NSImage? {
        entry(for: bundleIdentifier)?.icon
    }

    func headerColor(for bundleIdentifier: String?, colorScheme: ColorScheme) -> Color? {
        guard let dominantColor = entry(for: bundleIdentifier)?.dominantColor else {
            return nil
        }

        return dominantColor.headerColor(for: colorScheme)
    }

    private func entry(for bundleIdentifier: String?) -> Entry? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }

        if let entry = entries[bundleIdentifier] {
            return entry
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let entry = Entry(icon: icon, dominantColor: icon.dominantColor())
        entries[bundleIdentifier] = entry
        return entry
    }
}

private extension NSImage {
    func dominantColor(sampleSize: Int = 28) -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = sampleSize
        let height = sampleSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: (red: Double, green: Double, blue: Double, weight: Double)] = [:]

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.35 else {
                continue
            }

            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

            guard saturation > 0.12, brightness > 0.12, brightness < 0.96 else {
                continue
            }

            let hueBucket = Int((hue * 24).rounded(.down))
            let saturationBucket = Int((saturation * 4).rounded(.down))
            let brightnessBucket = Int((brightness * 4).rounded(.down))
            let key = hueBucket * 100 + saturationBucket * 10 + brightnessBucket
            let weight = alpha * (0.65 + Double(saturation))
            let previous = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (
                previous.red + red * weight,
                previous.green + green * weight,
                previous.blue + blue * weight,
                previous.weight + weight
            )
        }

        guard let dominant = buckets.values.max(by: { $0.weight < $1.weight }), dominant.weight > 0 else {
            return nil
        }

        return NSColor(
            calibratedRed: dominant.red / dominant.weight,
            green: dominant.green / dominant.weight,
            blue: dominant.blue / dominant.weight,
            alpha: 1
        )
    }
}

private extension NSColor {
    func headerColor(for colorScheme: ColorScheme) -> Color {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return Color(self)
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        let adjustedSaturation = min(max(saturation * 1.18, 0.42), 0.88)
        let adjustedBrightness: CGFloat
        if colorScheme == .dark {
            adjustedBrightness = min(max(brightness * 0.72, 0.32), 0.58)
        } else {
            adjustedBrightness = min(max(brightness, 0.54), 0.86)
        }

        return Color(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness)
    }
}
#endif

extension ClipboardKind {
    var cardTitle: String {
        switch self {
        case .text:
            "文本"
        case .url:
            "链接"
        case .command:
            "命令"
        case .image:
            "图片"
        case .file:
            "文件"
        case .richText:
            "富文本"
        case .html:
            "HTML"
        case .data:
            "数据"
        }
    }

    var sourceSymbolName: String {
        switch self {
        case .text:
            "doc.text"
        case .url:
            "globe"
        case .command:
            "chevron.left.forwardslash.chevron.right"
        case .image:
            "photo"
        case .file:
            "doc"
        case .richText:
            "textformat"
        case .html:
            "curlybraces"
        case .data:
            "shippingbox"
        }
    }

    func headerFill(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .text:
            colorScheme == .dark ? Color(red: 0.03, green: 0.55, blue: 0.31) : Color(red: 0.0, green: 0.80, blue: 0.42)
        case .url:
            colorScheme == .dark ? Color(red: 0.07, green: 0.34, blue: 0.82) : Color(red: 0.12, green: 0.43, blue: 0.95)
        case .command:
            colorScheme == .dark ? Color(red: 0.40, green: 0.32, blue: 0.72) : Color(red: 0.48, green: 0.38, blue: 0.82)
        case .image:
            colorScheme == .dark ? Color(red: 0.65, green: 0.24, blue: 0.40) : Color(red: 0.93, green: 0.28, blue: 0.48)
        case .file:
            colorScheme == .dark ? Color(red: 0.35, green: 0.38, blue: 0.44) : Color(red: 0.40, green: 0.45, blue: 0.52)
        case .richText, .html:
            colorScheme == .dark ? Color(red: 0.48, green: 0.35, blue: 0.15) : Color(red: 0.86, green: 0.55, blue: 0.18)
        case .data:
            colorScheme == .dark ? Color(red: 0.28, green: 0.42, blue: 0.47) : Color(red: 0.20, green: 0.58, blue: 0.64)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ClipboardItem.self, Pinboard.self, PinnedClipboardItem.self], inMemory: true)
}
