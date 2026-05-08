//
//  ClipboardStore.swift
//  paste3
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
    private let referenceDateProvider: () -> Date

    init(
        modelContext: ModelContext,
        retentionPeriod: ClipboardRetentionPeriod? = nil,
        referenceDateProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.retentionPeriod = retentionPeriod ?? ClipboardRetentionPreference.shared.period
        self.referenceDateProvider = referenceDateProvider
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
        try pruneExpiredItemsIfNeeded()
        return item
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

    func pruneExpiredItemsIfNeeded() throws {
        guard let cutoffDate = retentionPeriod.cutoffDate(relativeTo: referenceDateProvider()) else {
            return
        }

        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.createdAt < cutoffDate
            }
        )
        let expiredItems = try modelContext.fetch(descriptor)
        guard !expiredItems.isEmpty else {
            return
        }

        for item in expiredItems {
            modelContext.delete(item)
        }
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
}
