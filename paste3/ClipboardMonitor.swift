//
//  ClipboardMonitor.swift
//  Paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
import SwiftData

#if os(macOS)
import AppKit

@MainActor
final class ClipboardMonitor {
    private let modelContext: ModelContext
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var lastChangeCount: Int

    init(modelContext: ModelContext, pollInterval: TimeInterval = 0.75) {
        self.modelContext = modelContext
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                try? self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
    }

    func poll() throws {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        let source = currentSource()
        if !ClipboardCapturePreference.shared.shouldCapture(
            source: source,
            appBundleIdentifier: Bundle.main.bundleIdentifier
        ) {
            return
        }

        guard let snapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard) else {
            return
        }

        captureTask?.cancel()
        captureTask = Task { @MainActor [modelContext] in
            guard let candidate = await ClipboardPerformanceProbe.measure("clipboard.candidate", {
                await ClipboardClassifier.candidate(from: snapshot, source: source)
            }) else {
                return
            }

            do {
                try ClipboardPerformanceProbe.measure("clipboard.insert") {
                    try ClipboardStore(modelContext: modelContext).insert(candidate)
                }
            } catch {
                assertionFailure("Failed to insert clipboard candidate: \(error)")
            }
        }
    }

    private func currentSource() -> ClipboardSource {
        let app = NSWorkspace.shared.frontmostApplication
        return ClipboardSource(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier
        )
    }
}
#endif
