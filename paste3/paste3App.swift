//
//  paste3App.swift
//  paste3
//
//  Created by 余生辉 on 2026/4/29.
//

import SwiftData
import SwiftUI

@main
struct paste3App: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(Paste3AppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
#if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(Paste3ModelContainer.shared)
        }
#else
        WindowGroup(id: Paste3WindowID.history) {
            ContentView()
        }
        .modelContainer(Paste3ModelContainer.shared)
#endif
    }
}
