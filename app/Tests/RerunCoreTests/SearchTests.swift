import Testing
import Foundation
@testable import RerunCore

@Suite("Search")
struct SearchTests {

    private func makeDB() throws -> DatabaseManager {
        try DatabaseManager()
    }

    private func makeCapture(
        appName: String = "Safari",
        windowTitle: String? = "Test Window",
        url: String? = nil,
        textContent: String = "Stripe API charges endpoint POST /v1/charges",
        textHash: String? = nil,
        timestamp: Date = Date()
    ) -> Capture {
        Capture(
            timestamp: ISO8601DateFormatter().string(from: timestamp),
            appName: appName,
            bundleId: "com.test.app",
            windowTitle: windowTitle,
            url: url,
            textSource: "accessibility",
            captureTrigger: "app_switch",
            textContent: textContent,
            textHash: textHash ?? UUID().uuidString
        )
    }

    // MARK: - Database Search Tests

    @Test func searchReturnsResults() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            textContent: "Stripe API charges endpoint",
            textHash: "h1"
        ))
        try await db.insertCapture(makeCapture(
            textContent: "React hooks documentation",
            textHash: "h2"
        ))
        try await db.insertCapture(makeCapture(
            textContent: "Git rebase tutorial",
            textHash: "h3"
        ))

        let results = try await db.searchCaptures(query: "stripe")
        #expect(results.count == 1)
        #expect(results[0].textContent.contains("Stripe"))
    }

    @Test func searchCaseInsensitiveApp() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "API documentation for payments",
            textHash: "h1"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Chrome",
            textContent: "API documentation for authentication",
            textHash: "h2"
        ))

        // Lowercase "safari" should match "Safari"
        let results = try await db.searchCaptures(query: "API", app: "safari")
        #expect(results.count == 1)
        #expect(results[0].appName == "Safari")
    }

    @Test func searchWithSinceFilter() async throws {
        let db = try makeDB()
        let formatter = ISO8601DateFormatter()

        try await db.insertCapture(makeCapture(
            textContent: "recent stripe payment",
            textHash: "h1",
            timestamp: Date(timeIntervalSinceNow: -1800) // 30 min ago
        ))
        try await db.insertCapture(makeCapture(
            textContent: "old stripe documentation",
            textHash: "h2",
            timestamp: Date(timeIntervalSinceNow: -172800) // 2 days ago
        ))

        let sinceOneHour = formatter.string(from: Date(timeIntervalSinceNow: -3600))
        let results = try await db.searchCaptures(query: "stripe", since: sinceOneHour)
        #expect(results.count == 1)
        #expect(results[0].textContent.contains("recent"))
    }

    @Test func searchWithOffsetSinceFilter() async throws {
        let db = try makeDB()

        try await db.insertCapture(makeCapture(
            textContent: "stripe before cutoff",
            textHash: "h1",
            timestamp: formatterDate("2026-03-21T10:00:00Z")
        ))
        try await db.insertCapture(makeCapture(
            textContent: "stripe after cutoff",
            textHash: "h2",
            timestamp: formatterDate("2026-03-21T14:00:00Z")
        ))

        let results = try await db.searchCaptures(
            query: "stripe",
            since: "2026-03-21T08:00:00-05:00"
        )

        #expect(results.count == 1)
        #expect(results[0].textContent.contains("after"))
    }

    @Test func searchEmptyQuery() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture())

        let results = try await db.searchCaptures(query: "")
        #expect(results.isEmpty)
    }

    @Test func searchRespectsLimit() async throws {
        let db = try makeDB()
        for i in 0..<5 {
            try await db.insertCapture(makeCapture(
                textContent: "deploy version \(i) to production",
                textHash: "h\(i)"
            ))
        }

        let results = try await db.searchCaptures(query: "deploy", limit: 2)
        #expect(results.count == 2)
    }

    @Test func searchRejectsNonPositiveLimit() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            textContent: "deploy version one",
            textHash: "h1"
        ))

        let results = try await db.searchCaptures(query: "deploy", limit: -1)
        #expect(results.isEmpty)
    }

    // MARK: - Snippet Tests

    @Test func snippetCentersOnMatch() {
        let text = String(repeating: "word ", count: 100) + "stripe payment API" + String(repeating: " word", count: 100)
        let snippet = SearchResult.makeSnippet(from: text, query: "stripe")

        #expect(snippet.contains("stripe"))
        #expect(snippet.hasPrefix("..."))
        #expect(snippet.hasSuffix("..."))
        #expect(snippet.count <= 210) // 200 + ellipsis
    }

    @Test func snippetShortText() {
        let text = "Short text about stripe"
        let snippet = SearchResult.makeSnippet(from: text, query: "stripe")

        #expect(snippet == "Short text about stripe")
        #expect(!snippet.contains("..."))
    }

    @Test func snippetFallsBackToStart() {
        let text = String(repeating: "a", count: 500)
        let snippet = SearchResult.makeSnippet(from: text, query: "nonexistent")

        // Should start from the beginning since no match found
        #expect(snippet.hasPrefix("aaa"))
        #expect(snippet.hasSuffix("..."))
    }

    @Test func parseSinceNormalizesISO8601Offsets() {
        let parsed = SearchTimeParser.parseSince("2026-03-21T08:00:00-05:00")
        #expect(parsed == "2026-03-21T13:00:00Z")
    }

    @Test func parseSinceRejectsOversizedDurations() {
        let parsed = SearchTimeParser.parseSince("999999999999999999999999h")
        #expect(parsed == nil)
    }

    private func formatterDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}
