import Foundation

// MARK: - Request / Response Types

public struct SearchRequest: Sendable {
    public let query: String
    public let app: String?
    public let since: String?
    public let limit: Int
    public let mode: HybridSearch.SearchMode
    public let parsedQuery: ParsedQuery?

    public init(
        query: String,
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20,
        mode: HybridSearch.SearchMode = .hybrid,
        parsedQuery: ParsedQuery? = nil
    ) {
        self.query = query
        self.app = app
        self.since = since
        self.limit = limit
        self.mode = mode
        self.parsedQuery = parsedQuery
    }
}

public struct SearchResponse: Sendable {
    public let parsed: ParsedQuery
    public let hits: [SearchHit]
    public let summary: ActivitySummary?
}

public struct SearchHit: Sendable {
    public let capture: Capture
    public let score: Float
    public let source: HybridSearch.ResultSource
    public let snippet: String
}

public struct ActivitySummary: Sendable {
    public let appFrequency: [AppCount]
    public let workspaces: [String]
    public let facts: [ActivityFact]
}

public struct AppCount: Sendable {
    public let appName: String
    public let count: Int
}

public struct ActivityFact: Sendable {
    public let text: String
    public let appName: String
    public let timestamp: String
    public let score: Int
    public let occurrences: Int
}

// MARK: - Service

public struct SearchService: Sendable {
    private let db: DatabaseManager
    private let embedder: EmbeddingGenerator
    private let parser: QueryParser
    private let hybridSearch: HybridSearch

    public init(db: DatabaseManager) {
        self.db = db
        self.embedder = EmbeddingGenerator()
        self.parser = QueryParser()
        self.hybridSearch = HybridSearch()
    }

    // MARK: - Context Building

    /// Formats captures as structured text blocks for LLM context.
    /// Each capture becomes a metadata line + content, separated by `---`.
    public static func buildContext(from captures: [Capture], maxTextLength: Int = 1500) -> String {
        let formatter = ISO8601DateFormatter()
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short

        var blocks: [String] = []
        for capture in captures {
            var lines: [String] = []

            // Metadata line: [relative_time, AppName]
            let timeStr: String
            if let date = formatter.date(from: capture.timestamp) {
                timeStr = relative.localizedString(for: date, relativeTo: Date())
            } else {
                timeStr = String(capture.timestamp.prefix(16))
            }
            lines.append("[\(timeStr), \(capture.appName)]")

            if let title = capture.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                lines.append("Window: \(title)")
            }
            if let url = capture.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                lines.append("URL: \(url)")
            }

            // Normalize and truncate content
            let content = capture.textContent
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !content.isEmpty {
                let truncated = content.count > maxTextLength
                    ? String(content.prefix(maxTextLength)).truncatedAtWordBoundary()
                    : content
                lines.append("Content: \(truncated)")
            }

            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n---\n")
    }

    private static let browserApps = [
        "Safari", "Chrome", "Firefox", "Arc", "Brave", "Edge", "Opera", "Dia"
    ]

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        let parsed: ParsedQuery
        if let provided = request.parsedQuery {
            parsed = provided
        } else {
            parsed = await parser.parseBestEffort(request.query)
        }

        let effectiveApp = request.app ?? parsed.appFilter
        let effectiveSince = request.since ?? parsed.since
        let isBrowserQuery = effectiveApp?.lowercased() == "browser"

        var hits: [SearchHit]
        if parsed.searchTerms.isEmpty {
            if isBrowserQuery {
                hits = try await fetchRecent(
                    apps: Self.browserApps, since: effectiveSince, limit: request.limit, parsed: parsed
                )
            } else {
                hits = try await fetchRecent(
                    app: effectiveApp, since: effectiveSince, limit: request.limit, parsed: parsed
                )
            }
        } else {
            let searchApp = isBrowserQuery ? nil : effectiveApp
            let scored = try await hybridSearch.search(
                query: parsed.effectiveQuery,
                mode: request.mode,
                app: searchApp,
                since: effectiveSince,
                limit: request.limit,
                db: db,
                embedder: embedder
            )
            var results = scored.map { result in
                SearchHit(
                    capture: result.capture,
                    score: result.score,
                    source: result.source,
                    snippet: Self.makeSnippet(result.capture, parsed: parsed)
                )
            }
            if isBrowserQuery {
                let browserSet = Set(Self.browserApps.map { $0.lowercased() })
                results = results.filter { browserSet.contains($0.capture.appName.lowercased()) }
            }
            hits = results
            // Keyword search returned nothing — fall back to recency
            if hits.isEmpty {
                if isBrowserQuery {
                    hits = try await fetchRecent(
                        apps: Self.browserApps, since: effectiveSince, limit: request.limit, parsed: parsed
                    )
                } else {
                    hits = try await fetchRecent(
                        app: effectiveApp, since: effectiveSince, limit: request.limit, parsed: parsed
                    )
                }
            }
        }

        let summary = buildSummary(from: hits.map(\.capture), appFilter: effectiveApp)

        return SearchResponse(parsed: parsed, hits: hits, summary: summary)
    }
}

// MARK: - Recency Fetch

extension SearchService {
    private func fetchRecent(
        app: String?, since: String?, limit: Int, parsed: ParsedQuery
    ) async throws -> [SearchHit] {
        let captures = try await db.fetchCaptures(app: app, since: since, limit: limit)
        return makeHits(from: captures, parsed: parsed)
    }

    private func fetchRecent(
        apps: [String], since: String?, limit: Int, parsed: ParsedQuery
    ) async throws -> [SearchHit] {
        let captures = try await db.fetchCaptures(apps: apps, since: since, limit: limit)
        return makeHits(from: captures, parsed: parsed)
    }

    private func makeHits(from captures: [Capture], parsed: ParsedQuery) -> [SearchHit] {
        let filtered = filterNoise(captures, parsed: parsed)
        return filtered.map { capture in
            SearchHit(
                capture: capture,
                score: 0,
                source: .keyword,
                snippet: Self.makeSnippet(capture, parsed: parsed)
            )
        }
    }
}

// MARK: - Snippet

extension SearchService {
    private static func makeSnippet(_ capture: Capture, parsed: ParsedQuery) -> String {
        let snippetQuery = parsed.searchTerms.joined(separator: " ")
        return SearchResult.makeSnippet(
            from: capture.textContent,
            query: snippetQuery.isEmpty ? capture.appName : snippetQuery
        )
    }
}

// MARK: - Noise Filtering

extension SearchService {
    private static let noiseApps: Set<String> = [
        "RerunDev",
        "universalAccessAuthWarn",
    ]

    private func filterNoise(_ captures: [Capture], parsed: ParsedQuery) -> [Capture] {
        guard parsed.searchTerms.isEmpty, parsed.appFilter == nil else { return captures }
        let filtered = captures.filter { !Self.noiseApps.contains($0.appName) }
        return filtered.isEmpty ? captures : filtered
    }
}

// MARK: - Activity Summary

extension SearchService {
    /// Build an ActivitySummary from captures. Public so callers (e.g. CLI `ask`)
    /// can extract facts from keyword results, not just broad queries.
    public static func buildActivitySummary(from captures: [Capture], appFilter: String?) -> ActivitySummary {
        ActivitySummary(
            appFrequency: appFilter == nil ? summarizeApps(from: captures) : [],
            workspaces: extractWorkspaces(from: captures),
            facts: extractFacts(from: captures, appFilter: appFilter)
        )
    }

    private func buildSummary(from captures: [Capture], appFilter: String?) -> ActivitySummary {
        Self.buildActivitySummary(from: captures, appFilter: appFilter)
    }

    private static func summarizeApps(from captures: [Capture]) -> [AppCount] {
        Dictionary(grouping: captures, by: \.appName)
            .map { AppCount(appName: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.appName < rhs.appName }
                return lhs.count > rhs.count
            }
            .prefix(3)
            .map { $0 }
    }

    private static func extractWorkspaces(from captures: [Capture]) -> [String] {
        let workspacePattern = /^([A-Z]\s+)?([A-Za-z0-9-]+)\s+Repo settings\b/
        var seen = Set<String>()
        var workspaces: [String] = []

        for capture in captures {
            for line in capture.textContent.split(separator: "\n").map(String.init) {
                guard let match = line.firstMatch(of: workspacePattern) else { continue }
                let workspace = String(match.2)
                let key = workspace.lowercased()
                guard seen.insert(key).inserted else { continue }
                workspaces.append(workspace)
            }
        }

        return workspaces
    }
}

// MARK: - Fact Extraction

extension SearchService {
    private static let noiseLines: Set<String> = [
        "activity",
        "add a follow up",
        "add repository",
        "all files",
        "building for debugging...",
        "close terminal 1",
        "conductor",
        "enter your plan adjustments here...",
        "emptyfavicon",
        "new terminal",
        "notifications alt+t",
        "recent menu",
        "run",
        "setup",
        "terminal",
        "terminal input",
        "workspaces",
    ]

    private static let taskSignalTerms: Set<String> = [
        "accessibility",
        "audit",
        "bug",
        "build",
        "chat",
        "crash",
        "debug",
        "dev app",
        "error",
        "feat:",
        "fix",
        "fix:",
        "hotkey",
        "issue",
        "location",
        "parser",
        "path",
        "permission",
        "review",
        "search",
        "show",
        "snippet",
        "source",
        "summary",
        "tcc",
        "test",
    ]

    private static let commitPrefixes = [
        "feat:",
        "fix:",
        "refactor:",
        "build:",
        "chore:",
        "docs:",
        "style:",
        "perf:",
        "test:",
        "ci:",
    ]

    private static func extractFacts(from captures: [Capture], appFilter: String?) -> [ActivityFact] {
        var grouped: [String: FactAccumulator] = [:]

        for capture in captures {
            for candidate in candidateLines(from: capture) {
                guard isUsefulFactCandidate(candidate.text, appFilter: appFilter, appName: capture.appName) else { continue }

                let score = scoreFactCandidate(candidate.text, isWindowTitle: candidate.isWindowTitle)
                guard score >= 4 else { continue }

                let key = normalizeFactKey(candidate.text)
                if var existing = grouped[key] {
                    existing.merge(
                        text: candidate.text,
                        appName: capture.appName,
                        timestamp: capture.timestamp,
                        score: score
                    )
                    grouped[key] = existing
                } else {
                    grouped[key] = FactAccumulator(
                        text: candidate.text,
                        appName: capture.appName,
                        timestamp: capture.timestamp,
                        score: score,
                        occurrences: 1
                    )
                }
            }
        }

        let repetitionLimit = max(2, captures.count / 4)

        // Merge entries where one key is a prefix of another (truncated window titles)
        let keys = Array(grouped.keys).sorted { $0.count < $1.count }
        for shortKey in keys {
            guard grouped[shortKey] != nil else { continue }
            for longKey in keys where longKey.count > shortKey.count {
                if longKey.hasPrefix(shortKey), grouped[longKey] != nil {
                    // Merge short into long (prefer the fuller text)
                    grouped[longKey]!.merge(
                        text: grouped[shortKey]!.text,
                        appName: grouped[shortKey]!.appName,
                        timestamp: grouped[shortKey]!.timestamp,
                        score: grouped[shortKey]!.score
                    )
                    grouped.removeValue(forKey: shortKey)
                    break
                }
            }
        }

        return grouped.values
            .compactMap { accumulator in
                if accumulator.occurrences > repetitionLimit && accumulator.score < 8 {
                    return nil
                }
                guard accumulator.effectiveScore >= 4 else { return nil }
                return accumulator.fact()
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.timestamp > rhs.timestamp }
                return lhs.score > rhs.score
            }
            .prefix(6)
            .map { $0 }
    }

    private struct CandidateLine {
        let text: String
        let isWindowTitle: Bool
    }

    private static func candidateLines(from capture: Capture) -> [CandidateLine] {
        var lines: [CandidateLine] = []
        if let title = capture.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            // Split "Page Title — Site Name" style window titles
            let parts = title.split(separator: " — ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                for part in parts where part.count >= 3 {
                    lines.append(CandidateLine(text: String(part), isWindowTitle: true))
                }
            } else {
                lines.append(CandidateLine(text: title, isWindowTitle: true))
            }
        }
        lines.append(contentsOf: capture.textContent.split(separator: "\n").map {
            CandidateLine(text: $0.trimmingCharacters(in: .whitespacesAndNewlines), isWindowTitle: false)
        })
        return lines
    }

    private static func isUsefulFactCandidate(_ line: String, appFilter: String?, appName: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        guard trimmed.count >= 4, trimmed.count <= 140 else { return false }
        guard !Self.noiseLines.contains(lower) else { return false }
        guard lower != appName.lowercased() else { return false }
        guard lower != appFilter?.lowercased() else { return false }
        guard trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
        guard !lower.contains("repo settings") else { return false }
        guard !lower.contains("new workspace from") else { return false }
        guard !lower.contains("ask to make changes") else { return false }
        guard !lower.contains("planning build") else { return false }
        guard !lower.contains("write swift-version") else { return false }
        guard !lower.hasPrefix("issues ·") else { return false }
        guard !lower.hasPrefix("home /") else { return false }
        guard !lower.hasPrefix("brands") else { return false }
        guard !lower.hasPrefix("shpigford/") else { return false }
        guard !lower.hasPrefix("+"), !lower.hasPrefix("-") else { return false }

        // Tab-bar mash: "0 Dashboard — Rumored EmptyFavicon Filaments - 3DP.tools Home — Faire"
        // These are OCR of browser tab bars — many short fragments separated by spaces
        let dashCount = trimmed.components(separatedBy: " — ").count
            + trimmed.components(separatedBy: " - ").count - 1
        if dashCount >= 3 { return false }

        return true
    }

    private static func scoreFactCandidate(_ line: String, isWindowTitle: Bool) -> Int {
        let lower = line.lowercased()
        let words = normalizedWords(in: line)
        let wordCount = words.count
        var score = 0

        // Window titles are high-signal — they tell you what was active
        if isWindowTitle {
            score += 3
        }

        if Self.commitPrefixes.contains(where: { lower.hasPrefix($0) }) {
            score += 6
        }
        if Self.taskSignalTerms.contains(where: { lower.contains($0) }) {
            score += 3
        }
        if lower.hasSuffix(".") || lower.hasSuffix("!") || lower.hasSuffix("?") {
            score += 2
        }
        if wordCount >= 4 && wordCount <= 18 {
            score += 2
        } else if wordCount >= 3 {
            score += 1
        }
        if lower.contains("/") || lower.contains(".swift") || lower.contains(".app") {
            score += 2
        }
        if lower.contains(" i ") || lower.contains(" we ") || lower.contains("it's") || lower.contains("lets") || lower.contains("let's") {
            score += 1
        }
        // Title-case phrases (e.g. "Challenge Page", "Shop Manager") suggest named things
        if !isWindowTitle && line.first?.isUppercase == true && wordCount >= 2 && wordCount <= 6 {
            let titleCaseWords = line.split(separator: " ").filter { $0.first?.isUppercase == true }
            if titleCaseWords.count >= 2 {
                score += 1
            }
        }

        return score
    }

    private static func normalizedWords(in line: String) -> [String] {
        line
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: .punctuationCharacters)
            }
            .filter { !$0.isEmpty }
    }

    private static let trailingStopWords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "but", "is", "was", "with"
    ]

    private static func normalizeFactKey(_ line: String) -> String {
        // Strip trailing ellipsis before normalizing so truncated titles merge with full ones
        let cleaned = line.replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var words = normalizedWords(in: cleaned)
        // Strip trailing articles/prepositions so "I want a" and "I want an" merge
        while let last = words.last, trailingStopWords.contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}

// MARK: - Fact Accumulator (private)

private struct FactAccumulator {
    var text: String
    var appName: String
    var timestamp: String
    var score: Int
    var occurrences: Int

    var effectiveScore: Int {
        score - max(0, occurrences - 1)
    }

    mutating func merge(text: String, appName: String, timestamp: String, score: Int) {
        occurrences += 1

        if timestamp > self.timestamp {
            self.timestamp = timestamp
            self.appName = appName
        }

        if score > self.score || (score == self.score && text.count > self.text.count) {
            self.text = text
            self.score = score
        }
    }

    func fact() -> ActivityFact {
        ActivityFact(
            text: text,
            appName: appName,
            timestamp: timestamp,
            score: effectiveScore,
            occurrences: occurrences
        )
    }
}

// MARK: - String Helpers

extension String {
    /// Truncates at the last word boundary before the current length, appending "..."
    func truncatedAtWordBoundary() -> String {
        guard let lastSpace = self.lastIndex(of: " ") else { return self }
        return String(self[..<lastSpace]) + "..."
    }
}
