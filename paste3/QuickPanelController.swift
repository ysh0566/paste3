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

    private static let screenHeightRatio: CGFloat = 0.28
    private static let horizontalScreenInset: CGFloat = 16
    private static let minimumPanelSize = CGSize(width: 760, height: 340)
    private static let maximumPanelHeight: CGFloat = 380

    private var panel: NSPanel?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var outsideClickMonitoringTask: Task<Void, Never>?

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
        scheduleOutsideClickMonitoring()
    }

    func hide() {
        outsideClickMonitoringTask?.cancel()
        outsideClickMonitoringTask = nil
        panel?.orderOut(nil)
        stopOutsideClickMonitoring()
    }

    private func makePanel() -> NSPanel {
        let panel = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 340),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "paste3"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = ContentView(displayMode: .floatingPanel, onDismiss: { [weak self] in
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
        let screenFrame = screen.frame
        let availableWidth = visibleFrame.width - Self.horizontalScreenInset * 2
        let width = min(visibleFrame.width, max(Self.minimumPanelSize.width, availableWidth))
        let height = min(
            Self.maximumPanelHeight,
            max(Self.minimumPanelSize.height, visibleFrame.height * Self.screenHeightRatio)
        )
        let x = visibleFrame.midX - width / 2
        let y = screenFrame.minY

        // Size from the visible frame, but anchor to the full screen bottom so the
        // panel touches the display edge instead of floating above the Dock.
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func scheduleOutsideClickMonitoring() {
        outsideClickMonitoringTask?.cancel()

        // Installing the event monitors on the next run loop avoids treating the
        // menu item click that opened the panel as an immediate outside click.
        outsideClickMonitoringTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, panel?.isVisible == true else {
                return
            }
            startOutsideClickMonitoring()
        }
    }

    private func startOutsideClickMonitoring() {
        guard localOutsideClickMonitor == nil, globalOutsideClickMonitor == nil else {
            return
        }

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.hideIfClickIsOutsidePanel(event)
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.hideIfClickIsOutsidePanel(event)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }

        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func hideIfClickIsOutsidePanel(_ event: NSEvent) {
        guard let panel, panel.isVisible else {
            stopOutsideClickMonitoring()
            return
        }

        if event.window === panel {
            return
        }

        if !panel.frame.contains(NSEvent.mouseLocation) {
            hide()
        }
    }
}

private final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
#endif
