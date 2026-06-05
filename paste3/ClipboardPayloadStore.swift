//
//  ClipboardPayloadStore.swift
//  Paste3
//
//  Created by Codex on 2026/5/9.
//

import Foundation

final class ClipboardPayloadStore: Sendable {
    static let shared = ClipboardPayloadStore()

    let directoryURL: URL

    init(directoryURL: URL = ClipboardPayloadStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func write(_ data: Data, payloadType: String?) throws -> String {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileName = "\(UUID().uuidString).\(fileExtension(for: payloadType))"
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic])
        return fileName
    }

    func read(fileName: String) throws -> Data? {
        let fileURL = directoryURL.appendingPathComponent(safeFileName(fileName), isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try Data(contentsOf: fileURL)
    }

    func delete(fileName: String) throws {
        let fileURL = directoryURL.appendingPathComponent(safeFileName(fileName), isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    func deleteAllPayloads() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        for fileURL in fileURLs {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static func temporaryForTests() -> ClipboardPayloadStore {
        ClipboardPayloadStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("paste3-payload-tests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private nonisolated static func defaultDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Paste3", isDirectory: true)
            .appendingPathComponent("Payloads", isDirectory: true)
    }

    private func fileExtension(for payloadType: String?) -> String {
        guard let payloadType else {
            return "bin"
        }

        let lowered = payloadType.lowercased()
        if lowered.contains("png") {
            return "png"
        }
        if lowered.contains("tiff") || lowered.contains("tif") {
            return "tiff"
        }
        if lowered.contains("html") {
            return "html"
        }
        if lowered.contains("rtf") {
            return "rtf"
        }

        return "bin"
    }

    private func safeFileName(_ fileName: String) -> String {
        URL(fileURLWithPath: fileName).lastPathComponent
    }
}
