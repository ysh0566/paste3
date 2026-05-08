//
//  QuickPanelHotKeyRegistrar.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

#if os(macOS)
import Carbon
import Foundation

@MainActor
final class QuickPanelHotKeyRegistrar {
    private static let hotKeySignature: OSType = 0x50335348 // "P3SH"
    private static let hotKeyID = UInt32(1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func start(shortcut: QuickPanelShortcut) {
        installEventHandlerIfNeeded()
        register(shortcut)
    }

    func update(shortcut: QuickPanelShortcut) {
        unregisterHotKey()
        register(shortcut)
    }

    func stop() {
        unregisterHotKey()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
            assertionFailure("Failed to install quick panel hot key handler: \(status)")
        }
    }

    private func register(_ shortcut: QuickPanelShortcut) {
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )
        let status = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            assertionFailure("Failed to register quick panel hot key \(shortcut.displayName): \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotKey() {
        action()
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return noErr
        }

        let registrar = Unmanaged<QuickPanelHotKeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()

        Task { @MainActor in
            registrar.handleHotKey()
        }

        return noErr
    }
}
#endif
