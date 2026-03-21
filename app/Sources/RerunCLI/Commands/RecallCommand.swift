import ArgumentParser
import Foundation
import RerunCore

struct RecallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recall",
        abstract: "Fetch the capture closest to a given time.",
        discussion: """
            Examples:
              rerun recall --at 30m                    30 minutes ago
              rerun recall --at 2h                     2 hours ago
              rerun recall --at 2026-03-19             A specific date
              rerun recall --at 2026-03-19T15:00:00Z   A specific time
            """
    )

    @Option(name: .long, help: "Time to recall (e.g. 30m, 1h, 2d, 2026-03-19, ISO8601).")
    var at: String

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        let formatter = OutputFormatter(json: json, noColor: noColor)

        guard let timestamp = SearchTimeParser.parseSince(at) else {
            print("Invalid --at value: \(at). Use: 30m, 1h, 2d, 2026-03-19, or ISO8601")
            throw ExitCode(2)
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())

        guard let capture = try await db.fetchCapture(closestTo: timestamp) else {
            if formatter.useJSON {
                print("null")
            } else {
                print("No captures found.")
            }
            throw ExitCode(4)
        }

        if formatter.useJSON {
            try formatter.printJSON(capture)
        } else {
            printHuman(capture)
        }
    }

    private func printHuman(_ capture: Capture) {
        var header = formatTimestamp(capture.timestamp)
        header += "  \(capture.appName)"
        if let title = capture.windowTitle {
            header += " — \(title)"
        }
        print(header)

        if let url = capture.url {
            print("  \(url)")
        }

        let preview = String(capture.textContent.prefix(300))
        print("  \(preview)")
    }

    private func formatTimestamp(_ iso: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: iso) else {
            return String(iso.prefix(16))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }
}
