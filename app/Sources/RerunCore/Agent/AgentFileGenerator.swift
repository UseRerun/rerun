import Foundation
import os

public struct AgentFileGenerator: Sendable {
    private let baseURL: URL
    private let summaryProvider: @Sendable ([Capture], String) async -> String?
    private static let logger = Logger(subsystem: "com.rerun", category: "AgentFileGenerator")

    public init(baseURL: URL? = nil) {
        self.init(baseURL: baseURL, summaryProvider: Self.defaultSummary)
    }

    init(
        baseURL: URL? = nil,
        summaryProvider: @escaping @Sendable ([Capture], String) async -> String?
    ) {
        self.baseURL = baseURL ?? RerunHome.baseURL()
        self.summaryProvider = summaryProvider
    }

    // MARK: - today.md

    public func generateTodayMd(db: DatabaseManager) async throws {
        let cal = Calendar.current
        let now = Date()
        let midnight = cal.startOfDay(for: now)
        let sinceStr = Self.iso8601(midnight)

        let count = try await db.captureCount(since: sinceStr)
        let topApps = try await db.topApps(since: sinceStr)
        let topURLs = try await db.topURLs(since: sinceStr)
        let captures = try await db.fetchCaptures(since: sinceStr, limit: nil)

        // Bucket into time blocks
        let overnight = captures.filter { Self.hourOfCapture($0) < 6 }
        let morning = captures.filter { Self.hourOfCapture($0) >= 6 && Self.hourOfCapture($0) < 12 }
        let afternoon = captures.filter { Self.hourOfCapture($0) >= 12 && Self.hourOfCapture($0) < 18 }
        let evening = captures.filter { Self.hourOfCapture($0) >= 18 }

        // Summarize
        let overallSummary = await summaryProvider(captures, "today's full activity")
        let overnightSummary = await summaryProvider(overnight, "overnight (12am–6am)")
        let morningSummary = await summaryProvider(morning, "morning (6am–12pm)")
        let afternoonSummary = await summaryProvider(afternoon, "afternoon (12pm–6pm)")
        let eveningSummary = await summaryProvider(evening, "evening (6pm–midnight)")

        // Build markdown
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let dateStr = dateFormatter.string(from: now)
        let periodStr = Self.dateOnly(now)

        var md = """
            ---
            generated: \(Self.iso8601(now))
            period: \(periodStr)
            captures: \(count)
            ---

            # Today — \(dateStr)

            """

        // Overall summary
        if let summary = overallSummary {
            md += "## Summary\n\n\(summary)\n\n"
        } else if count > 0 {
            let appList = topApps.prefix(5).map(\.appName).joined(separator: ", ")
            md += "## Summary\n\n\(count) captures across \(appList).\n\n"
        } else {
            md += "## Summary\n\nNo activity captured today.\n\n"
        }

        // Time blocks
        md += Self.timeBlockSection("Overnight (12am–6am)", captures: overnight, summary: overnightSummary)
        md += Self.timeBlockSection("Morning (6am–12pm)", captures: morning, summary: morningSummary)
        md += Self.timeBlockSection("Afternoon (12pm–6pm)", captures: afternoon, summary: afternoonSummary)
        md += Self.timeBlockSection("Evening (6pm–midnight)", captures: evening, summary: eveningSummary)

        // Apps table
        if !topApps.isEmpty {
            md += "## Apps\n\n"
            md += "| App | Captures |\n|-----|----------|\n"
            for app in topApps {
                md += "| \(app.appName) | \(app.count) |\n"
            }
            md += "\n"
        }

        // URLs
        if !topURLs.isEmpty {
            md += "## Key URLs\n\n"
            for url in topURLs.prefix(15) {
                md += "- \(url.url) (\(url.count) captures)\n"
            }
            md += "\n"
        }

        try writeFile(md, name: "today.md")
        Self.logger.info("Generated today.md (\(count) captures)")
    }

    // MARK: - index.md

    public func generateIndexMd(db: DatabaseManager) async throws {
        let now = Date()
        let count = try await db.captureCount()
        let oldest = try await db.oldestCaptureTimestamp()
        let newest = try await db.newestCaptureTimestamp()

        let oldestDate = oldest.flatMap { Self.dateOnlyFromISO($0) } ?? "—"
        let newestDate = newest.flatMap { Self.dateOnlyFromISO($0) } ?? "—"

        let countFormatted = Self.formatNumber(count)

        let md = """
            ---
            generated: \(Self.iso8601(now))
            total_captures: \(count)
            oldest_capture: \(oldest ?? "~")
            newest_capture: \(newest ?? "~")
            ---

            # Rerun Index

            Local screen memory. This directory contains captured text from your screen.

            ## Quick Access

            - [Today's Activity](today.md)
            - [Captures](captures/)

            ## Structure

            - `today.md` — Rolling daily summary (updated every 30 min)
            - `index.md` — This file (updated every hour)
            - `captures/YYYY/MM/DD/HH-MM-SS.md` — Individual captures

            ## Stats

            - **Total captures:** \(countFormatted)
            - **Date range:** \(oldestDate) to \(newestDate)
            - **Last updated:** \(Self.humanDateTime(now))

            """

        try writeFile(md, name: "index.md")
        Self.logger.info("Generated index.md (\(count) total captures)")
    }

    // MARK: - File Writing

    private func writeFile(_ content: String, name: String) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let fileURL = baseURL.appendingPathComponent(name)
        // Trim leading whitespace from heredoc-style indentation
        let trimmed = content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let s = String(line)
                // Remove exactly the leading indentation (12 spaces from Swift heredoc)
                if s.hasPrefix("            ") {
                    return String(s.dropFirst(12))
                }
                return s
            }
            .joined(separator: "\n")
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Summarization

    private static func defaultSummary(captures: [Capture], context: String) async -> String? {
        guard !captures.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await summarizeWithLLM(captures: captures, context: context)
        }
        #endif

        return nil
    }

    // MARK: - Helpers

    private static func timeBlockSection(_ title: String, captures: [Capture], summary: String?) -> String {
        var section = "## \(title)\n\n"
        if captures.isEmpty {
            section += "No activity.\n\n"
        } else if let summary {
            section += "\(summary)\n\n"
        } else {
            // Structured-only: list unique apps
            let apps = uniqueApps(from: captures)
            section += "\(captures.count) captures across \(apps.joined(separator: ", ")).\n\n"
        }
        return section
    }

    private static func uniqueApps(from captures: [Capture]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for c in captures {
            if seen.insert(c.appName).inserted {
                result.append(c.appName)
            }
        }
        return result
    }

    private static func hourOfCapture(_ capture: Capture) -> Int {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: capture.timestamp) else { return 0 }
        return Calendar.current.component(.hour, from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func dateOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private static func dateOnlyFromISO(_ iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return String(iso.prefix(10)) }
        return dateOnly(date)
    }

    private static func humanDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }

    private static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func buildPromptData(from captures: [Capture], maxSamples: Int = 20) -> String {
        let apps = uniqueApps(from: captures)
        let titles = Array(Set(captures.compactMap(\.windowTitle))).prefix(15)
        let urls = Array(Set(captures.compactMap(\.url))).prefix(10)

        var data = "Apps used: \(apps.joined(separator: ", "))\n"

        if !titles.isEmpty {
            data += "Window titles: \(titles.joined(separator: "; "))\n"
        }
        if !urls.isEmpty {
            data += "URLs visited: \(urls.joined(separator: ", "))\n"
        }

        // Sample text snippets
        let stride = max(1, captures.count / maxSamples)
        var samples: [String] = []
        for i in Swift.stride(from: 0, to: captures.count, by: stride) {
            let snippet = String(captures[i].textContent.prefix(200))
                .replacingOccurrences(of: "\n", with: " ")
            samples.append(snippet)
            if samples.count >= maxSamples { break }
        }
        if !samples.isEmpty {
            data += "Sample content:\n"
            for s in samples {
                data += "- \(s)\n"
            }
        }

        return data
    }
}

// MARK: - Foundation Models (macOS 26+)

#if canImport(FoundationModels)
import FoundationModels

extension AgentFileGenerator {
    @available(macOS 26, *)
    private static func summarizeWithLLM(captures: [Capture], context: String) async -> String? {
        do {
            let session = LanguageModelSession()
            let data = Self.buildPromptData(from: captures)
            let prompt = """
                Summarize this screen activity for a \(context) period. \
                Write 2-3 concise sentences describing what the user was working on. \
                Focus on tasks and topics, not raw data. Don't mention capture counts.

                \(data)
                """
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Self.logger.warning("LLM summarization failed: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
