//
//  ClipboardPasteboardSnapshot.swift
//  Paste3
//
//  Created by Codex on 2026/6/5.
//

import Foundation

#if os(macOS)
import AppKit

enum ClipboardPasteboardSnapshot: Sendable, Equatable {
    case file(paths: [String])
    case payload(kind: ClipboardKind, text: String, payloadData: Data, payloadType: String)
    case text(String)
    case genericData(payloadData: Data, payloadType: String)

    @MainActor
    static func capture(from pasteboard: NSPasteboard) -> ClipboardPasteboardSnapshot? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty {
            return .file(paths: urls.map(\.path))
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
                return .payload(
                    kind: .image,
                    text: ClipboardClassifier.imageSummary(type: type, byteSize: data.count),
                    payloadData: data,
                    payloadType: type.rawValue
                )
            }
        }

        if let data = pasteboard.data(forType: .html), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
            let plainText = pasteboard.string(forType: .string)
            let htmlText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? "HTML Content"
            return .payload(
                kind: .html,
                text: plainText?.isEmpty == false ? plainText! : htmlText,
                payloadData: data,
                payloadType: NSPasteboard.PasteboardType.html.rawValue
            )
        }

        if let data = pasteboard.data(forType: .rtf), data.count <= ClipboardClassifier.maxStoredPayloadBytes {
            let plainText = pasteboard.string(forType: .string)
            return .payload(
                kind: .richText,
                text: plainText?.isEmpty == false ? plainText! : "Rich Text Content",
                payloadData: data,
                payloadType: NSPasteboard.PasteboardType.rtf.rawValue
            )
        }

        if let text = pasteboard.string(forType: .string) {
            return .text(text)
        }

        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            for type in pasteboardItem.types where ClipboardClassifier.shouldStoreGenericData(type) {
                guard let data = pasteboardItem.data(forType: type), !data.isEmpty, data.count <= ClipboardClassifier.maxStoredPayloadBytes else {
                    continue
                }
                return .genericData(payloadData: data, payloadType: type.rawValue)
            }
        }

        return nil
    }
}
#endif
