import ArgumentParser
import Foundation
import RerunCore

struct SummaryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "summary",
        abstract: "Show activity summary.",
        discussion: """
            Examples:
              rerun summary                   General summary
              rerun summary --today           Today's activity
              rerun summary --today --json    Today's activity as JSON
            """
    )

    @Flag(name: .long, help: "Show today's summary.")
    var today = false

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        let formatter = OutputFormatter(json: json, noColor: noColor)
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())

        if today {
            try await showToday(db: db, formatter: formatter)
        } else {
            try await showGeneral(db: db, formatter: formatter)
        }
    }

    private func showToday(db: DatabaseManager, formatter: OutputFormatter) async throws {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date())
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let sinceStr = isoFormatter.string(from: midnight)

        let count = try await db.captureCount(since: sinceStr)
        let oldest = try await db.oldestCaptureTimestamp(since: sinceStr)
        let newest = try await db.newestCaptureTimestamp(since: sinceStr)
        let topApps = try await db.topApps(since: sinceStr)

        if formatter.useJSON {
            let result = SummaryResult(
                totalCaptures: count,
                apps: topApps.map { AppCount(name: $0.appName, count: $0.count) },
                oldestCapture: oldest,
                newestCapture: newest
            )
            try formatter.printJSON(result)
        } else if count == 0 {
            print("No captures today.")
        } else {
            print("Today: \(count) capture\(count == 1 ? "" : "s")")
            if let oldest, let newest {
                print("  \(formatTime(oldest)) – \(formatTime(newest))")
            }
            print("")
            for app in topApps {
                print("  \(app.appName)\t\(app.count)")
            }
        }
    }

    private func showGeneral(db: DatabaseManager, formatter: OutputFormatter) async throws {
        let count = try await db.captureCount()
        let oldest = try await db.oldestCaptureTimestamp()
        let newest = try await db.newestCaptureTimestamp()
        let topApps = try await db.topApps()

        if formatter.useJSON {
            let result = SummaryResult(
                totalCaptures: count,
                apps: topApps.map { AppCount(name: $0.appName, count: $0.count) },
                oldestCapture: oldest,
                newestCapture: newest
            )
            try formatter.printJSON(result)
        } else if count == 0 {
            print("No captures yet.")
        } else {
            print("\(count) capture\(count == 1 ? "" : "s")")
            if let oldest, let newest {
                print("  \(formatDate(oldest)) – \(formatDate(newest))")
            }
            if !topApps.isEmpty {
                print("\nTop apps:")
                for app in topApps {
                    print("  \(app.appName)\t\(app.count)")
                }
            }
        }
    }

    private func formatTime(_ iso: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: iso) else {
            return String(iso.prefix(16))
        }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func formatDate(_ iso: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: iso) else {
            return String(iso.prefix(10))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

private struct SummaryResult: Codable {
    let totalCaptures: Int
    let apps: [AppCount]
    let oldestCapture: String?
    let newestCapture: String?
}

private struct AppCount: Codable {
    let name: String
    let count: Int
}
