//
//  Paste3ModelContainer.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/5/7.
//

import SwiftData

enum Paste3ModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
            Pinboard.self,
            PinnedClipboardItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
