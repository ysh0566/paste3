//
//  Paste3AppDelegate.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/5/7.
//

#if os(macOS)
import AppKit
import SwiftData

@MainActor
final class Paste3AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: ClipboardMonitor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep paste3 as a menu bar utility even when launched from Xcode or a stale bundle.
        NSApp.setActivationPolicy(.accessory)
        startClipboardMonitorIfNeeded()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    private func startClipboardMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        // Monitoring is app-scoped so clipboard capture continues even when the history window is closed.
        let monitor = ClipboardMonitor(modelContext: Paste3ModelContainer.shared.mainContext)
        monitor.start()
        self.monitor = monitor
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "paste3")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            QuickPanelController.shared.toggle()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showStatusMenu()
        default:
            QuickPanelController.shared.toggle()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else {
            return
        }

        // AppKit only tracks a status item menu when it is assigned to the item.
        // Clear it after the synchronous click so left-click remains a panel toggle.
        statusItem.menu = makeStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(
            withTitle: "Clear History",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        settingsMenu.items.last?.target = self
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit paste3", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func clearHistory() {
        do {
            try ClipboardStore(modelContext: Paste3ModelContainer.shared.mainContext).deleteAll()
        } catch {
            assertionFailure("Failed to clear clipboard history: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif
