//
//  ClipboardItem.swift
//  paste3
//
//  Created by ysh0566@qq.com on 2026/4/29.
//

import Foundation
import SwiftData

enum ClipboardKind: String, CaseIterable, Identifiable {
    case text
    case url
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            "Text"
        case .url:
            "Link"
        case .command:
            "Command"
        }
    }
}

@Model
final class ClipboardItem {
    var id: UUID
    var createdAt: Date
    var kindRawValue: String
    var text: String
    var searchText: String
    var sourceAppName: String?
    var sourceBundleIdentifier: String?
    var contentHash: String
    var byteSize: Int

    var kind: ClipboardKind {
        ClipboardKind(rawValue: kindRawValue) ?? .text
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipboardKind,
        text: String,
        searchText: String,
        sourceAppName: String?,
        sourceBundleIdentifier: String?,
        contentHash: String,
        byteSize: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRawValue = kind.rawValue
        self.text = text
        self.searchText = searchText
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.contentHash = contentHash
        self.byteSize = byteSize
    }
}
