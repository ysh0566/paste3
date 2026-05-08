//
//  AccessibilityPermission.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

#if os(macOS)
import ApplicationServices
import AppKit
import Foundation

enum AccessibilityPermission {
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPrompt() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func requestPromptAndOpenSettingsIfNeeded() {
        guard !isTrusted else {
            return
        }

        requestPrompt()

        // 系统可能抑制重复的授权弹窗；先给 AX prompt 一点时间，再兜底引导用户手动开启。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !isTrusted else {
                return
            }

            showManualGrantPrompt()
        }
    }

    @MainActor
    private static func showManualGrantPrompt() {
        let alert = NSAlert()
        alert.messageText = "paste3 需要辅助功能权限"
        alert.informativeText = "请在系统设置的辅助功能列表中开启 paste3，用于在选中剪贴板历史后自动粘贴到当前应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        NSApp.activate()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        if let accessibilitySettingsURL {
            NSWorkspace.shared.open(accessibilitySettingsURL)
        }
    }
}
#endif
