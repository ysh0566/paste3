//
//  MenuBarControls.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/5/7.
//

#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarControls: View {
    var body: some View {
        Button("Open History") {
            QuickPanelController.shared.toggle()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Divider()

        Button("Quit paste3") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
#endif
