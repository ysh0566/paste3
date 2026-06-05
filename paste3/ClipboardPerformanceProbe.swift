//
//  ClipboardPerformanceProbe.swift
//  Paste3
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import OSLog

enum ClipboardPerformanceProbe {
    private static let logger = Logger(subsystem: "top.ysh0566.paste3", category: "performance")

    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        do {
            let result = try operation()
            let duration = start.duration(to: .now)
            logger.debug("\(name, privacy: .public) completed in \(String(describing: duration), privacy: .public)")
            return result
        } catch {
            let duration = start.duration(to: .now)
            logger.error("\(name, privacy: .public) failed in \(String(describing: duration), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    static func measure<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        do {
            let result = try await operation()
            let duration = start.duration(to: .now)
            logger.debug("\(name, privacy: .public) completed in \(String(describing: duration), privacy: .public)")
            return result
        } catch {
            let duration = start.duration(to: .now)
            logger.error("\(name, privacy: .public) failed in \(String(describing: duration), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
