//
//  Pinboard.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

import Foundation
import SwiftData
import SwiftUI

enum PinboardColor: String, CaseIterable, Hashable, Identifiable {
    case red
    case orange
    case amber
    case green
    case blue
    case purple
    case pink
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red:
            "红色"
        case .orange:
            "橙色"
        case .amber:
            "黄色"
        case .green:
            "绿色"
        case .blue:
            "蓝色"
        case .purple:
            "紫色"
        case .pink:
            "粉色"
        case .gray:
            "灰色"
        }
    }

    var color: Color {
        switch self {
        case .red:
            Color(red: 1.0, green: 0.23, blue: 0.28)
        case .orange:
            Color(red: 1.0, green: 0.51, blue: 0.12)
        case .amber:
            Color(red: 0.96, green: 0.68, blue: 0.12)
        case .green:
            Color(red: 0.22, green: 0.68, blue: 0.34)
        case .blue:
            Color(red: 0.0, green: 0.48, blue: 1.0)
        case .purple:
            Color(red: 0.74, green: 0.22, blue: 0.86)
        case .pink:
            Color(red: 1.0, green: 0.12, blue: 0.34)
        case .gray:
            Color(red: 0.56, green: 0.57, blue: 0.61)
        }
    }
}

@Model
final class Pinboard {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var name: String
    var colorRawValue: String
    var sortOrder: Int = 0

    var colorKind: PinboardColor {
        PinboardColor(rawValue: colorRawValue) ?? .blue
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String = "未命名",
        color: PinboardColor = .blue,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.colorRawValue = color.rawValue
        self.sortOrder = sortOrder
    }
}

@Model
final class PinnedClipboardItem {
    var id: UUID
    var pinboardID: UUID
    var clipboardItemID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pinboardID: UUID,
        clipboardItemID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pinboardID = pinboardID
        self.clipboardItemID = clipboardItemID
        self.createdAt = createdAt
    }
}
