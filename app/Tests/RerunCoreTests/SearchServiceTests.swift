import Foundation
import Testing
@testable import RerunCore

@Suite("SearchService")
struct SearchServiceTests {
    private func makeCapture(
        appName: String,
        timestamp: Date = Date(),
        windowTitle: String? = nil,
        textContent: String
    ) -> Capture {
        Capture(
            timestamp: ISO8601DateFormatter().string(from: timestamp),
            appName: appName,
            windowTitle: windowTitle,
            textSource: "accessibility",
            captureTrigger: "test",
            textContent: textContent,
            textHash: UUID().uuidString
        )
    }

    @Test func searchWithTermsReturnsHitsWithSnippets() async throws {
        let db = try DatabaseManager()
        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "Stripe API documentation for payment intents and webhooks"
        ))

        let parsed = ParsedQuery(
            searchTerms: ["stripe"],
            since: nil,
            appFilter: nil,
            rawQuery: "stripe"
        )
        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "stripe",
            mode: .keyword,
            parsedQuery: parsed
        ))

        #expect(response.hits.count == 1)
        #expect(response.hits[0].capture.appName == "Safari")
        #expect(response.hits[0].snippet.localizedCaseInsensitiveContains("stripe"))
        #expect(response.summary != nil)
    }

    @Test func broadQueryReturnsSummary() async throws {
        let db = try DatabaseManager()
        let midday = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: Date()))!
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: midday,
            textContent: """
            C rerun Repo settings New workspace from New workspace
            fix: stable RerunDev.app path for worktree TCC persistence
            """
        ))

        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "Conductor",
            app: "Conductor",
            limit: 10
        ))

        #expect(response.hits.count == 1)
        #expect(response.summary != nil)
        #expect(response.summary?.workspaces == ["rerun"])
        #expect(response.summary?.facts.contains(where: { $0.text.contains("stable RerunDev.app") }) == true)
    }

    @Test func explicitAppOverridesParsed() async throws {
        let db = try DatabaseManager()
        try await db.insertCapture(makeCapture(
            appName: "Finder",
            textContent: "Applications Documents Downloads"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "Applications web page for downloads"
        ))

        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "applications",
            app: "Finder",
            mode: .keyword
        ))

        #expect(response.hits.allSatisfy { $0.capture.appName == "Finder" })
    }

    @Test func noiseAppsFilteredForBroadQueries() async throws {
        let db = try DatabaseManager()
        let now = Date()
        try await db.insertCapture(makeCapture(
            appName: "RerunDev",
            timestamp: now,
            textContent: "debug output internal"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: Calendar.current.date(byAdding: .second, value: -10, to: now)!,
            textContent: "fix: working on search improvements"
        ))

        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "What have I been doing?",
            limit: 10
        ))

        #expect(response.hits.allSatisfy { $0.capture.appName != "RerunDev" })
    }

    @Test func factExtractionScoresCommitPrefixes() async throws {
        let db = try DatabaseManager()
        let midday = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: Date()))!
        try await db.insertCapture(makeCapture(
            appName: "Terminal",
            timestamp: midday,
            textContent: """
            feat: add hybrid search ranking for keyword-backed results
            plain text that is not very interesting
            """
        ))

        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "Terminal",
            app: "Terminal",
            limit: 10
        ))

        #expect(response.summary != nil)
        #expect(response.summary?.facts.first?.text.contains("feat:") == true)
    }

    @Test func snippetUsesQueryTermsNotRawPrompt() async throws {
        let db = try DatabaseManager()
        let filler = String(repeating: "filler ", count: 24)
        try await db.insertCapture(makeCapture(
            appName: "Safari",
            textContent: "what \(filler)deployment checklist and release notes for the next build"
        ))

        let parsed = ParsedQuery(
            searchTerms: ["deployment", "checklist"],
            since: nil,
            appFilter: nil,
            rawQuery: "what was the deployment checklist"
        )
        let service = SearchService(db: db)
        let response = try await service.search(SearchRequest(
            query: "what was the deployment checklist",
            mode: .keyword,
            parsedQuery: parsed
        ))

        guard let hit = response.hits.first else {
            Issue.record("Expected at least one hit")
            return
        }
        #expect(hit.snippet.localizedCaseInsensitiveContains("deployment"))
    }
}
