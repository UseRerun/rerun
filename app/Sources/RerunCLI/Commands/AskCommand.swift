import ArgumentParser
import Foundation
import RerunCore
import MLXLLM
import MLXLMCommon
import Hub

struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Ask a question about your screen activity.",
        discussion: """
            Full search + LLM synthesis pipeline using local Gemma model.
            Shows every stage so you can debug answer quality from the terminal.

            Examples:
              rerun ask "What did I chat with Ashley about?"
              rerun ask "What have I been working on today?"
              rerun ask "What was I reading in Safari?" --no-llm
              rerun ask "meetings this week" --json
            """
    )

    @Argument(help: "Natural language question about your screen activity.")
    var question: String

    @Option(name: .long, help: "Filter by app name.")
    var app: String? = nil

    @Option(name: .long, help: "Only results after this time (e.g. 1h, 2d, 1w).")
    var since: String? = nil

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int = 10

    @Flag(name: .long, help: "Skip LLM synthesis, show facts only.")
    var noLlm = false

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        guard limit > 0 else {
            print("Invalid --limit value: \(limit). Must be greater than 0.")
            throw ExitCode(2)
        }

        var effectiveSince: String? = nil
        if let since {
            guard let parsedSince = SearchTimeParser.parseSince(since) else {
                print("Invalid --since value: \(since). Use: 1h, 2d, 1w, or ISO8601")
                throw ExitCode(2)
            }
            effectiveSince = parsedSince
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let service = SearchService(db: db)

        let response = try await service.search(SearchRequest(
            query: question,
            app: app,
            since: effectiveSince,
            limit: limit
        ))

        // Build summary from whatever we got
        let summary: ActivitySummary
        if let s = response.summary {
            summary = s
        } else {
            summary = SearchService.buildActivitySummary(
                from: response.hits.map(\.capture),
                appFilter: response.parsed.appFilter
            )
        }

        // Build capture context for LLM
        let captures = response.hits.map(\.capture)
        let context = SearchService.buildContext(from: captures)

        if json {
            try printJSON(response: response, summary: summary)
            return
        }

        printDiagnostic(response: response, summary: summary, context: context)

        if !noLlm && !captures.isEmpty {
            await printSynthesis(context: context)
        }
    }

    // MARK: - Diagnostic Output

    private func printDiagnostic(
        response: SearchResponse,
        summary: ActivitySummary,
        context: String
    ) {
        // Parsed query
        print("── Parsed ──")
        print("  terms: \(response.parsed.searchTerms)")
        print("  app: \(response.parsed.appFilter ?? "nil")")
        print("  since: \(response.parsed.since ?? "nil")")
        print("  effective: \"\(response.parsed.effectiveQuery)\"")
        print("")

        // Hits summary
        print("── Hits: \(response.hits.count) ──")
        var seenApps: [String: Int] = [:]
        for hit in response.hits {
            seenApps[hit.capture.appName, default: 0] += 1
        }
        for (app, count) in seenApps.sorted(by: { $0.value > $1.value }) {
            print("  \(app): \(count)")
        }
        print("")

        // Top hits (deduplicated by window title)
        print("── Top Hits ──")
        var shownTitles = Set<String>()
        var shown = 0
        for hit in response.hits {
            let key = "\(hit.capture.appName)|\(hit.capture.windowTitle ?? "")"
            guard shownTitles.insert(key).inserted else { continue }
            let time = formatTimestamp(hit.capture.timestamp)
            var line = "  \(time)  \(hit.capture.appName)"
            if let title = hit.capture.windowTitle {
                line += " — \(title)"
            }
            print(line)
            if shown < 3 {
                let snippet = hit.snippet.prefix(120)
                print("    \(snippet)\(hit.snippet.count > 120 ? "..." : "")")
            }
            shown += 1
            if shown >= 5 { break }
        }
        print("")

        // App frequency
        if !summary.appFrequency.isEmpty {
            print("── Apps ──")
            for ac in summary.appFrequency {
                print("  \(ac.appName) (\(ac.count))")
            }
            print("")
        }

        // Workspaces
        if !summary.workspaces.isEmpty {
            print("── Workspaces ──")
            print("  \(summary.workspaces.joined(separator: ", "))")
            print("")
        }

        // Context preview
        let contextLines = context.components(separatedBy: "\n")
        print("── Context (\(contextLines.count) lines, \(context.count) chars) ──")
        for line in contextLines.prefix(8) {
            print("  \(line)")
        }
        if contextLines.count > 8 {
            print("  ... (\(contextLines.count - 8) more lines)")
        }
        print("")
    }

    // MARK: - LLM Synthesis

    private func printSynthesis(context: String) async {
        print("── Answer ──")

        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rerun/models")
        let modelId = "mlx-community/gemma-3-4b-it-qat-4bit"

        do {
            let hub = HubApi(downloadBase: modelsDir)
            let config = ModelConfiguration(id: modelId)
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub, configuration: config
            )

            let instructions = """
                You answer questions about the user's computer activity based ONLY on the data below.

                RULES:
                1. Answer ONLY what was asked — don't summarize everything.
                2. Each entry shows the app in brackets like [time, AppName]. Focus on activities relevant to the question.
                3. Describe what was DONE, not UI chrome that was merely visible on screen. Ignore sidebar labels, empty states, notification badges.
                4. Use natural time references: "Around 2pm...", "Earlier today..."
                5. Never say "capture", "screenshot", "frame", "OCR", or "screen recording".
                6. Write 2-3 sentences, conversationally. Not a bulleted list.
                7. Start with the answer immediately — no preamble like "Based on the data" or "Here's what I found".
                8. If the data doesn't clearly answer the question, say so honestly.

                ACTIVITY DATA:
                \(context)
                """

            let params = GenerateParameters(maxTokens: 512)
            let session = ChatSession(container, instructions: instructions, generateParameters: params)

            // Stream tokens to stdout
            print("  ", terminator: "")
            var response = ""
            for try await token in session.streamResponse(to: question) {
                let cleaned = token
                    .replacingOccurrences(of: "<end_of_turn>", with: "")
                    .replacingOccurrences(of: "<start_of_turn>", with: "")
                    .replacingOccurrences(of: "<bos>", with: "")
                    .replacingOccurrences(of: "<eos>", with: "")
                if !cleaned.isEmpty {
                    print(cleaned, terminator: "")
                    fflush(stdout)
                    response.append(cleaned)
                }
            }
            print("") // newline after streaming

            if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("  (model returned empty response)")
            }
        } catch {
            print("  (MLX synthesis failed: \(error.localizedDescription))")
            print("  Hint: run the daemon first to download the model")
        }
    }

    // MARK: - JSON Output

    private func printJSON(
        response: SearchResponse,
        summary: ActivitySummary
    ) throws {
        struct AskOutput: Encodable {
            let parsed: ParsedOutput
            let hitCount: Int
            let hitsByApp: [String: Int]
            let facts: [FactOutput]
            let workspaces: [String]
            let appFrequency: [AppFreqOutput]
        }
        struct ParsedOutput: Encodable {
            let searchTerms: [String]
            let appFilter: String?
            let since: String?
            let effectiveQuery: String
        }
        struct FactOutput: Encodable {
            let text: String
            let appName: String
            let score: Int
            let occurrences: Int
        }
        struct AppFreqOutput: Encodable {
            let appName: String
            let count: Int
        }

        var hitsByApp: [String: Int] = [:]
        for hit in response.hits {
            hitsByApp[hit.capture.appName, default: 0] += 1
        }

        let output = AskOutput(
            parsed: ParsedOutput(
                searchTerms: response.parsed.searchTerms,
                appFilter: response.parsed.appFilter,
                since: response.parsed.since,
                effectiveQuery: response.parsed.effectiveQuery
            ),
            hitCount: response.hits.count,
            hitsByApp: hitsByApp,
            facts: summary.facts.map { FactOutput(text: $0.text, appName: $0.appName, score: $0.score, occurrences: $0.occurrences) },
            workspaces: summary.workspaces,
            appFrequency: summary.appFrequency.map { AppFreqOutput(appName: $0.appName, count: $0.count) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        print(String(data: data, encoding: .utf8)!)
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
