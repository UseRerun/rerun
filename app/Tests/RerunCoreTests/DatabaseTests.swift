import Testing
import Foundation
@testable import RerunCore

@Suite("DatabaseManager")
struct DatabaseTests {

    private func makeDB() throws -> DatabaseManager {
        try DatabaseManager()
    }

    private func makeCapture(
        appName: String = "Safari",
        textContent: String = "Stripe API charges endpoint POST /v1/charges",
        textHash: String? = nil
    ) -> Capture {
        Capture(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            appName: appName,
            bundleId: "com.apple.Safari",
            windowTitle: "Stripe API Reference",
            url: "https://stripe.com/docs/api/charges",
            textSource: "accessibility",
            captureTrigger: "app_switch",
            textContent: textContent,
            textHash: textHash ?? UUID().uuidString
        )
    }

    @Test func schemaCreation() async throws {
        let db = try makeDB()
        let count = try await db.captureCount()
        #expect(count == 0)
    }

    @Test func insertAndFetch() async throws {
        let db = try makeDB()
        let capture = makeCapture()
        try await db.insertCapture(capture)

        let fetched = try await db.fetchCaptures(limit: 10)
        #expect(fetched.count == 1)
        #expect(fetched[0].id == capture.id)
        #expect(fetched[0].appName == "Safari")
        #expect(fetched[0].textContent == capture.textContent)
    }

    @Test func fetchById() async throws {
        let db = try makeDB()
        let capture = makeCapture()
        try await db.insertCapture(capture)

        let fetched = try await db.fetchCapture(id: capture.id)
        #expect(fetched != nil)
        #expect(fetched?.id == capture.id)

        let missing = try await db.fetchCapture(id: "nonexistent")
        #expect(missing == nil)
    }

    @Test func captureCount() async throws {
        let db = try makeDB()
        #expect(try await db.captureCount() == 0)

        try await db.insertCapture(makeCapture(textHash: "hash1"))
        try await db.insertCapture(makeCapture(textHash: "hash2"))
        try await db.insertCapture(makeCapture(textHash: "hash3"))
        #expect(try await db.captureCount() == 3)
    }

    @Test func fts5Search() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date()),
            appName: "Safari",
            windowTitle: "Stripe API Reference",
            url: "https://stripe.com/docs/api/charges",
            textSource: "accessibility",
            captureTrigger: "app_switch",
            textContent: "Stripe API charges endpoint POST /v1/charges",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date()),
            appName: "Terminal",
            windowTitle: "zsh",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "git commit -m 'fix login bug'",
            textHash: "h2"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date()),
            appName: "Safari",
            windowTitle: "React Docs",
            url: "https://react.dev/learn",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "React documentation hooks tutorial",
            textHash: "h3"
        ))

        let stripeResults = try await db.searchCaptures(query: "stripe charges")
        #expect(stripeResults.count == 1)
        #expect(stripeResults[0].appName == "Safari")

        let gitResults = try await db.searchCaptures(query: "git commit")
        #expect(gitResults.count == 1)
        #expect(gitResults[0].appName == "Terminal")
    }

    @Test func searchFilterByApp() async throws {
        let db = try makeDB()

        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "API documentation for payments"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Chrome",
            textContent: "API documentation for authentication"
        ))

        let safariOnly = try await db.searchCaptures(query: "API", app: "Safari")
        #expect(safariOnly.count == 1)
        #expect(safariOnly[0].appName == "Safari")
    }

    @Test func searchNoResults() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture())
        let results = try await db.searchCaptures(query: "nonexistent gibberish xyz")
        #expect(results.isEmpty)
    }

    @Test func latestHashForApp() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -60)),
            appName: "Safari",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "old content",
            textHash: "hash_old"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date()),
            appName: "Safari",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "new content",
            textHash: "hash_new"
        ))

        let hash = try await db.latestHashForApp("Safari")
        #expect(hash == "hash_new")

        let noHash = try await db.latestHashForApp("Terminal")
        #expect(noHash == nil)
    }

    @Test func exclusionCRUD() async throws {
        let db = try makeDB()

        let exclusion = Exclusion(type: "app", value: "1Password")
        try await db.insertExclusion(exclusion)

        let all = try await db.fetchExclusions()
        #expect(all.count == 1)
        #expect(all[0].value == "1Password")

        let exists = try await db.exclusionExists(type: "app", value: "1Password")
        #expect(exists)

        let notExists = try await db.exclusionExists(type: "app", value: "Safari")
        #expect(!notExists)

        let deleted = try await db.deleteExclusion(id: exclusion.id)
        #expect(deleted)
        #expect(try await db.fetchExclusions().isEmpty)
    }

    @Test func summaryCRUD() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        let summary = Summary(
            periodType: "hourly",
            periodStart: formatter.string(from: Date(timeIntervalSinceNow: -3600)),
            periodEnd: formatter.string(from: Date()),
            summaryText: "Worked on Stripe integration in Safari"
        )
        try await db.insertSummary(summary)

        let hourly = try await db.fetchSummaries(periodType: "hourly")
        #expect(hourly.count == 1)
        #expect(hourly[0].summaryText.contains("Stripe"))

        let daily = try await db.fetchSummaries(periodType: "daily")
        #expect(daily.isEmpty)
    }

    @Test func fetchCaptureClosestTo() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        let t1 = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let t2 = Date(timeIntervalSinceNow: -1800) // 30 min ago
        let t3 = Date(timeIntervalSinceNow: -600)  // 10 min ago

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: t1),
            appName: "App1",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "one hour ago",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: t2),
            appName: "App2",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "thirty min ago",
            textHash: "h2"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: t3),
            appName: "App3",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "ten min ago",
            textHash: "h3"
        ))

        // Query closest to 25 min ago — should match the 30-min-ago capture
        let target = formatter.string(from: Date(timeIntervalSinceNow: -1500))
        let closest = try await db.fetchCapture(closestTo: target)
        #expect(closest?.appName == "App2")

        // Empty DB returns nil
        let emptyDb = try makeDB()
        let nothing = try await emptyDb.fetchCapture(closestTo: target)
        #expect(nothing == nil)
    }

    @Test func fetchCapturesWithSince() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -7200)),
            appName: "Old",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "old capture",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -600)),
            appName: "Recent",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "recent capture",
            textHash: "h2"
        ))

        // Fetch all
        let all = try await db.fetchCaptures(since: nil, limit: 100)
        #expect(all.count == 2)

        // Fetch since 1 hour ago — only recent
        let since = formatter.string(from: Date(timeIntervalSinceNow: -3600))
        let filtered = try await db.fetchCaptures(since: since, limit: 100)
        #expect(filtered.count == 1)
        #expect(filtered[0].appName == "Recent")
    }

    @Test func fetchCapturesWithoutLimitReturnsAllMatches() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -7200)),
            appName: "Old",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "old capture",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -600)),
            appName: "Recent",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "recent capture",
            textHash: "h2"
        ))

        let all = try await db.fetchCaptures(since: nil, limit: nil)
        #expect(all.count == 2)

        let since = formatter.string(from: Date(timeIntervalSinceNow: -3600))
        let filtered = try await db.fetchCaptures(since: since, limit: nil)
        #expect(filtered.count == 1)
        #expect(filtered[0].appName == "Recent")
    }

    @Test func topApps() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()
        let now = Date()

        for i in 0..<5 {
            try await db.insertCapture(Capture(
                timestamp: formatter.string(from: now.addingTimeInterval(TimeInterval(-i))),
                appName: "Safari",
                textSource: "accessibility",
                captureTrigger: "idle",
                textContent: "safari \(i)",
                textHash: "s\(i)"
            ))
        }
        for i in 0..<3 {
            try await db.insertCapture(Capture(
                timestamp: formatter.string(from: now.addingTimeInterval(TimeInterval(-i))),
                appName: "Terminal",
                textSource: "accessibility",
                captureTrigger: "idle",
                textContent: "terminal \(i)",
                textHash: "t\(i)"
            ))
        }

        let top = try await db.topApps()
        #expect(top.count == 2)
        #expect(top[0].appName == "Safari")
        #expect(top[0].count == 5)
        #expect(top[1].appName == "Terminal")
        #expect(top[1].count == 3)
    }

    @Test func topURLs() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()
        let now = Date()

        for i in 0..<4 {
            try await db.insertCapture(Capture(
                timestamp: formatter.string(from: now.addingTimeInterval(TimeInterval(-i))),
                appName: "Safari",
                url: "https://example.com/docs",
                textSource: "accessibility",
                captureTrigger: "idle",
                textContent: "docs \(i)",
                textHash: "d\(i)"
            ))
        }
        for i in 0..<2 {
            try await db.insertCapture(Capture(
                timestamp: formatter.string(from: now.addingTimeInterval(TimeInterval(-60 - i))),
                appName: "Safari",
                url: "https://example.com/blog",
                textSource: "accessibility",
                captureTrigger: "idle",
                textContent: "blog \(i)",
                textHash: "b\(i)"
            ))
        }

        let top = try await db.topURLs()
        #expect(top.count == 2)
        #expect(top[0].url == "https://example.com/docs")
        #expect(top[0].count == 4)
        #expect(top[1].url == "https://example.com/blog")
        #expect(top[1].count == 2)
    }

    @Test func captureStatsWithSince() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        let old = formatter.string(from: Date(timeIntervalSinceNow: -7200))
        let middle = formatter.string(from: Date(timeIntervalSinceNow: -1800))
        let recent = formatter.string(from: Date(timeIntervalSinceNow: -600))

        try await db.insertCapture(Capture(
            timestamp: old,
            appName: "Old",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "old capture",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: middle,
            appName: "Middle",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "middle capture",
            textHash: "h2"
        ))
        try await db.insertCapture(Capture(
            timestamp: recent,
            appName: "Recent",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "recent capture",
            textHash: "h3"
        ))

        let since = formatter.string(from: Date(timeIntervalSinceNow: -3600))
        #expect(try await db.captureCount(since: since) == 2)
        #expect(try await db.oldestCaptureTimestamp(since: since) == middle)
        #expect(try await db.newestCaptureTimestamp(since: since) == recent)
    }

    @Test func fetchCapturesOrdering() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -120)),
            appName: "First",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "first capture",
            textHash: "h1"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date()),
            appName: "Third",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "third capture",
            textHash: "h3"
        ))
        try await db.insertCapture(Capture(
            timestamp: formatter.string(from: Date(timeIntervalSinceNow: -60)),
            appName: "Second",
            textSource: "accessibility",
            captureTrigger: "idle",
            textContent: "second capture",
            textHash: "h2"
        ))

        let results = try await db.fetchCaptures(limit: 10)
        #expect(results.count == 3)
        #expect(results[0].appName == "Third")
        #expect(results[1].appName == "Second")
        #expect(results[2].appName == "First")
    }
}
