//
//  ClipboardClassifier.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import CryptoKit
import Foundation

struct ClipboardSource: Equatable {
    var appName: String?
    var bundleIdentifier: String?
}

struct ClipboardItemCandidate: Equatable {
    var kind: ClipboardKind
    var text: String
    var searchText: String
    var source: ClipboardSource
    var contentHash: String
    var byteSize: Int
}

enum ClipboardClassifier {
    static let maxStoredTextLength = 200_000
    static let maxSearchTextLength = 8_000

    static func candidate(from rawText: String, source: ClipboardSource) -> ClipboardItemCandidate? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let storedText = String(rawText.prefix(maxStoredTextLength))
        let normalizedForClassification = normalizeForClassification(storedText)
        guard !normalizedForClassification.isEmpty else {
            return nil
        }

        let kind = classify(normalizedText: normalizedForClassification, originalText: storedText)
        let searchText = buildSearchText(text: storedText, kind: kind, source: source)

        return ClipboardItemCandidate(
            kind: kind,
            text: storedText,
            searchText: searchText,
            source: source,
            contentHash: hash(text: storedText, source: source),
            byteSize: storedText.utf8.count
        )
    }

    static func normalizeForClassification(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func classify(normalizedText: String, originalText: String) -> ClipboardKind {
        if isURL(normalizedText) {
            return .url
        }

        if isCommandLike(normalizedText) {
            return .command
        }

        return .text
    }

    static func buildSearchText(text: String, kind: ClipboardKind, source: ClipboardSource) -> String {
        let parts = [
            text,
            kind.rawValue,
            source.appName,
            source.bundleIdentifier,
        ]

        return String(parts.compactMap { $0 }.joined(separator: " ").lowercased().prefix(maxSearchTextLength))
    }

    static func matches(_ item: ClipboardItem, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return item.searchText.localizedCaseInsensitiveContains(normalizedQuery)
    }

    private static func isURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace) else {
            return false
        }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return true
        }

        return text.hasPrefix("www.") && text.contains(".")
    }

    private static func isCommandLike(_ text: String) -> Bool {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
        let lowered = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let commandPrefixes = [
            "git ", "swift ", "xcodebuild ", "npm ", "pnpm ", "yarn ", "bun ",
            "cargo ", "go ", "docker ", "kubectl ", "curl ", "ssh ", "make ",
            "python ", "python3 ", "uv ", "brew ", "sed ", "rg ", "grep ",
        ]

        if commandPrefixes.contains(where: { lowered == String($0.dropLast()) || lowered.hasPrefix($0) }) {
            return true
        }

        let declarationSignals = ["func ", "class ", "struct ", "enum ", "import "]
        if declarationSignals.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }

        let codeSignals = ["let ", "var ", "{", "}", "=>"]
        return text.contains("\n") && codeSignals.contains(where: { text.contains($0) })
    }

    private static func hash(text: String, source: ClipboardSource) -> String {
        let appName = normalizeSourceComponent(source.appName)
        let bundleIdentifier = normalizeSourceComponent(source.bundleIdentifier)
        // Source is part of identity: identical text copied from different apps should stay separate.
        let input = [
            hashField("text", text),
            hashField("sourceAppName", appName),
            hashField("sourceBundleIdentifier", bundleIdentifier),
        ].joined()

        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeSourceComponent(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func hashField(_ name: String, _ value: String) -> String {
        "\(name):\(value.utf8.count):\(value)\n"
    }
}
