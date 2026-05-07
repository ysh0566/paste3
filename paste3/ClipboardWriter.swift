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

#if os(macOS)
    @MainActor
    private static func importToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
#endif
}
