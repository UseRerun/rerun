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
