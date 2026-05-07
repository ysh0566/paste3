//
//  ClipboardMonitor.swift
//  paste3
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
    }

    func poll() throws {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        let source = currentSource()
        // Copy-back happens while paste3 is frontmost. Skipping self-captures prevents a loop.
        if source.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        guard let candidate = ClipboardClassifier.candidate(from: text, source: source) else {
            return
        }

        try ClipboardStore(modelContext: modelContext).insert(candidate)
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
