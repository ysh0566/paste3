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

    private let displayMode: HistoryDisplayMode
    private let onDismiss: (() -> Void)?
    private let onPasteRequest: (() -> Void)?

    @State private var selectedFilter: ClipboardFilter = .all
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var copiedItemID: UUID?
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
        let recentItems = Array(items.prefix(ClipboardStore.defaultMaxItems))
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceDate = Date()

        let filteredItems = recentItems.filter { item in
            selectedFilter.matches(item) &&
                (trimmedQuery.isEmpty || ClipboardClassifier.matches(item, query: trimmedQuery))
        }

        // Build the card display strings once per body pass so rendering does not
        // redo filter and formatter work independently in every card.
        return HistorySnapshot(
            recentCount: recentItems.count,
            cards: filteredItems.map { item in
                ClipboardCardSnapshot(
                    item: item,
                    detailText: ClipboardCardFormatters.detailText(for: item),
                    createdAtText: ClipboardCardFormatters.relativeTimestamp(for: item.createdAt, relativeTo: referenceDate)
                )
            }
        )
    }

    var body: some View {
        let snapshot = historySnapshot
        let cardIDs = snapshot.cards.map(\.id)

        ZStack(alignment: .bottom) {
            outerBackground

            VStack(spacing: 0) {
                header
                historyContent(cards: snapshot.cards, recentCount: snapshot.recentCount)
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
            resetSelection(to: cardIDs)
            focusHistory()
        }
        .onChange(of: cardIDs) { _, newIDs in
            normalizeSelection(in: newIDs)
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
    }

    private var header: some View {
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
            }

            Spacer(minLength: 16)

            searchField

            utilityButton(systemImage: "bolt.horizontal.circle", help: "Clipboard monitor is running") {}
                .disabled(true)
        }
        .padding(.horizontal, 24)
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

    private var filterTabs: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
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

    @ViewBuilder
    private func historyContent(cards: [ClipboardCardSnapshot], recentCount: Int) -> some View {
        if cards.isEmpty {
            emptyState(recentCount: recentCount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .frame(minHeight: HistoryLayout.cardContentHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Paste3Theme.gutter) {
                        ForEach(cards) { card in
                            ClipboardCard(
                                snapshot: card,
                                isSelected: selectedItemID == card.id,
                                isCopied: copiedItemID == card.id,
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

    private func emptyState(recentCount: Int) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(palette.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 62, height: 62)

                Image(systemName: recentCount == 0 ? ClipboardFilter.all.emptyStateImage : selectedFilter.emptyStateImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette.primary)
            }

            VStack(spacing: 5) {
                Text(emptyStateTitle(recentCount: recentCount))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.text)

                Text(emptyStateMessage(recentCount: recentCount))
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

    private func emptyStateTitle(recentCount: Int) -> String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching clips"
        }

        return recentCount == 0 ? ClipboardFilter.all.emptyTitle : selectedFilter.emptyTitle
    }

    private func emptyStateMessage(recentCount: Int) -> String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search term or switch to another category."
        }

        if recentCount > 0 {
            return "Switch to All Items to browse the rest of your clipboard history."
        }

        return "Copy text, URLs, images, files, rich text, commands, or app data in another app. They will appear here."
    }

    private func footer(recentCount: Int) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 8) {
                Text("STORAGE:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.tertiaryText)

                ProgressView(value: min(Double(recentCount), Double(ClipboardStore.defaultMaxItems)), total: Double(ClipboardStore.defaultMaxItems))
                    .progressViewStyle(.linear)
                    .tint(palette.primary)
                    .frame(width: 96)

                Text("\(recentCount)/\(ClipboardStore.defaultMaxItems) items")
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

    private func utilityButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 32, height: 32)
                .paste3GlassSurface(
                    cornerRadius: Paste3Theme.controlRadius,
                    fill: palette.insetFill.opacity(0.30)
                )
        }
        .buttonStyle(.plain)
        .help(help)
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
    let cards: [ClipboardCardSnapshot]
}

private struct ClipboardCardSnapshot: Identifiable {
    var id: UUID { item.id }

    let item: ClipboardItem
    let detailText: String
    let createdAtText: String
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

private struct ClipboardCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: ClipboardCardSnapshot
    let isSelected: Bool
    let isCopied: Bool
    let selectAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void

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
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(tapGesture)
        .contextMenu {
            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
        }
        .help("Click to select. Double-click to copy. Right-click to delete.")
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
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
