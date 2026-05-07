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

    func applicationDidFinishLaunching(_ notification: Notification) {
        startClipboardMonitorIfNeeded()
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
}
#endif
