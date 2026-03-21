import Foundation
import Testing
@testable import RerunCore

@Suite("AgentFileGenerator")
struct AgentFileGeneratorTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rerun-agent-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func timestampForToday(hour: Int, minute: Int = 0) throws -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay) else {
            throw TestError.invalidDate
        }
        return ISO8601DateFormatter().string(from: date)
    }

    private func makeCapture(
        timestamp: String,
        appName: String,
        textHash: String,
        url: String? = nil
    ) -> Capture {
        Capture(
            timestamp: timestamp,
            appName: appName,
            bundleId: "com.example.\(appName.lowercased())",
            windowTitle: "\(appName) Window",
            url: url,
            textSource: "accessibility",
            captureTrigger: "timer",
            textContent: "\(appName) work",
            textHash: textHash
        )
    }

    @Test func todayMdIncludesOvernightMorningAfternoonAndEveningSections() async throws {
        let db = try DatabaseManager()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await db.insertCapture(makeCapture(
            timestamp: try timestampForToday(hour: 1),
            appName: "NightApp",
            textHash: "night",
            url: "https://night.example.com"
        ))
        try await db.insertCapture(makeCapture(
            timestamp: try timestampForToday(hour: 8),
            appName: "MorningApp",
            textHash: "morning"
        ))
        try await db.insertCapture(makeCapture(
            timestamp: try timestampForToday(hour: 14),
            appName: "AfternoonApp",
            textHash: "afternoon"
        ))
        try await db.insertCapture(makeCapture(
            timestamp: try timestampForToday(hour: 20),
            appName: "EveningApp",
            textHash: "evening"
        ))

        let generator = AgentFileGenerator(baseURL: dir, summaryProvider: { _, _ in nil })
        try await generator.generateTodayMd(db: db)

        let content = try String(contentsOf: dir.appendingPathComponent("today.md"), encoding: .utf8)
        #expect(content.contains("## Overnight (12am–6am)"))
        #expect(content.contains("1 captures across NightApp."))
        #expect(content.contains("## Morning (6am–12pm)"))
        #expect(content.contains("1 captures across MorningApp."))
        #expect(content.contains("## Afternoon (12pm–6pm)"))
        #expect(content.contains("1 captures across AfternoonApp."))
        #expect(content.contains("## Evening (6pm–midnight)"))
        #expect(content.contains("1 captures across EveningApp."))
    }

    @Test func todayMdStillIncludesOlderCapturesWhenDayExceedsFiveHundredEntries() async throws {
        let db = try DatabaseManager()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await db.insertCapture(makeCapture(
            timestamp: try timestampForToday(hour: 1),
            appName: "NightApp",
            textHash: "night-anchor"
        ))

        let morningTimestamp = try timestampForToday(hour: 9)
        for i in 0..<500 {
            try await db.insertCapture(makeCapture(
                timestamp: morningTimestamp,
                appName: "MorningApp",
                textHash: "morning-\(i)"
            ))
        }

        let generator = AgentFileGenerator(baseURL: dir, summaryProvider: { _, _ in nil })
        try await generator.generateTodayMd(db: db)

        let content = try String(contentsOf: dir.appendingPathComponent("today.md"), encoding: .utf8)
        #expect(content.contains("captures: 501"))
        #expect(content.contains("## Overnight (12am–6am)\n\n1 captures across NightApp."))
        #expect(content.contains("## Morning (6am–12pm)\n\n500 captures across MorningApp."))
    }
}

private enum TestError: Error {
    case invalidDate
}
