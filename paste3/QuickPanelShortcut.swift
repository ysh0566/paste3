//
//  QuickPanelShortcut.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

#if os(macOS)
import AppKit
import Carbon
import Foundation

struct QuickPanelShortcut: Equatable, Identifiable {
    let id: String
    let menuTitle: String
    let displayName: String
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let carbonKeyCode: UInt32
    let carbonModifierFlags: UInt32

    static let commandShiftV = QuickPanelShortcut(
        id: "command-shift-v",
        menuTitle: "Command + Shift + V",
        displayName: "⌘⇧V",
        keyEquivalent: "v",
        keyEquivalentModifierMask: [.command, .shift],
        carbonKeyCode: 0x09,
        carbonModifierFlags: UInt32(cmdKey | shiftKey)
    )

    static let commandOptionV = QuickPanelShortcut(
        id: "command-option-v",
        menuTitle: "Command + Option + V",
        displayName: "⌘⌥V",
        keyEquivalent: "v",
        keyEquivalentModifierMask: [.command, .option],
        carbonKeyCode: 0x09,
        carbonModifierFlags: UInt32(cmdKey | optionKey)
    )

    static let controlOptionV = QuickPanelShortcut(
        id: "control-option-v",
        menuTitle: "Control + Option + V",
        displayName: "⌃⌥V",
        keyEquivalent: "v",
        keyEquivalentModifierMask: [.control, .option],
        carbonKeyCode: 0x09,
        carbonModifierFlags: UInt32(controlKey | optionKey)
    )

    static let controlShiftV = QuickPanelShortcut(
        id: "control-shift-v",
        menuTitle: "Control + Shift + V",
        displayName: "⌃⇧V",
        keyEquivalent: "v",
        keyEquivalentModifierMask: [.control, .shift],
        carbonKeyCode: 0x09,
        carbonModifierFlags: UInt32(controlKey | shiftKey)
    )

    static let all: [QuickPanelShortcut] = [
        .commandShiftV,
        .commandOptionV,
        .controlOptionV,
        .controlShiftV
    ]

    static let defaultShortcut = commandShiftV

    static func find(id: String) -> QuickPanelShortcut {
        all.first { $0.id == id } ?? defaultShortcut
    }
}

@MainActor
final class QuickPanelShortcutPreference {
    static let shared = QuickPanelShortcutPreference()

    private static let storageKey = "quickPanelShortcutID"

    private let defaults: UserDefaults
    private(set) var shortcut: QuickPanelShortcut
    var onChange: ((QuickPanelShortcut) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = QuickPanelShortcut.find(id: defaults.string(forKey: Self.storageKey) ?? "")
    }

    func setShortcut(_ shortcut: QuickPanelShortcut) {
        guard self.shortcut != shortcut else {
            return
        }

        self.shortcut = shortcut
        defaults.set(shortcut.id, forKey: Self.storageKey)
        onChange?(shortcut)
    }
}
#endif
