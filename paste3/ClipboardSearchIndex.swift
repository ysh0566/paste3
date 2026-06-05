//
//  ClipboardSearchIndex.swift
//  Paste3
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ClipboardSearchIndex {
    static let shared = ClipboardSearchIndex()

    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL = ClipboardSearchIndex.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    static func temporaryForTests() -> ClipboardSearchIndex {
        ClipboardSearchIndex(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("paste3-search-index-tests-\(UUID().uuidString).sqlite", isDirectory: false)
        )
    }

    nonisolated static func canSearch(primaryTerm: String) -> Bool {
        normalizedFTSTerm(primaryTerm) != nil
    }

    func upsert(_ item: ClipboardItem) throws {
        try delete(itemID: item.id)
        try insertIndexEntry(for: item)
    }

    func delete(itemID: UUID) throws {
        try withStatement("DELETE FROM clipboard_search WHERE item_id = ?;") { statement in
            bind(itemID.uuidString, to: 1, in: statement)
            try stepDone(statement)
        }
    }

    func searchIDs(primaryTerm: String, limit: Int, offset: Int) throws -> [UUID] {
        guard let term = Self.normalizedFTSTerm(primaryTerm), limit > 0 else {
            return []
        }

        let matchQuery = "\(term)*"
        return try withStatement("SELECT item_id FROM clipboard_search WHERE clipboard_search MATCH ? LIMIT ? OFFSET ?;") { statement in
            bind(matchQuery, to: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(limit))
            sqlite3_bind_int(statement, 3, Int32(max(offset, 0)))

            var ids: [UUID] = []
            while true {
                let result = sqlite3_step(statement)
                switch result {
                case SQLITE_ROW:
                    guard let text = sqlite3_column_text(statement, 0) else {
                        continue
                    }
                    if let id = UUID(uuidString: String(cString: text)) {
                        ids.append(id)
                    }
                case SQLITE_DONE:
                    return ids
                default:
                    throw error("Failed to search clipboard index", result: result)
                }
            }
        }
    }

    func rebuild(from items: [ClipboardItem]) throws {
        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            try execute("DELETE FROM clipboard_search;")
            for item in items {
                try insertIndexEntry(for: item)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func openDatabaseIfNeeded() throws -> OpaquePointer {
        if let database {
            return database
        }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil) == SQLITE_OK, let openedDatabase else {
            throw error("Failed to open clipboard search index", database: openedDatabase)
        }

        database = openedDatabase
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_search
        USING fts5(item_id UNINDEXED, search_text, tokenize = 'unicode61');
        """)
        return openedDatabase
    }

    private func execute(_ sql: String) throws {
        let database = try openDatabaseIfNeeded()
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw error("Failed to execute clipboard search index statement", database: database)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        let database = try openDatabaseIfNeeded()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw error("Failed to prepare clipboard search index statement", database: database)
        }
        defer {
            sqlite3_finalize(statement)
        }

        return try body(statement)
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func insertIndexEntry(for item: ClipboardItem) throws {
        try withStatement("INSERT INTO clipboard_search(item_id, search_text) VALUES(?, ?);") { statement in
            bind(item.id.uuidString, to: 1, in: statement)
            bind(item.searchText, to: 2, in: statement)
            try stepDone(statement)
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw error("Failed to write clipboard search index", result: result)
        }
    }

    private func error(_ message: String, database: OpaquePointer? = nil, result: Int32? = nil) -> NSError {
        let database = database ?? self.database
        let detail = database.flatMap { sqlite3_errmsg($0).map(String.init(cString:)) } ?? result.map(String.init(describing:)) ?? "unknown"
        let code = result ?? database.map(sqlite3_errcode) ?? -1
        return NSError(
            domain: "ClipboardSearchIndex",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(message): \(detail)"]
        )
    }

    private nonisolated static func normalizedFTSTerm(_ term: String) -> String? {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        let allowed = CharacterSet.alphanumerics
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }

        return normalized
    }

    private nonisolated static func defaultDatabaseURL() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("paste3-search-index-\(ProcessInfo.processInfo.globallyUniqueString).sqlite", isDirectory: false)
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Paste3", isDirectory: true)
            .appendingPathComponent("clipboard-search.sqlite", isDirectory: false)
    }
}
