import ArgumentParser
import Foundation
import RerunCore

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export captures in various formats.",
        discussion: """
            Examples:
              rerun export                                Export all as JSONL
              rerun export --format csv --since 1w        Last week as CSV
              rerun export --format md --since 1d          Last day as Markdown
              rerun export --format jsonl > captures.jsonl  Redirect to file
            """
    )

    @Option(name: .long, help: "Output format: jsonl, csv, or md.")
    var format: String = "jsonl"

    @Option(name: .long, help: "Only captures after this time (e.g. 1h, 2d, 1w).")
    var since: String? = nil

    @Option(name: .long, help: "Maximum captures to export.")
    var limit: Int? = nil

    @Flag(name: .long, help: "Output as JSON (equivalent to --format jsonl).")
    var json = false

    func run() async throws {
        let effectiveFormat = json ? "jsonl" : format

        guard ["jsonl", "csv", "md"].contains(effectiveFormat) else {
            print("Invalid --format value: \(format). Use: jsonl, csv, or md")
            throw ExitCode(2)
        }

        var effectiveSince: String? = nil
        if let since {
            guard let parsed = SearchTimeParser.parseSince(since) else {
                print("Invalid --since value: \(since). Use: 1h, 2d, 1w, 2026-03-19, or ISO8601")
                throw ExitCode(2)
            }
            effectiveSince = parsed
        }

        if let limit, limit <= 0 {
            print("Invalid --limit value: \(limit). Must be greater than 0")
            throw ExitCode(2)
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let captures = try await db.fetchCaptures(since: effectiveSince, limit: limit)

        guard !captures.isEmpty else {
            if effectiveFormat == "jsonl" {
                // Empty output for JSONL is fine
            } else {
                fputs("No captures found.\n", stderr)
            }
            throw ExitCode(4)
        }

        switch effectiveFormat {
        case "jsonl":
            try exportJSONL(captures)
        case "csv":
            exportCSV(captures)
        case "md":
            exportMarkdown(captures)
        default:
            break
        }
    }

    private func exportJSONL(_ captures: [Capture]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for capture in captures {
            let data = try encoder.encode(capture)
            if let line = String(data: data, encoding: .utf8) {
                print(line)
            }
        }
    }

    private func exportCSV(_ captures: [Capture]) {
        print("id,timestamp,appName,windowTitle,url,textSource,textContent")
        for capture in captures {
            let fields = [
                capture.id,
                capture.timestamp,
                capture.appName,
                capture.windowTitle ?? "",
                capture.url ?? "",
                capture.textSource,
                String(capture.textContent.prefix(500))
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " "),
            ]
            let escaped = fields.map { csvEscape($0) }
            print(escaped.joined(separator: ","))
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func exportMarkdown(_ captures: [Capture]) {
        for (i, capture) in captures.enumerated() {
            if i > 0 { print("\n---\n") }

            var frontmatter = "---\n"
            frontmatter += "id: \(capture.id)\n"
            frontmatter += "timestamp: \(capture.timestamp)\n"
            frontmatter += "app: \(capture.appName)\n"
            if let bundleId = capture.bundleId {
                frontmatter += "bundle_id: \(bundleId)\n"
            }
            if let title = capture.windowTitle {
                frontmatter += "window: \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
            }
            if let url = capture.url {
                frontmatter += "url: \(url)\n"
            }
            frontmatter += "source: \(capture.textSource)\n"
            frontmatter += "trigger: \(capture.captureTrigger)\n"
            frontmatter += "---\n"
            print(frontmatter)
            print(capture.textContent)
        }
    }
}
