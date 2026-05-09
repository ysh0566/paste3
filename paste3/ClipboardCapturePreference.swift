//
//  ClipboardCapturePreference.swift
//  Paste3
//
//  Created by Codex on 2026/5/9.
//

#if os(macOS)
import AppKit
import Foundation

struct ClipboardCaptureExcludedApp: Codable, Equatable, Identifiable, Sendable {
    var bundleIdentifier: String
    var appName: String?

    var id: String { bundleIdentifier }

    var displayName: String {
        appName?.isEmpty == false ? appName! : bundleIdentifier
    }
}

@MainActor
final class ClipboardCapturePreference {
    static let shared = ClipboardCapturePreference()

    private static let pausedKey = "clipboardCapturePaused"
    private static let excludedAppsKey = "clipboardCaptureExcludedApps"

    private static let defaultExcludedApps = [
        ClipboardCaptureExcludedApp(bundleIdentifier: "com.1password.1password", appName: "1Password"),
        ClipboardCaptureExcludedApp(bundleIdentifier: "com.1password.1password7", appName: "1Password 7"),
        ClipboardCaptureExcludedApp(bundleIdentifier: "com.agilebits.onepassword7", appName: "1Password 7"),
        ClipboardCaptureExcludedApp(bundleIdentifier: "com.apple.keychainaccess", appName: "Keychain Access"),
        ClipboardCaptureExcludedApp(bundleIdentifier: "com.apple.Passwords", appName: "Passwords")
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seedDefaultExcludedAppsIfNeeded()
    }

    var isPaused: Bool {
        defaults.bool(forKey: Self.pausedKey)
    }

    var excludedApps: [ClipboardCaptureExcludedApp] {
        loadExcludedApps()
    }

    func setPaused(_ isPaused: Bool) {
        defaults.set(isPaused, forKey: Self.pausedKey)
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func shouldCapture(source: ClipboardSource, appBundleIdentifier: String?) -> Bool {
        guard !isPaused else {
            return false
        }

        if source.bundleIdentifier == appBundleIdentifier {
            return false
        }

        guard let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return true
        }

        return !excludedApps.contains { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    func exclude(source: ClipboardSource) {
        guard let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return
        }

        addExcludedApp(bundleIdentifier: bundleIdentifier, appName: source.appName)
    }

    func addExcludedApp(bundleIdentifier rawBundleIdentifier: String, appName: String? = nil) {
        let bundleIdentifier = rawBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            return
        }

        var apps = excludedApps
        if let index = apps.firstIndex(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            apps[index].appName = appName?.isEmpty == false ? appName : apps[index].appName
        } else {
            apps.append(ClipboardCaptureExcludedApp(bundleIdentifier: bundleIdentifier, appName: appName))
        }
        saveExcludedApps(apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
    }

    func removeExcludedApp(bundleIdentifier: String) {
        saveExcludedApps(excludedApps.filter {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) != .orderedSame
        })
    }

    private func seedDefaultExcludedAppsIfNeeded() {
        guard defaults.object(forKey: Self.excludedAppsKey) == nil else {
            return
        }

        saveExcludedApps(Self.defaultExcludedApps)
    }

    private func loadExcludedApps() -> [ClipboardCaptureExcludedApp] {
        guard let data = defaults.data(forKey: Self.excludedAppsKey),
              let apps = try? JSONDecoder().decode([ClipboardCaptureExcludedApp].self, from: data)
        else {
            return []
        }

        return apps
    }

    private func saveExcludedApps(_ apps: [ClipboardCaptureExcludedApp]) {
        guard let data = try? JSONEncoder().encode(apps) else {
            return
        }

        defaults.set(data, forKey: Self.excludedAppsKey)
    }
}
#endif
