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
#if os(macOS)
import AppKit
#endif

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
        let store = ClipboardStore(
            modelContext: context,
            retentionPeriod: ClipboardRetentionPeriod.find(id: "forever")
        )
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

    @Test func storePersistsPayloadData() throws {
        let context = try makeContext()
        let store = ClipboardStore(modelContext: context)
        let payload = Data([0x01, 0x02, 0x03])
        let candidate = try #require(ClipboardClassifier.candidate(
            kind: .data,
            text: "public.test-data, 3 bytes",
            payloadData: payload,
            payloadType: "public.test-data",
            source: ClipboardSource(appName: "Test", bundleIdentifier: "test.app")
        ))

        let item = try #require(try store.insert(candidate))

        #expect(item.kind == .data)
        #expect(item.payloadData == payload)
        #expect(item.payloadType == "public.test-data")
    }

    @Test func classifierRejectsOversizedPayload() {
        let payload = Data(repeating: 0, count: ClipboardClassifier.maxStoredPayloadBytes + 1)
        let candidate = ClipboardClassifier.candidate(
            kind: .data,
            text: "oversized",
            payloadData: payload,
            payloadType: "public.test-data",
            source: ClipboardSource(appName: "Test", bundleIdentifier: "test.app")
        )

        #expect(candidate == nil)
    }

#if os(macOS)
    @Test func classifierCapturesHTMLPasteboardData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paste3Tests.html.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)
        pasteboard.setData(Data("<b>Hello</b>".utf8), forType: .html)

        let candidate = try #require(ClipboardClassifier.candidate(
            from: pasteboard,
            source: ClipboardSource(appName: "Safari", bundleIdentifier: "com.apple.Safari")
        ))

        #expect(candidate.kind == .html)
        #expect(candidate.text == "Hello")
        #expect(candidate.payloadType == NSPasteboard.PasteboardType.html.rawValue)
        #expect(candidate.payloadData == Data("<b>Hello</b>".utf8))
    }

    @Test func classifierCapturesGenericPasteboardData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paste3Tests.data.\(UUID().uuidString)"))
        let payloadType = NSPasteboard.PasteboardType("com.example.custom")
        let payload = Data([0x0A, 0x0B])
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: payloadType)

        let candidate = try #require(ClipboardClassifier.candidate(
            from: pasteboard,
            source: ClipboardSource(appName: "Custom", bundleIdentifier: "custom.app")
        ))

        #expect(candidate.kind == .data)
        #expect(candidate.payloadType == payloadType.rawValue)
        #expect(candidate.payloadData == payload)
    }

    @Test func quickPanelShortcutFallsBackToCommandShiftV() {
        #expect(QuickPanelShortcut.find(id: "missing") == .commandShiftV)
        #expect(QuickPanelShortcut.defaultShortcut.displayName == "⌘⇧V")
    }

    @Test func quickPanelShortcutPreferencePersistsSelection() throws {
        let suiteName = "paste3Tests.shortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preference = QuickPanelShortcutPreference(defaults: defaults)
        #expect(preference.shortcut == .commandShiftV)

        preference.setShortcut(.commandOptionV)

        let reloadedPreference = QuickPanelShortcutPreference(defaults: defaults)
        #expect(reloadedPreference.shortcut == .commandOptionV)
    }
#endif

    @Test func clipboardRetentionPreferencePersistsSelection() throws {
        let suiteName = "paste3Tests.retention.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preference = ClipboardRetentionPreference(defaults: defaults)
        #expect(preference.period == .defaultPeriod)

        let threeMonths = ClipboardRetentionPeriod.find(id: "month-3")
        preference.setPeriod(threeMonths)

        let reloadedPreference = ClipboardRetentionPreference(defaults: defaults)
        #expect(reloadedPreference.period == threeMonths)
    }

    @Test func storePrunesItemsOlderThanRetentionPeriod() throws {
        let now = Date()
        let context = try makeContext()
        let store = ClipboardStore(
            modelContext: context,
            retentionPeriod: ClipboardRetentionPeriod.find(id: "day-1"),
            referenceDateProvider: { now }
        )

        let oldCandidate = try #require(ClipboardClassifier.candidate(
            from: "old clip",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ))
        let oldItem = try #require(try store.insert(oldCandidate))
        oldItem.createdAt = now.addingTimeInterval(-2 * 24 * 60 * 60)
        try context.save()

        let freshCandidate = try #require(ClipboardClassifier.candidate(
            from: "fresh clip",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ))
        try store.insert(freshCandidate)

        let allItems = try store.items()
        #expect(allItems.map(\.text) == ["fresh clip"])
    }

    @Test func storeKeepsOldItemsForever() throws {
        let now = Date()
        let context = try makeContext()
        let store = ClipboardStore(
            modelContext: context,
            retentionPeriod: ClipboardRetentionPeriod.find(id: "forever"),
            referenceDateProvider: { now }
        )

        let candidate = try #require(ClipboardClassifier.candidate(
            from: "old but kept",
            source: ClipboardSource(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ))
        let item = try #require(try store.insert(candidate))
        item.createdAt = now.addingTimeInterval(-400 * 24 * 60 * 60)
        try context.save()

        try store.pruneExpiredItemsIfNeeded()

        let allItems = try store.items()
        #expect(allItems.map(\.text) == ["old but kept"])
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClipboardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
