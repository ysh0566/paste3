//
//  PinboardStore.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

import Foundation
import SwiftData

@MainActor
final class PinboardStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func createPinboard(existingCount: Int) throws -> Pinboard {
        let color = PinboardColor.allCases[existingCount % PinboardColor.allCases.count]
        let pinboard = Pinboard(color: color, sortOrder: existingCount)
        modelContext.insert(pinboard)
        try modelContext.save()
        return pinboard
    }

    func rename(_ pinboard: Pinboard, to rawName: String) throws {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        pinboard.name = trimmedName.isEmpty ? "未命名" : trimmedName
        pinboard.updatedAt = Date()
        try modelContext.save()
    }

    func setColor(_ color: PinboardColor, for pinboard: Pinboard) throws {
        pinboard.colorRawValue = color.rawValue
        pinboard.updatedAt = Date()
        try modelContext.save()
    }

    func swap(_ lhs: Pinboard, with rhs: Pinboard, in orderedPinboards: [Pinboard]) throws {
        guard lhs.id != rhs.id,
              let lhsIndex = orderedPinboards.firstIndex(where: { $0.id == lhs.id }),
              let rhsIndex = orderedPinboards.firstIndex(where: { $0.id == rhs.id })
        else {
            return
        }

        var reorderedPinboards = orderedPinboards
        reorderedPinboards.swapAt(lhsIndex, rhsIndex)
        let updatedAt = Date()

        for (index, pinboard) in reorderedPinboards.enumerated() {
            pinboard.sortOrder = index
            pinboard.updatedAt = updatedAt
        }

        try modelContext.save()
    }

    func delete(_ pinboard: Pinboard) throws {
        let pins = try pins(for: pinboard.id)
        for pin in pins {
            modelContext.delete(pin)
        }

        modelContext.delete(pinboard)
        try modelContext.save()
    }

    @discardableResult
    func pin(_ item: ClipboardItem, to pinboard: Pinboard) throws -> Bool {
        if try existingPin(itemID: item.id, pinboardID: pinboard.id) != nil {
            return false
        }

        modelContext.insert(PinnedClipboardItem(pinboardID: pinboard.id, clipboardItemID: item.id))
        pinboard.updatedAt = Date()
        try modelContext.save()
        return true
    }

    func unpin(_ item: ClipboardItem, from pinboard: Pinboard) throws {
        guard let pin = try existingPin(itemID: item.id, pinboardID: pinboard.id) else {
            return
        }

        modelContext.delete(pin)
        pinboard.updatedAt = Date()
        try modelContext.save()
    }

    private func existingPin(itemID: UUID, pinboardID: UUID) throws -> PinnedClipboardItem? {
        var descriptor = FetchDescriptor<PinnedClipboardItem>(
            predicate: #Predicate { pin in
                pin.clipboardItemID == itemID && pin.pinboardID == pinboardID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func pins(for pinboardID: UUID) throws -> [PinnedClipboardItem] {
        let descriptor = FetchDescriptor<PinnedClipboardItem>(
            predicate: #Predicate { pin in
                pin.pinboardID == pinboardID
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
