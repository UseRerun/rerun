import Foundation
import Testing
import RerunCore
@testable import RerunDaemon

@Suite("ChatEngine")
struct ChatEngineTests {
    private func makeCapture(
        appName: String,
        timestamp: Date = Date(),
        textContent: String
    ) -> Capture {
        Capture(
            timestamp: ISO8601DateFormatter().string(from: timestamp),
            appName: appName,
            windowTitle: nil,
            textSource: "accessibility",
            captureTrigger: "test",
            textContent: textContent,
            textHash: UUID().uuidString
        )
    }

    @Test func exactAppQueryReturnsRecentCaptures() async throws {
        let db = try DatabaseManager()
        try await db.insertCapture(makeCapture(appName: "Finder", textContent: "Applications window"))
        let engine = ChatEngine(db: db, summarySynthesizer: nil)

        let response = await engine.process("Finder")

        #expect(response.content.contains("Finder"))
        #expect(response.sources.count == 1)
        #expect(response.sources[0].appName == "Finder")
    }

    @Test func broadTodayQuestionReturnsRecentCaptures() async throws {
        let db = try DatabaseManager()
        let calendar = Calendar.current
        let midday = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: Date()))!
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: midday,
            textContent: "reviewing rerun chat bug"
        ))
        let engine = ChatEngine(db: db, summarySynthesizer: nil)
        let parsed = ParsedQuery(
            searchTerms: [],
            since: ISO8601DateFormatter().string(from: calendar.startOfDay(for: Date())),
            appFilter: nil,
            rawQuery: "What have I been working on today?"
        )

        let response = await engine.process(parsed: parsed)

        #expect(response.content.contains("Conductor"))
        #expect(response.sources.count == 1)
    }

    @Test func appSummaryPrefersTopicsOverRawRows() async throws {
        let db = try DatabaseManager()
        let midday = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: Date()))!
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: midday,
            textContent: """
            Activity
            C chops Repo settings New workspace from New workspace
            R rerun Repo settings New workspace from New workspace
            Dev app fixed location
            Filter and display
            Phase4 core services
            """
        ))
        let engine = ChatEngine(db: db, summarySynthesizer: nil)
        let parsed = ParsedQuery(
            searchTerms: [],
            since: nil,
            appFilter: "Conductor",
            rawQuery: "What did I work on in Conductor?"
        )

        let response = await engine.process(parsed: parsed)

        #expect(response.content.contains("Workspaces: chops, rerun"))
        #expect(response.content.contains("Observed work:"))
        #expect(response.content.contains("Dev app fixed location"))
        #expect(response.summaryDebug?.workspaces == ["chops", "rerun"])
        #expect(response.summaryDebug?.facts.contains("Dev app fixed location") == true)
        #expect(!response.content.contains("1. "))
    }

    @Test func appSummarySkipsRepeatedSidebarNoise() async throws {
        let db = try DatabaseManager()
        let start = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: Date()))!
        let shared = """
        Activity
        C chops Repo settings New workspace from New workspace
        C clearly Repo settings New workspace from New workspace
        Conductor
        Filter and display
        Phase4 core services
        Tauri + React + Typescript
        Workspaces
        """
        let lines = [
            "Dev app fixed location",
            "accessibility issues are back.",
            "errr. it's crashing when i invoke the chat",
            "okay. let's run",
        ]

        for (offset, line) in lines.enumerated() {
            let timestamp = Calendar.current.date(byAdding: .minute, value: offset, to: start)!
            try await db.insertCapture(makeCapture(
                appName: "Conductor",
                timestamp: timestamp,
                textContent: "\(shared)\n\(line)"
            ))
        }

        let engine = ChatEngine(db: db, summarySynthesizer: nil)
        let parsed = ParsedQuery(
            searchTerms: [],
            since: nil,
            appFilter: "Conductor",
            rawQuery: "What did I work on in Conductor today?"
        )

        let response = await engine.process(parsed: parsed)

        #expect(response.content.contains("Dev app fixed location"))
        #expect(response.content.contains("accessibility issues are back."))
        #expect(response.content.contains("errr. it's crashing when i invoke the chat"))
        #expect(response.summaryDebug?.facts.contains("Dev app fixed location") == true)
        #expect(response.summaryDebug?.facts.contains("accessibility issues are back.") == true)
        #expect(response.summaryDebug?.facts.contains("errr. it's crashing when i invoke the chat") == true)
        #expect(!response.content.contains("Filter and display"))
        #expect(!response.content.contains("Phase4 core services"))
        #expect(!response.content.contains("Tauri + React + Typescript"))
        #expect(!response.content.contains("okay. let's run"))
    }

    @Test func summarySynthesizerReceivesFactsOnly() async throws {
        let db = try DatabaseManager()
        let start = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: Date()))!
        let shared = """
        Activity
        C chops Repo settings New workspace from New workspace
        C clearly Repo settings New workspace from New workspace
        Conductor
        Filter and display
        Phase4 core services
        Workspaces
        """
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: start,
            textContent: "\(shared)\nfix: stable RerunDev.app path for worktree TCC persistence"
        ))
        try await db.insertCapture(makeCapture(
            appName: "Conductor",
            timestamp: Calendar.current.date(byAdding: .minute, value: 1, to: start)!,
            textContent: "\(shared)\nerrr. it's crashing when i invoke the chat"
        ))

        let engine = ChatEngine(
            db: db,
            summarySynthesizer: { request in
                let facts = request.facts.map(\.text).joined(separator: " | ")
                let workspaces = request.workspaces.joined(separator: ", ")
                return "facts=\(facts); workspaces=\(workspaces)"
            }
        )
        let parsed = ParsedQuery(
            searchTerms: [],
            since: nil,
            appFilter: "Conductor",
            rawQuery: "What did I work on in Conductor today?"
        )

        let response = await engine.process(parsed: parsed)

        #expect(response.content.contains("fix: stable RerunDev.app path for worktree TCC persistence"))
        #expect(response.content.contains("errr. it's crashing when i invoke the chat"))
        #expect(response.content.contains("workspaces=chops, clearly"))
        #expect(response.summaryDebug?.facts == [
            "fix: stable RerunDev.app path for worktree TCC persistence",
            "errr. it's crashing when i invoke the chat",
        ])
        #expect(!response.content.contains("Filter and display"))
        #expect(!response.content.contains("Phase4 core services"))
    }
}
