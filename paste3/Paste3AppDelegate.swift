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
    private let shortcutPreference = QuickPanelShortcutPreference.shared
    private lazy var hotKeyRegistrar = QuickPanelHotKeyRegistrar { [weak self] in
        self?.toggleQuickPanel()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep paste3 as a menu bar utility even when launched from Xcode or a stale bundle.
        NSApp.setActivationPolicy(.accessory)
        startClipboardMonitorIfNeeded()
        startQuickPanelHotKey()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKeyRegistrar.stop()
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
        let statusItem = NSStatusBar.system.statusItem(withLength: 28)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            return
        }

        let statusImage = NSImage(named: NSImage.Name("StatusBarIcon")) ??
            NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "paste3")
        statusImage?.isTemplate = true
        statusImage?.size = NSSize(width: 22, height: 22)
        button.image = statusImage
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleQuickPanel()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showStatusMenu()
        default:
            toggleQuickPanel()
        }
    }

    private func startQuickPanelHotKey() {
        shortcutPreference.onChange = { [weak self] shortcut in
            self?.hotKeyRegistrar.update(shortcut: shortcut)
        }
        hotKeyRegistrar.start(shortcut: shortcutPreference.shortcut)
    }

    private func toggleQuickPanel() {
        QuickPanelController.shared.toggle()
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
        let currentShortcut = shortcutPreference.shortcut

        let quickPanelItem = NSMenuItem(
            title: "Quick Panel",
            action: #selector(showQuickPanel),
            keyEquivalent: currentShortcut.keyEquivalent
        )
        quickPanelItem.keyEquivalentModifierMask = currentShortcut.keyEquivalentModifierMask
        quickPanelItem.target = self
        menu.addItem(quickPanelItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit paste3", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showQuickPanel() {
        QuickPanelController.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif
