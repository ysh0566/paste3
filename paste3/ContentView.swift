//
//  ContentView.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import SwiftData
import SwiftUI

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

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    private let displayMode: HistoryDisplayMode
    private let onDismiss: (() -> Void)?

    @State private var selectedFilter: ClipboardFilter = .all
    @State private var searchText = ""
    @State private var copiedItemID: UUID?

    init(displayMode: HistoryDisplayMode = .window, onDismiss: (() -> Void)? = nil) {
        self.displayMode = displayMode
        self.onDismiss = onDismiss
    }

    private var palette: Paste3Theme.Palette {
        Paste3Theme.palette(for: colorScheme)
    }

    @ViewBuilder
    private var outerBackground: some View {
        switch displayMode {
        case .window:
            palette.background
                .ignoresSafeArea()
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
                    byteSizeText: ClipboardCardFormatters.byteSize(item.byteSize),
                    createdAtText: ClipboardCardFormatters.relativeTimestamp(for: item.createdAt, relativeTo: referenceDate)
                )
            }
        )
    }

    var body: some View {
        let snapshot = historySnapshot

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
        .onExitCommand {
            onDismiss?()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                Text("ClipFlow")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)

                filterTabs
            }

            Spacer(minLength: 16)

            searchField

            utilityButton(systemImage: "bolt.horizontal.circle", help: "Clipboard monitor is running") {}
                .disabled(true)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(palette.topBarFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
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
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(selectedFilter == filter ? palette.primary : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            Capsule()
                .fill(colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.05))
        }
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
        .frame(width: 230, height: 32)
        .background {
            RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                .fill(palette.insetFill.opacity(colorScheme == .dark ? 0.72 : 1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func historyContent(cards: [ClipboardCardSnapshot], recentCount: Int) -> some View {
        if cards.isEmpty {
            emptyState(recentCount: recentCount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .frame(minHeight: 226)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Paste3Theme.gutter) {
                    ForEach(cards) { card in
                        ClipboardCard(
                            snapshot: card,
                            isCopied: copiedItemID == card.id,
                            copyAction: {
                                ClipboardWriter.copyBack(card.item.text)
                                copiedItemID = card.id
                                touch(card.item)
                                onDismiss?()
                            },
                            deleteAction: {
                                delete(card.item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 226)
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

        return "Copy text, URLs, commands, or code snippets in another app. They will appear here."
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
        .frame(height: 42)
        .background(palette.topBarFill.opacity(0.78))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)
        }
    }

    private func utilityButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                        .fill(Color.clear)
                }
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
}

private enum ClipboardFilter: CaseIterable, Identifiable {
    case all
    case text
    case links
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
    let byteSizeText: String
    let createdAtText: String
}

@MainActor
private enum ClipboardCardFormatters {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func byteSize(_ bytes: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(bytes))
    }

    static func relativeTimestamp(for date: Date, relativeTo referenceDate: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

private struct ClipboardCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: ClipboardCardSnapshot
    let isCopied: Bool
    let copyAction: () -> Void
    let deleteAction: () -> Void

    @State private var isHovering = false

    private var palette: Paste3Theme.Palette {
        Paste3Theme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    kindPill
                    Spacer()
                    Image(systemName: isCopied ? "checkmark.circle.fill" : snapshot.item.kind.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCopied ? Paste3Theme.success : snapshot.item.kind.tint(for: colorScheme))
                }

                contentPreview
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                sourceBadge

                Spacer()

                Text(snapshot.createdAtText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .padding(14)
        .frame(width: snapshot.item.kind == .text && snapshot.item.text.count > 300 ? 360 : 280, height: 210, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous)
                .fill(isCopied ? Paste3Theme.success.opacity(0.12) : isHovering ? palette.primary.opacity(0.10) : palette.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous)
                .stroke(isCopied ? Paste3Theme.success.opacity(0.72) : isHovering ? palette.primary.opacity(0.58) : palette.border, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 12, x: 0, y: 6)
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(perform: copyAction)
        .contextMenu {
            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
        }
        .help("Click to copy. Right-click to delete.")
    }

    private var kindPill: some View {
        Text(snapshot.item.kind.badgeTitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(snapshot.item.kind.badgeText(for: colorScheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(snapshot.item.kind.badgeFill(for: colorScheme))
            }
    }

    @ViewBuilder
    private var contentPreview: some View {
        if snapshot.item.kind == .url {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.item.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .underline()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                            .fill(palette.insetFill.opacity(colorScheme == .dark ? 0.42 : 1))
                    }

                Text(snapshot.item.searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
        } else {
            ScrollView {
                Text(snapshot.item.text)
                    .font(snapshot.item.kind == .command ? .system(size: 13, design: .monospaced) : .system(size: 13))
                    .foregroundStyle(palette.text)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 118)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                    .fill(snapshot.item.kind == .command ? palette.insetFill.opacity(0.9) : Color.clear)
            }
            .overlay {
                if snapshot.item.kind == .command {
                    RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.5)
                }
            }
        }
    }

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(snapshot.item.kind.tint(for: colorScheme).opacity(0.22))
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: snapshot.item.kind.sourceSymbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(snapshot.item.kind.tint(for: colorScheme))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.item.sourceAppName?.isEmpty == false ? snapshot.item.sourceAppName! : "Unknown")
                    .lineLimit(1)
                Text(snapshot.byteSizeText)
                    .foregroundStyle(palette.tertiaryText)
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.secondaryText)
        }
    }
}

extension ClipboardKind {
    var badgeTitle: String {
        switch self {
        case .text:
            "TEXT SNIPPET"
        case .url:
            "LINK"
        case .command:
            "COMMAND"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            "text.quote"
        case .url:
            "link"
        case .command:
            "terminal"
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
        }
    }

    func tint(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .text:
            Paste3Theme.palette(for: colorScheme).primary
        case .url:
            colorScheme == .dark ? Color(red: 1.0, green: 0.71, blue: 0.58) : Color(red: 0.0, green: 0.42, blue: 0.15)
        case .command:
            Paste3Theme.success
        }
    }

    func badgeFill(for colorScheme: ColorScheme) -> Color {
        tint(for: colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.18)
    }

    func badgeText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? tint(for: colorScheme) : Paste3Theme.palette(for: colorScheme).secondaryText
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
