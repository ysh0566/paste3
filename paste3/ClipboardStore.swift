//
//  ClipboardStore.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
import SwiftData

@MainActor
final class ClipboardStore {
    nonisolated static let defaultMaxItems = 1_000

    private let modelContext: ModelContext
    private let maxItems: Int

    init(modelContext: ModelContext, maxItems: Int = defaultMaxItems) {
        self.modelContext = modelContext
        self.maxItems = maxItems
    }

    @discardableResult
    func insert(_ candidate: ClipboardItemCandidate) throws -> ClipboardItem? {
        if let existingItem = try item(matchingHash: candidate.contentHash) {
            try touch(existingItem)
            return nil
        }

        let item = ClipboardItem(
            kind: candidate.kind,
            text: candidate.text,
            searchText: candidate.searchText,
            sourceAppName: candidate.source.appName,
            sourceBundleIdentifier: candidate.source.bundleIdentifier,
            contentHash: candidate.contentHash,
            byteSize: candidate.byteSize,
            payloadData: candidate.payloadData,
            payloadType: candidate.payloadType
        )
        modelContext.insert(item)
        try modelContext.save()
        try pruneIfNeeded()
        return item
    }

    func items(matching query: String = "") throws -> [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = maxItems

        let items = try modelContext.fetch(descriptor)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { ClipboardClassifier.matches($0, query: trimmedQuery) }
    }

    func delete(_ item: ClipboardItem) throws {
        modelContext.delete(item)
        try modelContext.save()
    }

    func touch(_ item: ClipboardItem) throws {
        item.createdAt = Date()
        try modelContext.save()
    }

    func deleteAll() throws {
        try modelContext.delete(model: ClipboardItem.self)
        try modelContext.save()
    }

    private func item(matchingHash hash: String) throws -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func pruneIfNeeded() throws {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let items = try modelContext.fetch(descriptor)
        guard items.count > maxItems else {
            return
        }

        for item in items.dropFirst(maxItems) {
            modelContext.delete(item)
        }
        try modelContext.save()
    }
}
