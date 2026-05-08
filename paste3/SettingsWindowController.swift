//
//  SettingsWindowController.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.contentViewController = NSHostingController(
            rootView: SettingsView()
                .modelContainer(Paste3ModelContainer.shared)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "paste3 Settings"
        window.isReleasedWhenClosed = false
        return window
    }
}
#endif
