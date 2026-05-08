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
    private static let minimumPanelSize = CGSize(width: 760, height: 358)
    private static let maximumPanelHeight: CGFloat = 380
    private static let pasteKeyVirtualCode: CGKeyCode = 0x09

    private var panel: NSPanel?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var outsideClickMonitoringTask: Task<Void, Never>?
    private var pasteTargetApplication: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        rememberPasteTargetApplication()
        let panel = panel ?? makePanel()
        self.panel = panel
        installRootView(in: panel)
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

        return panel
    }

    private func installRootView(in panel: NSPanel) {
        // Rebuilding the SwiftUI root on each open resets transient selection/search
        // state, so history consistently starts on the newest card.
        let rootView = ContentView(
            displayMode: .floatingPanel,
            onDismiss: { [weak self] in
                self?.hide()
            },
            onPasteRequest: { [weak self] in
                self?.pasteToTargetApplication()
            }
        )
        .modelContainer(Paste3ModelContainer.shared)

        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    private func rememberPasteTargetApplication() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            pasteTargetApplication = nil
        } else {
            pasteTargetApplication = frontmostApplication
        }
    }

    private func pasteToTargetApplication() {
        let targetApplication = pasteTargetApplication
        pasteTargetApplication = nil
        hide()

        Task { @MainActor in
            targetApplication?.activate()
            try? await Task.sleep(nanoseconds: 80_000_000)
            Self.postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
        guard AccessibilityPermission.isTrusted,
              let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyVirtualCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyVirtualCode, keyDown: false) else {
            return
        }

        // Cmd+V is intentionally synthesized only after the panel closes and the
        // original app is active, matching the user's keyboard-only paste flow.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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
