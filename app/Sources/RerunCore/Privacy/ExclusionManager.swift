import Foundation
import os

/// Manages app, domain, and window exclusions for the capture pipeline.
/// Maintains an in-memory cache for fast lookups during capture.
public actor ExclusionManager {
    private let db: DatabaseManager
    private let logger = Logger(subsystem: "com.rerun", category: "ExclusionManager")

    // In-memory caches
    private var appBundleIds: Set<String> = []
    private var domainPatterns: [String] = []

    // Stats
    public private(set) var excludedCount: Int = 0

    public init(db: DatabaseManager) {
        self.db = db
    }

    /// Load exclusions from DB into memory. Seeds defaults on first run.
    public func loadExclusions() async throws {
        let existing = try await db.fetchExclusions()

        if existing.isEmpty {
            try await seedDefaults()
        }

        try await rebuildCache()
    }

    // MARK: - Exclusion Checks

    /// Fast check by bundle ID only. Call BEFORE capture to skip extraction entirely.
    public func shouldExcludeApp(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if appBundleIds.contains(bundleId) {
            excludedCount += 1
            return true
        }
        return false
    }

    /// Full check including URL and window title. Call AFTER capture for URL/window-based exclusions.
    public func shouldExclude(bundleId: String?, url: String?, windowTitle: String?) -> Bool {
        // Bundle ID check
        if let bundleId, appBundleIds.contains(bundleId) {
            excludedCount += 1
            return true
        }

        // Private browsing window check
        if let bundleId, let title = windowTitle, isPrivateBrowsingWindow(bundleId: bundleId, title: title) {
            excludedCount += 1
            return true
        }

        // Domain exclusion check
        if let url, let host = URLComponents(string: url)?.host {
            for pattern in domainPatterns {
                if matchesDomain(host: host, pattern: pattern) {
                    excludedCount += 1
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Mutation

    /// Add a new exclusion. Updates cache immediately.
    public func addExclusion(type: String, value: String) async throws {
        let exists = try await db.exclusionExists(type: type, value: value)
        guard !exists else { return }
        let exclusion = Exclusion(type: type, value: value)
        try await db.insertExclusion(exclusion)
        try await rebuildCache()
        logger.info("Added exclusion: \(type) = \(value)")
    }

    /// Remove an exclusion by type and value. Updates cache immediately.
    public func removeExclusion(type: String, value: String) async throws {
        let exclusions = try await db.fetchExclusions()
        guard let match = exclusions.first(where: { $0.type == type && $0.value == value }) else {
            return
        }
        _ = try await db.deleteExclusion(id: match.id)
        try await rebuildCache()
        logger.info("Removed exclusion: \(type) = \(value)")
    }

    // MARK: - Private

    private func seedDefaults() async throws {
        for app in DefaultExclusions.apps {
            let exclusion = Exclusion(type: "app", value: app.bundleId)
            try await db.insertExclusion(exclusion)
        }
        logger.info("Seeded \(DefaultExclusions.apps.count) default exclusions")
    }

    private func rebuildCache() async throws {
        let exclusions = try await db.fetchExclusions()
        appBundleIds = Set(exclusions.filter { $0.type == "app" }.map(\.value))
        domainPatterns = exclusions.filter { $0.type == "domain" }.map(\.value)
    }

    private func isPrivateBrowsingWindow(bundleId: String, title: String) -> Bool {
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if DefaultExclusions.safariPrivateBrowsingBundleIds.contains(bundleId) {
            return matchesWindowMarker(normalizedTitle, marker: "private browsing")
        }

        if DefaultExclusions.chromiumPrivateBrowsingBundleIds.contains(bundleId) {
            return normalizedTitle == "new incognito tab" ||
                matchesWindowMarker(normalizedTitle, marker: "incognito")
        }

        if DefaultExclusions.edgePrivateBrowsingBundleIds.contains(bundleId) {
            return matchesWindowMarker(normalizedTitle, marker: "inprivate")
        }

        if DefaultExclusions.firefoxPrivateBrowsingBundleIds.contains(bundleId) {
            return matchesWindowMarker(normalizedTitle, marker: "private browsing") ||
                matchesWindowMarker(normalizedTitle, marker: "private window")
        }

        return false
    }

    private func matchesWindowMarker(_ title: String, marker: String) -> Bool {
        if title == marker { return true }

        for separator in [" - ", " — ", " – ", ": "] {
            if title.hasPrefix(marker + separator) || title.hasSuffix(separator + marker) {
                return true
            }
        }

        return false
    }

    private func matchesDomain(host: String, pattern: String) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedPattern = pattern.lowercased()

        if normalizedHost == normalizedPattern { return true }
        if normalizedPattern.hasPrefix("*.") {
            let suffix = String(normalizedPattern.dropFirst(2))
            return normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
        return false
    }
}
