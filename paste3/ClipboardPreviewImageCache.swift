//
//  ClipboardPreviewImageCache.swift
//  Paste3
//
//  Created by Codex on 2026/6/5.
//

import Foundation

#if os(macOS)
import AppKit
import Combine

@MainActor
final class ClipboardPreviewImageCache: ObservableObject {
    static let shared = ClipboardPreviewImageCache()

    private var imagesByKey: [String: NSImage] = [:]

    func image(for item: ClipboardItem) -> NSImage? {
        image(for: item, payloadStore: .shared)
    }

    func image(for item: ClipboardItem, payloadStore: ClipboardPayloadStore) -> NSImage? {
        guard item.kind == .image else {
            return nil
        }

        let key = cacheKey(for: item)
        if let image = imagesByKey[key] {
            return image
        }

        let data: Data?
        if let payloadData = item.payloadData {
            data = payloadData
        } else if let payloadFileName = item.payloadFileName {
            data = try? payloadStore.read(fileName: payloadFileName)
        } else {
            data = nil
        }

        guard let data, let image = NSImage(data: data) else {
            return nil
        }

        let thumbnail = image.resizedToFit(maxSide: 512)
        imagesByKey[key] = thumbnail
        return thumbnail
    }

    func removeImage(for item: ClipboardItem) {
        imagesByKey.removeValue(forKey: cacheKey(for: item))
    }

    private func cacheKey(for item: ClipboardItem) -> String {
        item.payloadFileName ?? item.id.uuidString
    }
}

private extension NSImage {
    func resizedToFit(maxSide: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxSide else {
            return self
        }

        let scale = maxSide / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        return thumbnail
    }
}
#endif
