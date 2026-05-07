//
//  QuickPanelController.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/5/7.
//

#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 320),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "paste3"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = QuickPanelView(onDismiss: { [weak self] in
            self?.hide()
        })
        .modelContainer(Paste3ModelContainer.shared)

        panel.contentViewController = NSHostingController(rootView: rootView)
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = min(920, max(420, visibleFrame.width - 80))
        let height: CGFloat = 320
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.minY + 28

        // Recompute the frame each time because the active display or Dock position can change.
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
