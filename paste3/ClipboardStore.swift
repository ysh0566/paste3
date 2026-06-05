//
//  ClipboardStore.swift
//  Paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
import SwiftData

struct ClipboardRetentionPeriod: Equatable, Identifiable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
        case forever
    }

    let id: String
    let value: Int
    let unit: Unit

    var title: String {
        switch unit {
        case .day:
            "\(value) 天"
        case .week:
            "\(value) 周"
        case .month:
            "\(value) 个月"
        case .year:
            "\(value) 年"
        case .forever:
            "永久"
        }
    }

    var detail: String {
        switch unit {
        case .forever:
            "不会自动删除历史记录"
        default:
            "保留最近 \(title) 内的历史"
        }
    }

    static let all: [ClipboardRetentionPeriod] =
        (1...6).map { ClipboardRetentionPeriod(id: "day-\($0)", value: $0, unit: .day) } +
        (1...3).map { ClipboardRetentionPeriod(id: "week-\($0)", value: $0, unit: .week) } +
        (1...11).map { ClipboardRetentionPeriod(id: "month-\($0)", value: $0, unit: .month) } +
        (1...3).map { ClipboardRetentionPeriod(id: "year-\($0)", value: $0, unit: .year) } +
        [ClipboardRetentionPeriod(id: "forever", value: 0, unit: .forever)]

    static let defaultPeriod = ClipboardRetentionPeriod(id: "year-1", value: 1, unit: .year)

    static func find(id: String) -> ClipboardRetentionPeriod {
        all.first { $0.id == id } ?? defaultPeriod
    }

    static func index(forID id: String) -> Int {
        all.firstIndex { $0.id == id } ?? all.firstIndex(of: defaultPeriod) ?? 0
    }

    func cutoffDate(relativeTo date: Date, calendar: Calendar = .current) -> Date? {
        // Calendar keeps month and year retention aligned with the user's local calendar
        // instead of approximating those periods as a fixed number of seconds.
        switch unit {
        case .day:
            calendar.date(byAdding: .day, value: -value, to: date)
        case .week:
            calendar.date(byAdding: .day, value: -(value * 7), to: date)
        case .month:
            calendar.date(byAdding: .month, value: -value, to: date)
        case .year:
            calendar.date(byAdding: .year, value: -value, to: date)
        case .forever:
            nil
        }
    }
}

@MainActor
final class ClipboardRetentionPreference {
    static let shared = ClipboardRetentionPreference()

    private static let storageKey = "clipboardRetentionPeriodID"

    private let defaults: UserDefaults
    private(set) var period: ClipboardRetentionPeriod

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        period = ClipboardRetentionPeriod.find(id: defaults.string(forKey: Self.storageKey) ?? "")
    }

    func setPeriod(_ period: ClipboardRetentionPeriod) {
        guard self.period != period else {
            return
        }

        self.period = period
        defaults.set(period.id, forKey: Self.storageKey)
    }
}

@MainActor
final class ClipboardStore {
    static let defaultRetentionPeriod = ClipboardRetentionPeriod.defaultPeriod

    private let modelContext: ModelContext
    private let retentionPeriod: ClipboardRetentionPeriod
    private let payloadStore: ClipboardPayloadStore
    private let searchIndex: ClipboardSearchIndex?
    private let referenceDateProvider: () -> Date

    init(
        modelContext: ModelContext,
        retentionPeriod: ClipboardRetentionPeriod? = nil,
        payloadStore: ClipboardPayloadStore? = nil,
        searchIndex: ClipboardSearchIndex? = nil,
        referenceDateProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.retentionPeriod = retentionPeriod ?? ClipboardRetentionPreference.shared.period
        self.payloadStore = payloadStore ?? ClipboardPayloadStore.shared
        self.searchIndex = searchIndex ?? ClipboardSearchIndex.shared
        self.referenceDateProvider = referenceDateProvider
    }

    @discardableResult
    func insert(_ candidate: ClipboardItemCandidate) throws -> ClipboardItem? {
        if let existingItem = try item(matchingHash: candidate.contentHash) {
            try touch(existingItem)
            return nil
        }

        var payloadData = candidate.payloadData
        let payloadFileName: String?
        if let data = candidate.payloadData {
            payloadFileName = try payloadStore.write(data, payloadType: candidate.payloadType)
            payloadData = nil
        } else {
            payloadFileName = nil
        }

        let item = ClipboardItem(
            kind: candidate.kind,
            text: candidate.text,
            searchText: candidate.searchText,
            sourceAppName: candidate.source.appName,
            sourceBundleIdentifier: candidate.source.bundleIdentifier,
            contentHash: candidate.contentHash,
            byteSize: candidate.byteSize,
            payloadData: payloadData,
            payloadType: candidate.payloadType,
            payloadFileName: payloadFileName
        )
        do {
            modelContext.insert(item)
            try modelContext.save()
            try searchIndex?.upsert(item)
            try pruneExpiredItemsIfNeeded()
            return item
        } catch {
            if let payloadFileName {
                try? payloadStore.delete(fileName: payloadFileName)
            }
            throw error
        }
    }

    func items(matching query: String = "") throws -> [ClipboardItem] {
        try pruneExpiredItemsIfNeeded()

        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let items = try modelContext.fetch(descriptor)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        let parsedQuery = ClipboardSearchQuery.parse(trimmedQuery)
        return items.filter { parsedQuery.matches($0) }
    }

    func itemsPage(
        offset: Int,
        limit: Int,
        matchingKinds kinds: [ClipboardKind]? = nil,
        matching query: ClipboardSearchQuery? = nil,
        matchingItemIDs itemIDs: Set<UUID>? = nil,
        pinboardNamesByItemID: [UUID: [String]] = [:],
        pruneExpiredItems: Bool = true
    ) throws -> [ClipboardItem] {
        if pruneExpiredItems {
            try pruneExpiredItemsIfNeeded()
        }

        let query = query ?? ClipboardSearchQuery.parse("")
        let sortBy = [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
        let queryKinds = query.matchingKinds
        let effectiveKinds: [ClipboardKind]?
        switch (kinds, queryKinds) {
        case (.some(let kinds), .some(let queryKinds)):
            let queryKindSet = Set(queryKinds)
            effectiveKinds = kinds.filter { queryKindSet.contains($0) }
        case (.some(let kinds), .none):
            effectiveKinds = kinds
        case (.none, .some(let queryKinds)):
            effectiveKinds = queryKinds
        case (.none, .none):
            effectiveKinds = nil
        }

        if effectiveKinds?.isEmpty == true {
            return []
        }

        let rawValues = effectiveKinds?.map(\.rawValue) ?? []
        let hasKindFilter = effectiveKinds != nil
        let searchTerms = query.databaseSearchTerms
        let primarySearchTerm = searchTerms.first ?? ""
        let hasPrimarySearchTerm = !primarySearchTerm.isEmpty
        let scopedItemIDs = itemIDs.map(Array.init) ?? []
        let hasItemIDScope = itemIDs != nil
        let indexedItemIDs = indexedItemIDs(
            primarySearchTerm: primarySearchTerm,
            candidateLimit: 5_000,
            enabled: hasPrimarySearchTerm && !hasItemIDScope
        )
        if indexedItemIDs?.isEmpty == true {
            return []
        }
        var candidateOffset = 0
        var skippedMatches = 0
        var pageItems: [ClipboardItem] = []
        let candidateLimit = max(limit * 4, 100)
        let activeScopedItemIDs = indexedItemIDs ?? scopedItemIDs
        let activeHasItemIDScope = indexedItemIDs != nil || hasItemIDScope
        let shouldFilterBySearchText = hasPrimarySearchTerm && indexedItemIDs == nil

        while pageItems.count < limit {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { item in
                    (!hasKindFilter || rawValues.contains(item.kindRawValue)) &&
                        (!shouldFilterBySearchText || item.searchText.contains(primarySearchTerm)) &&
                        (!activeHasItemIDScope || activeScopedItemIDs.contains(item.id))
                },
                sortBy: sortBy
            )
            descriptor.fetchOffset = candidateOffset
            descriptor.fetchLimit = candidateLimit

            let candidates = try ClipboardPerformanceProbe.measure("clipboard.itemsPage.fetch") {
                try modelContext.fetch(descriptor)
            }
            guard !candidates.isEmpty else {
                break
            }

            candidateOffset += candidates.count
            for item in candidates {
                guard query.matches(item, pinboardNames: pinboardNamesByItemID[item.id] ?? []) else {
                    continue
                }

                if skippedMatches < offset {
                    skippedMatches += 1
                    continue
                }

                pageItems.append(item)
                if pageItems.count == limit {
                    break
                }
            }

            if candidates.count < candidateLimit {
                break
            }
        }

        return pageItems
    }

    func delete(_ item: ClipboardItem) throws {
        try deletePayloadIfNeeded(for: item)
        modelContext.delete(item)
        try modelContext.save()
        try searchIndex?.delete(itemID: item.id)
    }

    func touch(_ item: ClipboardItem) throws {
        item.createdAt = Date()
        try modelContext.save()
    }

    func deleteAll() throws {
        let items = try modelContext.fetch(FetchDescriptor<ClipboardItem>())
        for item in items {
            try deletePayloadIfNeeded(for: item)
        }
        try modelContext.delete(model: ClipboardItem.self)
        try modelContext.save()
        try searchIndex?.rebuild(from: [])
    }

    func pruneExpiredItemsIfNeeded() throws {
        guard let cutoffDate = retentionPeriod.cutoffDate(relativeTo: referenceDateProvider()) else {
            return
        }

        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { item in
                    item.createdAt < cutoffDate
                },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            descriptor.fetchLimit = ClipboardStoreBatching.pruneBatchSize

            let expiredItems = try modelContext.fetch(descriptor)
            guard !expiredItems.isEmpty else {
                return
            }

            for item in expiredItems {
                try deletePayloadIfNeeded(for: item)
                modelContext.delete(item)
                try searchIndex?.delete(itemID: item.id)
            }
            try modelContext.save()
        }
    }

    func payloadData(for item: ClipboardItem) throws -> Data? {
        if let payloadData = item.payloadData {
            return payloadData
        }

        guard let payloadFileName = item.payloadFileName else {
            return nil
        }

        return try payloadStore.read(fileName: payloadFileName)
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

    private func deletePayloadIfNeeded(for item: ClipboardItem) throws {
        guard let payloadFileName = item.payloadFileName else {
            return
        }

        try payloadStore.delete(fileName: payloadFileName)
    }

    private func indexedItemIDs(primarySearchTerm: String, candidateLimit: Int, enabled: Bool) -> [UUID]? {
        guard enabled,
              let searchIndex,
              ClipboardSearchIndex.canSearch(primaryTerm: primarySearchTerm)
        else {
            return nil
        }

        return try? searchIndex.searchIDs(
            primaryTerm: primarySearchTerm,
            limit: candidateLimit,
            offset: 0
        )
    }
}

private enum ClipboardStoreBatching {
    static let pruneBatchSize = 250
}
