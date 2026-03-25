import Testing
@testable import RerunCore

@Suite("ExclusionManager")
struct ExclusionManagerTests {
    private func makeDB() throws -> DatabaseManager {
        try DatabaseManager()
    }

    @Test func seedsDefaultsOnFirstLoad() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)

        try await manager.loadExclusions()

        let exclusions = try await db.fetchExclusions()
        #expect(exclusions.count == DefaultExclusions.apps.count)
    }

    @Test func doesNotReseedIfExclusionsExist() async throws {
        let db = try makeDB()

        // Insert one custom exclusion manually
        let exclusion = Exclusion(type: "app", value: "com.custom.app")
        try await db.insertExclusion(exclusion)

        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let exclusions = try await db.fetchExclusions()
        #expect(exclusions.count == 1)
    }

    @Test func excludesKnownBundleId() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let result1 = await manager.shouldExcludeApp(bundleId: "com.1password.1password")
        #expect(result1)
        let result2 = await manager.shouldExcludeApp(bundleId: "com.bitwarden.desktop")
        #expect(result2)
    }

    @Test func allowsUnknownBundleId() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let result = await manager.shouldExcludeApp(bundleId: "com.apple.Safari")
        #expect(result == false)
    }

    @Test func nilBundleIdNotExcluded() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let result = await manager.shouldExcludeApp(bundleId: nil)
        #expect(result == false)
    }

    @Test func detectsPrivateBrowsingWindows() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let safari = await manager.shouldExclude(bundleId: "com.apple.Safari", url: nil, windowTitle: "Private Browsing — Google")
        #expect(safari)
        let chrome = await manager.shouldExclude(bundleId: "com.google.Chrome", url: nil, windowTitle: "New Incognito Tab")
        #expect(chrome)
        let edge = await manager.shouldExclude(bundleId: "com.microsoft.edgemac", url: nil, windowTitle: "InPrivate - Bing")
        #expect(edge)
        let firefox = await manager.shouldExclude(bundleId: "org.mozilla.firefox", url: nil, windowTitle: "Private Window")
        #expect(firefox)
    }

    @Test func normalWindowNotExcluded() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let result = await manager.shouldExclude(bundleId: "com.apple.Safari", url: "https://example.com", windowTitle: "Example Domain")
        #expect(result == false)
    }

    @Test func privateBrowsingMarkersDoNotExcludeNormalContent() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let chrome = await manager.shouldExclude(
            bundleId: "com.google.Chrome",
            url: "https://example.com",
            windowTitle: "How Incognito Mode Works"
        )
        #expect(chrome == false)

        let textEdit = await manager.shouldExclude(
            bundleId: "com.apple.TextEdit",
            url: nil,
            windowTitle: "Private Window"
        )
        #expect(textEdit == false)
    }

    @Test func domainExclusionMatches() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        try await manager.addExclusion(type: "domain", value: "*.bankofamerica.com")

        let matched = await manager.shouldExclude(bundleId: nil, url: "https://www.bankofamerica.com/login", windowTitle: nil)
        #expect(matched)
        let notMatched = await manager.shouldExclude(bundleId: nil, url: "https://example.com", windowTitle: nil)
        #expect(notMatched == false)
    }

    @Test func wildcardDomainDoesNotOvermatchSimilarSuffix() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        try await manager.addExclusion(type: "domain", value: "*.bankofamerica.com")

        let matched = await manager.shouldExclude(bundleId: nil, url: "https://evilbankofamerica.com/login", windowTitle: nil)
        #expect(matched == false)
    }

    @Test func domainExclusionIsCaseInsensitive() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        try await manager.addExclusion(type: "domain", value: "*.bankofamerica.com")

        let matched = await manager.shouldExclude(bundleId: nil, url: "https://WWW.BankOfAmerica.com/login", windowTitle: nil)
        #expect(matched)
    }

    @Test func addExclusionTakesEffectImmediately() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let before = await manager.shouldExcludeApp(bundleId: "com.custom.app")
        #expect(before == false)

        try await manager.addExclusion(type: "app", value: "com.custom.app")

        let after = await manager.shouldExcludeApp(bundleId: "com.custom.app")
        #expect(after)
    }

    @Test func removeExclusionTakesEffectImmediately() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let before = await manager.shouldExcludeApp(bundleId: "com.1password.1password")
        #expect(before)

        try await manager.removeExclusion(type: "app", value: "com.1password.1password")

        let after = await manager.shouldExcludeApp(bundleId: "com.1password.1password")
        #expect(after == false)
    }

    @Test func removedDefaultStaysRemovedAfterReload() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        try await manager.removeExclusion(type: "app", value: "com.apple.finder")
        #expect(try await db.exclusionExists(type: "app", value: "com.apple.finder") == false)

        try await manager.loadExclusions()

        let stillRemoved = try await db.exclusionExists(type: "app", value: "com.apple.finder")
        #expect(stillRemoved == false)
        let allowsFinder = await manager.shouldExcludeApp(bundleId: "com.apple.finder")
        #expect(allowsFinder == false)
    }

    @Test func refreshPicksUpExternalDatabaseChanges() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let before = await manager.shouldExcludeApp(bundleId: "com.custom.app")
        #expect(before == false)

        try await db.insertExclusion(Exclusion(type: "app", value: "com.custom.app"))

        let stale = await manager.shouldExcludeApp(bundleId: "com.custom.app")
        #expect(stale == false)

        try await manager.refresh()

        let refreshed = await manager.shouldExcludeApp(bundleId: "com.custom.app")
        #expect(refreshed)
    }

    @Test func excludedCountIncrements() async throws {
        let db = try makeDB()
        let manager = ExclusionManager(db: db)
        try await manager.loadExclusions()

        let initial = await manager.excludedCount
        #expect(initial == 0)

        _ = await manager.shouldExcludeApp(bundleId: "com.1password.1password")
        _ = await manager.shouldExcludeApp(bundleId: "com.bitwarden.desktop")

        let final_ = await manager.excludedCount
        #expect(final_ == 2)
    }
}
