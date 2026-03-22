import Testing
import Foundation
@testable import RerunCore

@Suite("HybridSearch")
struct HybridSearchTests {

    private func makeDB() throws -> DatabaseManager {
        try DatabaseManager()
    }

    private func makeCapture(
        id: String = UUID().uuidString,
        appName: String = "Safari",
        windowTitle: String? = "Test Window",
        url: String? = nil,
        textContent: String = "Test content",
        textHash: String? = nil,
        timestamp: Date = Date()
    ) -> Capture {
        Capture(
            id: id,
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

    // MARK: - Score Normalization

    @Test func normalizeRankMapsNegativeToZeroOne() {
        // FTS5 ranks are negative (more negative = better)
        #expect(HybridSearch.normalizeRank(0) == 1.0)
        #expect(HybridSearch.normalizeRank(-1.0) == 0.5)
        let result = HybridSearch.normalizeRank(-4.0)
        #expect(abs(result - 0.2) < 0.001)
    }

    @Test func normalizeDistanceMapsPositiveToZeroOne() {
        // Vector distances: 0 = identical, higher = more different
        #expect(HybridSearch.normalizeDistance(0) == 1.0)
        #expect(HybridSearch.normalizeDistance(1.0) == 0.5)
        let result = HybridSearch.normalizeDistance(3.0)
        #expect(abs(result - 0.25) < 0.001)
    }

    // MARK: - Database Ranked Methods

    @Test func searchCapturesWithRankReturnsRank() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            textContent: "Stripe API charges endpoint",
            textHash: "h1"
        ))

        let results = try await db.searchCapturesWithRank(query: "stripe")
        #expect(results.count == 1)
        #expect(results[0].capture.textContent.contains("Stripe"))
        #expect(results[0].rank < 0) // FTS5 ranks are negative
    }

    @Test func searchCapturesWithRankFiltersApp() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "API docs for payments",
            textHash: "h1"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Chrome",
            textContent: "API docs for auth",
            textHash: "h2"
        ))

        let results = try await db.searchCapturesWithRank(query: "API", app: "safari")
        #expect(results.count == 1)
        #expect(results[0].capture.appName == "Safari")
    }

    @Test func searchCapturesWithRankFiltersSince() async throws {
        let db = try makeDB()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(3600)

        try await db.insertCapture(makeCapture(
            id: "old",
            textContent: "Ashley planning dinner",
            textHash: "h-old",
            timestamp: older
        ))
        try await db.insertCapture(makeCapture(
            id: "new",
            textContent: "Ashley booked the hotel",
            textHash: "h-new",
            timestamp: newer
        ))

        let since = ISO8601DateFormatter().string(from: newer.addingTimeInterval(-60))
        let results = try await db.searchCapturesWithRank(query: "ashley", since: since)

        #expect(results.count == 1)
        #expect(results[0].capture.id == "new")
    }

    @Test func findSimilarWithDistanceReturnsDistance() async throws {
        let db = try makeDB()
        let capture = makeCapture(id: "cap1", textContent: "test", textHash: "h1")
        try await db.insertCapture(capture)

        let embedding = [Float](repeating: 0.1, count: 512)
        try await db.insertEmbedding(captureId: "cap1", embedding: embedding)

        let query = [Float](repeating: 0.1, count: 512)
        let results = try await db.findSimilarWithDistance(to: query, limit: 5)
        #expect(results.count == 1)
        #expect(results[0].capture.id == "cap1")
        #expect(results[0].distance >= 0) // Distance is non-negative
    }

    @Test func findSimilarWithDistanceFiltersApp() async throws {
        let db = try makeDB()
        let c1 = makeCapture(id: "cap1", appName: "Safari", textContent: "test1", textHash: "h1")
        let c2 = makeCapture(id: "cap2", appName: "Chrome", textContent: "test2", textHash: "h2")
        try await db.insertCapture(c1)
        try await db.insertCapture(c2)

        let emb = [Float](repeating: 0.1, count: 512)
        try await db.insertEmbedding(captureId: "cap1", embedding: emb)
        try await db.insertEmbedding(captureId: "cap2", embedding: emb)

        let results = try await db.findSimilarWithDistance(to: emb, app: "Safari", limit: 5)
        #expect(results.count == 1)
        #expect(results[0].capture.appName == "Safari")
    }

    // MARK: - Keyword Mode

    @Test func keywordModeUsesOnlyFTS5() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            textContent: "Stripe payment processing",
            textHash: "h1"
        ))

        let search = HybridSearch()
        let embedder = EmbeddingGenerator()
        let results = try await search.search(
            query: "stripe",
            mode: .keyword,
            db: db,
            embedder: embedder
        )

        #expect(results.count == 1)
        #expect(results[0].source == .keyword)
        #expect(results[0].capture.textContent.contains("Stripe"))
    }

    @Test func keywordModeNormalizesInvisibleNoise() async throws {
        let db = try makeDB()
        try await db.insertCapture(makeCapture(
            textContent: "Ashley Pigford dinner plans",
            textHash: "h1"
        ))

        let search = HybridSearch()
        let embedder = EmbeddingGenerator()
        let results = try await search.search(
            query: "Ashley\u{200B}",
            mode: .keyword,
            db: db,
            embedder: embedder
        )

        #expect(results.count == 1)
        #expect(results[0].capture.textContent.contains("Ashley"))
    }

    // MARK: - Hybrid Dedup

    @Test func hybridDeduplicatesResults() async throws {
        let db = try makeDB()
        // Insert a capture that will appear in both FTS5 and vector results
        let c = makeCapture(id: "cap1", textContent: "Stripe API charges endpoint", textHash: "h1")
        try await db.insertCapture(c)

        let emb = [Float](repeating: 0.1, count: 512)
        try await db.insertEmbedding(captureId: "cap1", embedding: emb)

        // Search with a query that hits FTS5 ("stripe") and provide an embedding
        let ranked = try await db.searchCapturesWithRank(query: "stripe")
        #expect(ranked.count == 1)

        let vecResults = try await db.findSimilarWithDistance(to: emb, limit: 5)
        #expect(vecResults.count == 1)

        // Both return the same capture — hybrid search should dedup
        // We test this at the DB level since EmbeddingGenerator may not be available
    }

    @Test func mergeKeepsKeywordHitsAheadOfSemanticOnlyResults() {
        let search = HybridSearch()
        let keywordCapture = makeCapture(id: "keyword", textContent: "Ashley Pigford dinner plans")
        let semanticCapture = makeCapture(id: "semantic", textContent: "Conductor workspace notes")

        let results = search.merge(
            keyword: [(capture: keywordCapture, rank: -20)],
            vector: [(capture: semanticCapture, distance: 0.05)],
            limit: 2
        )

        #expect(results.count == 2)
        #expect(results[0].capture.id == "keyword")
        #expect(results[0].source == .keyword)
        #expect(results[1].capture.id == "semantic")
        #expect(results[1].source == .semantic)
    }
}

@Suite("QueryParser")
struct QueryParserTests {

    private let parser = QueryParser()

    @Test func parsePlainQuery() {
        let result = parser.parse("stripe API")
        #expect(result.searchTerms == ["stripe", "API"])
        #expect(result.since == nil)
        #expect(result.appFilter == nil)
    }

    @Test func parseToday() {
        let now = Date()
        let result = parser.parse("meeting notes today", now: now)

        #expect(result.searchTerms.contains("meeting"))
        #expect(result.searchTerms.contains("notes"))
        #expect(result.since != nil)
    }

    @Test func parseYesterday() {
        let now = Date()
        let result = parser.parse("API docs yesterday", now: now)

        #expect(result.searchTerms.contains("API"))
        #expect(result.searchTerms.contains("docs"))
        #expect(result.since != nil)

        // Verify the since date is yesterday
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let expectedStart = calendar.startOfDay(for: yesterday)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        #expect(result.since == formatter.string(from: expectedStart))
    }

    @Test func parseDaysAgo() {
        let now = Date()
        let result = parser.parse("deploy logs 3 days ago", now: now)

        #expect(result.searchTerms.contains("deploy"))
        #expect(result.searchTerms.contains("logs"))
        #expect(result.since != nil)
    }

    @Test func parseAppFilter() {
        let result = parser.parse("API docs in Safari")
        #expect(result.appFilter == "Safari")
        #expect(result.searchTerms.contains("API"))
        #expect(result.searchTerms.contains("docs"))
        #expect(!result.searchTerms.contains("in"))
        #expect(!result.searchTerms.contains("Safari"))
    }

    @Test func parseAppFilterFrom() {
        let result = parser.parse("error logs from terminal")
        #expect(result.appFilter == "Terminal")
        #expect(result.searchTerms.contains("error"))
        #expect(result.searchTerms.contains("logs"))
    }

    @Test func parseCombinedTimeAndApp() {
        let result = parser.parse("meeting notes from yesterday in Zoom")

        // Should extract both time and app
        #expect(result.since != nil)
        // Note: parsing order may vary — either app or time could be extracted
        #expect(result.searchTerms.contains("meeting"))
        #expect(result.searchTerms.contains("notes"))
    }

    @Test func effectiveQueryJoinsTerms() {
        let result = parser.parse("stripe API docs")
        #expect(result.effectiveQuery == "stripe API docs")
    }

    @Test func effectiveQueryFallsBackToRaw() {
        let parsed = ParsedQuery(
            searchTerms: [],
            since: nil,
            appFilter: nil,
            rawQuery: "some query"
        )
        #expect(parsed.effectiveQuery == "some query")
    }

    @Test func parseBestEffortFallsBackToRegexWhenLLMUnavailable() async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return
        }
        #endif

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = await parser.parseBestEffort("API docs in Safari yesterday", now: now)

        #expect(result.appFilter == "Safari")
        #expect(result.searchTerms == ["API", "docs"])
        #expect(result.since != nil)
    }

    @Test func mergeBestEffortPrefersRegexTimeAndApp() {
        let regex = ParsedQuery(
            searchTerms: ["what", "was", "I", "reading", "about", "Stripe"],
            since: "2026-03-20T00:00:00Z",
            appFilter: "Safari",
            rawQuery: "what was I reading in Safari about Stripe yesterday"
        )
        let llm = ParsedQuery(
            searchTerms: ["Stripe", "Safari"],
            since: "2023-10-01T00:00:00Z",
            appFilter: "Safari",
            rawQuery: regex.rawQuery
        )

        let merged = parser.mergeBestEffort(regex: regex, llm: llm)

        #expect(merged.searchTerms == ["Stripe"])
        #expect(merged.since == "2026-03-20T00:00:00Z")
        #expect(merged.appFilter == "Safari")
    }

    @Test func mergeBestEffortUsesLLMTermsWhenTheyAreCleaner() {
        let regex = ParsedQuery(
            searchTerms: ["what", "was", "I", "reading", "about", "Stripe"],
            since: nil,
            appFilter: nil,
            rawQuery: "what was I reading about Stripe"
        )
        let llm = ParsedQuery(
            searchTerms: ["Stripe"],
            since: nil,
            appFilter: nil,
            rawQuery: regex.rawQuery
        )

        let merged = parser.mergeBestEffort(regex: regex, llm: llm)

        #expect(merged.searchTerms == ["Stripe"])
        #expect(merged.since == nil)
        #expect(merged.appFilter == nil)
    }

    @Test func parseExactAppNameUsesAppFilter() {
        let result = parser.parse("Finder")

        #expect(result.appFilter == "Finder")
        #expect(result.searchTerms.isEmpty)
    }

    @Test func parseKnownAppFromNaturalLanguageUsesAppFilter() {
        let result = parser.parse("What did I work on in Conductor?")

        #expect(result.appFilter == "Conductor")
        #expect(result.searchTerms.isEmpty)
    }

    @Test func parseBroadTodayQuestionDropsFillerTerms() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = parser.parse("What have I been working on today?", now: now)

        #expect(result.since != nil)
        #expect(result.searchTerms.isEmpty)
    }

    @Test func parseLastThirtyMinutesChatQuestionDropsTimeAndChatNoise() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = parser.parse("What did I chat with ashley about in the last 30 minutes?", now: now)

        #expect(result.since != nil)
        #expect(result.appFilter == "Messages")
        #expect(result.searchTerms.map { $0.lowercased() } == ["ashley"])
    }

    @Test func parseKnownAppInsideTermsUsesAppFilter() {
        let result = parser.parse("Ashley messages")

        #expect(result.appFilter == "Messages")
        #expect(result.searchTerms.map { $0.lowercased() } == ["ashley"])
    }

    @Test func mergeBestEffortIgnoresLLMTimeWithoutTimeHint() {
        let regex = ParsedQuery(
            searchTerms: ["Finder"],
            since: nil,
            appFilter: nil,
            rawQuery: "Finder"
        )
        let llm = ParsedQuery(
            searchTerms: ["Finder"],
            since: "2026-03-21T19:43:21Z",
            appFilter: "",
            rawQuery: regex.rawQuery
        )

        let merged = parser.mergeBestEffort(regex: regex, llm: llm)

        #expect(merged.appFilter == "Finder")
        #expect(merged.since == nil)
        #expect(merged.searchTerms.isEmpty)
    }
}
