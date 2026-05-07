//
//  QuickPanelView.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/5/7.
//

import SwiftData
import SwiftUI

struct QuickPanelView: View {
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @FocusState private var searchFocused: Bool

    @State private var searchText = ""
    @State private var copiedItemID: UUID?

    let onDismiss: () -> Void

    private var filteredItems: [ClipboardItem] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentItems = items.prefix(80)
        guard !trimmedQuery.isEmpty else {
            return Array(recentItems)
        }

        return recentItems.filter { ClipboardClassifier.matches($0, query: trimmedQuery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField
            panelContent
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 920, minHeight: 320, idealHeight: 320)
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
        }
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("paste3")
                .font(.headline.weight(.semibold))

            Spacer()

            Button(action: onDismiss) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }

    private var searchField: some View {
        TextField("Search", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
    }

    @ViewBuilder
    private var panelContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "magnifyingglass")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(filteredItems) { item in
                        QuickPanelCard(
                            item: item,
                            isCopied: copiedItemID == item.id,
                            copyAction: {
                                ClipboardWriter.copyBack(item.text)
                                copiedItemID = item.id
                                onDismiss()
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        }
    }
}

private struct QuickPanelCard: View {
    let item: ClipboardItem
    let isCopied: Bool
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(item.kind.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kindColor)
                Spacer()
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(item.text)
                .font(item.kind == .command ? .system(.callout, design: .monospaced) : .callout)
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 6) {
                Label(item.sourceAppName ?? "Unknown", systemImage: "app")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copyAction) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 220, height: 190, alignment: .topLeading)
        .background(.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .text:
            .secondary
        case .url:
            .blue
        case .command:
            .green
        }
    }
}

#Preview {
    QuickPanelView(onDismiss: {})
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
