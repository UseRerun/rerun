import ArgumentParser
import Foundation
import RerunCore

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search captured screen text.",
        discussion: """
            Examples:
              rerun search "stripe"                       Search all captures
              rerun search "API docs" --app Safari        Filter by app
              rerun search "meeting" --since 2d           Last 2 days
              rerun search "deploy" --since 1h --json     JSON output
            """
    )

    @Argument(help: "Search query (keywords).")
    var query: String

    @Option(name: .long, help: "Filter by app name (case-insensitive).")
    var app: String? = nil

    @Option(name: .long, help: "Only results after this time (e.g. 1h, 2d, 1w, 2026-03-19).")
    var since: String? = nil

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        let formatter = OutputFormatter(json: json, noColor: noColor)

        guard limit > 0 else {
            print("Invalid --limit value: \(limit). Must be greater than 0.")
            throw ExitCode(2)
        }

        var sinceISO: String? = nil
        if let since {
            guard let parsed = SearchTimeParser.parseSince(since) else {
                print("Invalid --since value: \(since). Use: 1h, 2d, 1w, 2026-03-19, or ISO8601")
                throw ExitCode(2)
            }
            sinceISO = parsed
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let results = try await db.searchCaptures(
            query: query,
            app: app,
            since: sinceISO,
            limit: limit
        )

        guard !results.isEmpty else {
            if formatter.useJSON {
                try formatter.printJSON([SearchResult]())
            } else {
                print("No results for \"\(query)\"")
            }
            throw ExitCode(4)
        }

        let searchResults = results.map { capture in
            SearchResult(
                capture: capture,
                snippet: SearchResult.makeSnippet(from: capture.textContent, query: query)
            )
        }

        if formatter.useJSON {
            try formatter.printJSON(searchResults)
        } else {
            printHuman(searchResults)
        }
    }

    // MARK: - Output

    private func printHuman(_ results: [SearchResult]) {
        for (i, result) in results.enumerated() {
            if i > 0 { print("") }

            var header = formatTimestamp(result.timestamp)
            header += "  \(result.appName)"
            if let title = result.windowTitle {
                header += " — \(title)"
            }
            print(header)

            if let url = result.url {
                print("  \(url)")
            }
            print("  \(result.snippet)")
        }
        print("\n\(results.count) result\(results.count == 1 ? "" : "s")")
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
