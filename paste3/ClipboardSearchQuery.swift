//
//  ClipboardSearchQuery.swift
//  Paste3
//
//  Created by Codex on 2026/5/9.
//

import Foundation

struct ClipboardSearchQuery: Equatable {
    private enum Filter: Equatable {
        case app(String)
        case type(String)
        case from(String)
        case pin(String)
    }

    private let terms: [String]
    private let filters: [Filter]

    static func parse(_ rawQuery: String) -> ClipboardSearchQuery {
        var terms: [String] = []
        var filters: [Filter] = []

        for token in tokenize(rawQuery) {
            guard let separatorIndex = token.firstIndex(of: ":") else {
                terms.append(token)
                continue
            }

            let key = token[..<separatorIndex].lowercased()
            let value = String(token[token.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            switch key {
            case "app", "source":
                filters.append(.app(value))
            case "type", "kind":
                filters.append(.type(value))
            case "from", "date":
                filters.append(.from(value))
            case "pin", "board", "pinboard":
                filters.append(.pin(value))
            default:
                terms.append(token)
            }
        }

        return ClipboardSearchQuery(
            terms: terms.map { $0.lowercased() },
            filters: filters
        )
    }

    var isEmpty: Bool {
        terms.isEmpty && filters.isEmpty
    }

    var databaseSearchTerms: [String] {
        terms + filters.compactMap { filter in
            switch filter {
            case .app(let value):
                value.lowercased()
            case .type, .from, .pin:
                nil
            }
        }
    }

    var pinFilterValues: [String] {
        filters.compactMap { filter in
            guard case .pin(let value) = filter else {
                return nil
            }
            return value
        }
    }

    var matchingKinds: [ClipboardKind]? {
        var allowedKinds: Set<ClipboardKind>?
        for filter in filters {
            guard case .type(let value) = filter else {
                continue
            }

            let matchingKinds = Set(ClipboardKind.allCases.filter { kind in
                Self.typeAliases(for: kind).contains { $0.localizedCaseInsensitiveContains(value) }
            })
            allowedKinds = allowedKinds.map { $0.intersection(matchingKinds) } ?? matchingKinds
        }

        guard let allowedKinds else {
            return nil
        }

        return ClipboardKind.allCases.filter { allowedKinds.contains($0) }
    }

    func matches(
        _ item: ClipboardItem,
        pinboardNames: [String] = [],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        guard !isEmpty else {
            return true
        }

        for term in terms where !item.searchText.localizedCaseInsensitiveContains(term) {
            return false
        }

        for filter in filters where !matches(filter, item: item, pinboardNames: pinboardNames, calendar: calendar, now: now) {
            return false
        }

        return true
    }

    private func matches(
        _ filter: Filter,
        item: ClipboardItem,
        pinboardNames: [String],
        calendar: Calendar,
        now: Date
    ) -> Bool {
        switch filter {
        case .app(let value):
            return [item.sourceAppName, item.sourceBundleIdentifier]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(value) }
        case .type(let value):
            return Self.typeAliases(for: item.kind).contains { $0.localizedCaseInsensitiveContains(value) }
        case .from(let value):
            return matchesDateFilter(value, date: item.createdAt, calendar: calendar, now: now)
        case .pin(let value):
            if ["true", "yes", "any"].contains(value.lowercased()) {
                return !pinboardNames.isEmpty
            }

            return pinboardNames.contains { $0.localizedCaseInsensitiveContains(value) }
        }
    }

    private static func typeAliases(for kind: ClipboardKind) -> [String] {
        switch kind {
        case .text:
            ["text", "txt"]
        case .url:
            ["url", "link", "links"]
        case .command:
            ["command", "cmd", "shell", "terminal"]
        case .image:
            ["image", "img", "media", "photo"]
        case .file:
            ["file", "files", "path"]
        case .richText:
            ["rich", "richtext", "rtf"]
        case .html:
            ["rich", "html"]
        case .data:
            ["rich", "data", "binary"]
        }
    }

    private func matchesDateFilter(_ value: String, date: Date, calendar: Calendar, now: Date) -> Bool {
        let lowered = value.lowercased()
        let startOfToday = calendar.startOfDay(for: now)

        switch lowered {
        case "today":
            return date >= startOfToday
        case "yesterday":
            guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
                return false
            }
            return date >= startOfYesterday && date < startOfToday
        case "week", "7d":
            return date >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case "month", "30d":
            return date >= now.addingTimeInterval(-30 * 24 * 60 * 60)
        case "year", "365d":
            return date >= now.addingTimeInterval(-365 * 24 * 60 * 60)
        default:
            return matchesRelativeDayFilter(lowered, date: date, now: now)
        }
    }

    private func matchesRelativeDayFilter(_ value: String, date: Date, now: Date) -> Bool {
        guard value.hasSuffix("d"),
              let days = Int(value.dropLast()),
              days > 0
        else {
            return false
        }

        return date >= now.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
    }

    private static func tokenize(_ rawQuery: String) -> [String] {
        rawQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
