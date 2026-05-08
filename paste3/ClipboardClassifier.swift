//
//  ClipboardClassifier.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import CryptoKit
import Foundation

#if os(macOS)
import AppKit
#endif

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
    var payloadData: Data?
    var payloadType: String?
}

enum ClipboardClassifier {
    static let maxStoredTextLength = 200_000
    static let maxSearchTextLength = 8_000
    static let maxStoredPayloadBytes = 20 * 1_024 * 1_024

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
            byteSize: storedText.utf8.count,
            payloadData: nil,
            payloadType: nil
        )
    }

    static func candidate(
        kind: ClipboardKind,
        text: String,
        payloadData: Data?,
        payloadType: String?,
        source: ClipboardSource
    ) -> ClipboardItemCandidate? {
        let storedText = String(text.prefix(maxStoredTextLength))
        guard !storedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let payloadData, payloadData.count > maxStoredPayloadBytes {
            return nil
        }

        let byteSize = payloadData?.count ?? storedText.utf8.count
        let searchText = buildSearchText(text: storedText, kind: kind, source: source)
        return ClipboardItemCandidate(
            kind: kind,
            text: storedText,
            searchText: searchText,
            source: source,
            contentHash: hash(kind: kind, text: storedText, payloadData: payloadData, payloadType: payloadType, source: source),
            byteSize: byteSize,
            payloadData: payloadData,
            payloadType: payloadType
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
        hash(kind: nil, text: text, payloadData: nil, payloadType: nil, source: source)
    }

    private static func hash(
        kind: ClipboardKind?,
        text: String,
        payloadData: Data?,
        payloadType: String?,
        source: ClipboardSource
    ) -> String {
        let appName = normalizeSourceComponent(source.appName)
        let bundleIdentifier = normalizeSourceComponent(source.bundleIdentifier)
        // Source is part of identity: identical text copied from different apps should stay separate.
        let input = [
            hashField("kind", kind?.rawValue ?? "text"),
            hashField("text", text),
            hashField("payloadType", payloadType ?? ""),
            hashField("sourceAppName", appName),
            hashField("sourceBundleIdentifier", bundleIdentifier),
        ].joined()

        var hasher = SHA256()
        hasher.update(data: Data(input.utf8))
        if let payloadData {
            hasher.update(data: payloadData)
        }
        let digest = hasher.finalize()
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

#if os(macOS)
extension ClipboardClassifier {
    static func candidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        if let fileCandidate = fileCandidate(from: pasteboard, source: source) {
            return fileCandidate
        }

        if let imageCandidate = imageCandidate(from: pasteboard, source: source) {
            return imageCandidate
        }

        if let htmlCandidate = htmlCandidate(from: pasteboard, source: source) {
            return htmlCandidate
        }

        if let richTextCandidate = richTextCandidate(from: pasteboard, source: source) {
            return richTextCandidate
        }

        if let text = pasteboard.string(forType: .string) {
            return candidate(from: text, source: source)
        }

        return dataCandidate(from: pasteboard, source: source)
    }

    private static func fileCandidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        guard !urls.isEmpty else {
            return nil
        }

        let paths = urls.map(\.path)
        let summary = paths.joined(separator: "\n")
        return candidate(
            kind: .file,
            text: summary,
            payloadData: nil,
            payloadType: NSPasteboard.PasteboardType.fileURL.rawValue,
            source: source
        )
    }

    private static func imageCandidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in preferredTypes {
            if let data = pasteboard.data(forType: type), data.count <= maxStoredPayloadBytes {
                return candidate(
                    kind: .image,
                    text: imageSummary(type: type, byteSize: data.count),
                    payloadData: data,
                    payloadType: type.rawValue,
                    source: source
                )
            }
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let data = image.tiffRepresentation,
            data.count <= maxStoredPayloadBytes
        else {
            return nil
        }

        return candidate(
            kind: .image,
            text: imageSummary(type: .tiff, byteSize: data.count),
            payloadData: data,
            payloadType: NSPasteboard.PasteboardType.tiff.rawValue,
            source: source
        )
    }

    private static func htmlCandidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        guard let data = pasteboard.data(forType: .html), data.count <= maxStoredPayloadBytes else {
            return nil
        }

        let plainText = pasteboard.string(forType: .string)
        let htmlText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? "HTML Content"
        let summary = plainText?.isEmpty == false ? plainText! : htmlText
        return candidate(
            kind: .html,
            text: summary,
            payloadData: data,
            payloadType: NSPasteboard.PasteboardType.html.rawValue,
            source: source
        )
    }

    private static func richTextCandidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        guard let data = pasteboard.data(forType: .rtf), data.count <= maxStoredPayloadBytes else {
            return nil
        }

        let plainText = pasteboard.string(forType: .string)
        return candidate(
            kind: .richText,
            text: plainText?.isEmpty == false ? plainText! : "Rich Text Content",
            payloadData: data,
            payloadType: NSPasteboard.PasteboardType.rtf.rawValue,
            source: source
        )
    }

    private static func imageSummary(type: NSPasteboard.PasteboardType, byteSize: Int) -> String {
        let format = type == .png ? "PNG" : "TIFF"
        return "\(format) Image, \(byteSize) bytes"
    }

    private static func dataCandidate(from pasteboard: NSPasteboard, source: ClipboardSource) -> ClipboardItemCandidate? {
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            for type in pasteboardItem.types where shouldStoreGenericData(type) {
                guard let data = pasteboardItem.data(forType: type), !data.isEmpty, data.count <= maxStoredPayloadBytes else {
                    continue
                }

                return candidate(
                    kind: .data,
                    text: "\(type.rawValue), \(data.count) bytes",
                    payloadData: data,
                    payloadType: type.rawValue,
                    source: source
                )
            }
        }

        return nil
    }

    private static func shouldStoreGenericData(_ type: NSPasteboard.PasteboardType) -> Bool {
        let rawValue = type.rawValue
        let skippedTypes = [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.html.rawValue,
            NSPasteboard.PasteboardType.rtf.rawValue,
        ]

        return !skippedTypes.contains(rawValue) && !rawValue.hasPrefix("dyn.")
    }
}
#endif
