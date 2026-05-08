//
//  ClipboardWriter.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
#if os(macOS)
import AppKit
#endif

enum ClipboardWriter {
    @MainActor
    static func copyBack(_ text: String) {
#if os(macOS)
        importToPasteboard(text)
#endif
    }

    @MainActor
    static func copyBack(_ item: ClipboardItem) {
#if os(macOS)
        importToPasteboard(item)
#endif
    }

#if os(macOS)
    @MainActor
    private static func importToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @MainActor
    private static func importToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .image:
            if let payloadType = item.payloadType, let payloadData = item.payloadData {
                pasteboard.setData(payloadData, forType: NSPasteboard.PasteboardType(payloadType))
            } else {
                pasteboard.setString(item.text, forType: .string)
            }
        case .file:
            let urls = item.text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { URL(fileURLWithPath: String($0)) }
            pasteboard.writeObjects(urls as [NSURL])
        case .richText, .html, .data:
            if let payloadType = item.payloadType, let payloadData = item.payloadData {
                pasteboard.setData(payloadData, forType: NSPasteboard.PasteboardType(payloadType))
            }
            if item.kind != .data {
                pasteboard.setString(item.text, forType: .string)
            }
        case .text, .url, .command:
            pasteboard.setString(item.text, forType: .string)
        }
    }
#endif
}
