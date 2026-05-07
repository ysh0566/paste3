//
//  ContentView.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var searchText = ""
    @State private var copiedItemID: UUID?

    private var filteredItems: [ClipboardItem] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return Array(items.prefix(ClipboardStore.defaultMaxItems))
        }

        return items
            .prefix(ClipboardStore.defaultMaxItems)
            .filter { ClipboardClassifier.matches($0, query: trimmedQuery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchField
            historyContent
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("paste3")
                    .font(.title2.weight(.semibold))
                Text("Developer clipboard history, local-first.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                deleteAllItems()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(items.isEmpty)
        }
    }

    private var searchField: some View {
        TextField("Search code, links, commands...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .font(.body)
    }

    @ViewBuilder
    private var historyContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView {
                Label("No clipboard history", systemImage: "doc.on.clipboard")
            } description: {
                Text("Copy text, URLs, commands, or code snippets in another app. They will appear here.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(filteredItems) { item in
                        ClipboardCard(
                            item: item,
                            isCopied: copiedItemID == item.id,
                            copyAction: {
                                ClipboardWriter.copyBack(item.text)
                                copiedItemID = item.id
                            },
                            deleteAction: {
                                delete(item)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
        }
    }

    private func delete(_ item: ClipboardItem) {
        do {
            try ClipboardStore(modelContext: modelContext).delete(item)
        } catch {
            assertionFailure("Failed to delete clipboard item: \(error)")
        }
    }

    private func deleteAllItems() {
        do {
            try ClipboardStore(modelContext: modelContext).deleteAll()
        } catch {
            assertionFailure("Failed to clear clipboard history: \(error)")
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let isCopied: Bool
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.kind.title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kindColor)
                Spacer()
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(item.text)
                    .font(item.kind == .command ? .system(.body, design: .monospaced) : .body)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 132)

            HStack(spacing: 8) {
                if let sourceAppName = item.sourceAppName, !sourceAppName.isEmpty {
                    Label(sourceAppName, systemImage: "app")
                        .lineLimit(1)
                } else {
                    Label("Unknown app", systemImage: "app.dashed")
                }

                Spacer()

                Button(action: copyAction) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }

                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 260, height: 230, alignment: .topLeading)
        .background(.regularMaterial)
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
    ContentView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
