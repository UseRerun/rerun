import ArgumentParser
import Foundation
import RerunCore

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search captured screen text.",
        discussion: """
            Examples:
              rerun search "stripe"                            Search all captures
              rerun search "API docs" --app Safari             Filter by app
              rerun search "meeting" --since 2d                Last 2 days
              rerun search "deploy" --since 1h --json          JSON output
              rerun search "payment API" --mode semantic       Semantic search only
              rerun search "what was I looking at in Safari"   NL query parsing
            """
    )

    @Argument(help: "Search query (keywords or natural language).")
    var query: String

    @Option(name: .long, help: "Filter by app name (case-insensitive).")
    var app: String? = nil

    @Option(name: .long, help: "Only results after this time (e.g. 1h, 2d, 1w, 2026-03-19).")
    var since: String? = nil

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int = 20

    @Option(name: .long, help: "Search mode: keyword, semantic, or hybrid (default).")
    var mode: String = "hybrid"

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

        guard let searchMode = HybridSearch.SearchMode(rawValue: mode) else {
            print("Invalid --mode value: \(mode). Use: keyword, semantic, or hybrid")
            throw ExitCode(2)
        }

        // Parse NL query for implicit filters
        let parser = QueryParser()
        let parsed = await parser.parseBestEffort(query)

        // Explicit CLI flags override parsed values
        var effectiveSince: String? = nil
        if let since {
            guard let parsedSince = SearchTimeParser.parseSince(since) else {
                print("Invalid --since value: \(since). Use: 1h, 2d, 1w, 2026-03-19, or ISO8601")
                throw ExitCode(2)
            }
            effectiveSince = parsedSince
        } else {
            effectiveSince = parsed.since
        }

        let effectiveApp = app ?? parsed.appFilter
        let effectiveQuery = parsed.effectiveQuery

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let hybridSearch = HybridSearch()
        let embedder = EmbeddingGenerator()

        let scored = try await hybridSearch.search(
            query: effectiveQuery,
            mode: searchMode,
            app: effectiveApp,
            since: effectiveSince,
            limit: limit,
            db: db,
            embedder: embedder
        )

        guard !scored.isEmpty else {
            if formatter.useJSON {
                try formatter.printJSON([SearchResult]())
            } else {
                print("No results for \"\(query)\"")
            }
            throw ExitCode(4)
        }

        let searchResults = scored.map { result in
            SearchResult(
                capture: result.capture,
                snippet: SearchResult.makeSnippet(from: result.capture.textContent, query: effectiveQuery)
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
