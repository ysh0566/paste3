//
//  paste3Tests.swift
//  paste3Tests
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
import SwiftData
import Testing
@testable import paste3

@MainActor
struct paste3Tests {
    @Test func classifierIgnoresEmptyText() {
        let candidate = ClipboardClassifier.candidate(
            from: " \n\t ",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        )

        #expect(candidate == nil)
    }

    @Test func classifierDetectsURL() throws {
        let candidate = try #require(ClipboardClassifier.candidate(
            from: "https://developer.apple.com/documentation/appkit/nspasteboard",
            source: ClipboardSource(appName: "Safari", bundleIdentifier: "com.apple.Safari")
        ))

        #expect(candidate.kind == .url)
        #expect(candidate.searchText.contains("safari"))
        #expect(candidate.byteSize > 0)
    }

    @Test func classifierDetectsCommandAndPreservesText() throws {
        let text = "git rebase -i origin/main\nswift test --filter Clipboard"
        let candidate = try #require(ClipboardClassifier.candidate(
            from: text,
            source: ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        ))

        #expect(candidate.kind == .command)
        #expect(candidate.text == text)
        #expect(candidate.searchText.contains("terminal"))
    }

    @Test func classifierPreservesWhitespaceAndLineEndingsInHash() throws {
        let source = ClipboardSource(appName: nil, bundleIdentifier: nil)
        let first = try #require(ClipboardClassifier.candidate(from: "hello\n", source: source))
        let second = try #require(ClipboardClassifier.candidate(from: " hello\r\n", source: source))

        #expect(first.text == "hello\n")
        #expect(second.text == " hello\r\n")
        #expect(first.contentHash != second.contentHash)
    }

    @Test func classifierIncludesSourceInHash() throws {
        let xcode = ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        let terminal = ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let first = try #require(ClipboardClassifier.candidate(from: "git status", source: xcode))
        let second = try #require(ClipboardClassifier.candidate(from: "git status", source: terminal))

        #expect(first.contentHash != second.contentHash)
    }

    @Test func storeInsertsAndSearchesItems() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let candidate = try #require(ClipboardClassifier.candidate(
            from: "func loadClips() async throws { }",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ))

        let item = try #require(try store.insert(candidate))
        let matches = try store.items(matching: "loadclips")

        #expect(item.kind == .command)
        #expect(matches.map(\.id).contains(item.id))
    }

    @Test func storeDedupesByContentHash() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let source = ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let first = try #require(ClipboardClassifier.candidate(from: "git status", source: source))
        let second = try #require(ClipboardClassifier.candidate(from: "git status", source: source))

        let inserted = try #require(try store.insert(first))
        inserted.createdAt = Date(timeIntervalSince1970: 1)
        try context.save()
        let duplicate = try store.insert(second)
        let allItems = try store.items()

        #expect(duplicate == nil)
        #expect(allItems.count == 1)
        #expect(allItems[0].id == inserted.id)
        #expect(allItems[0].createdAt > Date(timeIntervalSince1970: 1))
    }

    @Test func storeKeepsWhitespaceAndLineEndingVariants() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let source = ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let first = try #require(ClipboardClassifier.candidate(from: "git status\n", source: source))
        let second = try #require(ClipboardClassifier.candidate(from: " git status\r\n", source: source))

        let firstItem = try store.insert(first)
        let secondItem = try store.insert(second)
        let allItems = try store.items()

        #expect(firstItem != nil)
        #expect(secondItem != nil)
        #expect(allItems.count == 2)
        #expect(allItems.map(\.text).contains("git status\n"))
        #expect(allItems.map(\.text).contains(" git status\r\n"))
    }

    @Test func storeTouchMovesItemToFront() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let source = ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let firstCandidate = try #require(ClipboardClassifier.candidate(from: "git status", source: source))
        let secondCandidate = try #require(ClipboardClassifier.candidate(from: "git diff", source: source))
        let first = try #require(try store.insert(firstCandidate))
        let second = try #require(try store.insert(secondCandidate))

        first.createdAt = Date(timeIntervalSince1970: 1)
        second.createdAt = Date(timeIntervalSince1970: 2)
        try context.save()
        try store.touch(first)

        let allItems = try store.items()
        #expect(allItems.map(\.id) == [first.id, second.id])
    }

    @Test func storeKeepsSameTextFromDifferentSources() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let xcode = try #require(ClipboardClassifier.candidate(
            from: "git status",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ))
        let terminal = try #require(ClipboardClassifier.candidate(
            from: "git status",
            source: ClipboardSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        ))

        let first = try store.insert(xcode)
        let second = try store.insert(terminal)
        let allItems = try store.items()

        #expect(first != nil)
        #expect(second != nil)
        #expect(allItems.count == 2)
    }

    @Test func storePrunesAboveLimit() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context, maxItems: 2)

        for index in 0..<3 {
            let candidate = try #require(ClipboardClassifier.candidate(
                from: "clip \(index)",
                source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
            ))
            try store.insert(candidate)
        }

        let allItems = try store.items()
        #expect(allItems.count == 2)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClipboardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
