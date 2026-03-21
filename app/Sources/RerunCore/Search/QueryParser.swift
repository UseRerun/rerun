import Foundation

public struct ParsedQuery: Sendable {
    public let searchTerms: [String]
    public let since: String?
    public let appFilter: String?
    public let rawQuery: String

    public var effectiveQuery: String {
        searchTerms.isEmpty ? rawQuery : searchTerms.joined(separator: " ")
    }
}

public struct QueryParser: Sendable {

    private static let knownApps = [
        "safari", "chrome", "firefox", "terminal", "iterm",
        "vs code", "vscode", "xcode", "slack", "zoom",
        "figma", "notion", "obsidian", "arc", "brave",
        "edge", "opera", "finder", "mail", "messages",
        "discord", "linear", "cursor", "warp",
    ]

    public init() {}

    public func parse(_ query: String, now: Date = Date()) -> ParsedQuery {
        var remaining = query
        let since = extractTime(from: &remaining, now: now)
        let appFilter = extractApp(from: &remaining)
        let terms = remaining
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        return ParsedQuery(
            searchTerms: terms,
            since: since,
            appFilter: appFilter,
            rawQuery: query
        )
    }

    public func parseBestEffort(_ query: String, now: Date = Date()) async -> ParsedQuery {
        let regexParsed = parse(query, now: now)

        #if canImport(FoundationModels)
        if #available(macOS 26, *), let llmParsed = await parseWithLLM(query, now: now) {
            let merged = mergeBestEffort(regex: regexParsed, llm: llmParsed)
            debugLog("parser=foundation-models")
            debugLogParsed(merged)
            return merged
        }
        #endif

        debugLog("parser=regex")
        debugLogParsed(regexParsed)
        return regexParsed
    }

    // MARK: - Time Extraction

    private func extractTime(from query: inout String, now: Date) -> String? {
        let lower = query.lowercased()
        let calendar = Calendar.current

        // "today"
        if let range = lower.range(of: "today") {
            query.removeSubrange(range)
            return iso8601(calendar.startOfDay(for: now))
        }

        // "yesterday"
        if let range = lower.range(of: "yesterday") {
            query.removeSubrange(range)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            return iso8601(calendar.startOfDay(for: yesterday))
        }

        // "this morning"
        if let range = lower.range(of: "this morning") {
            query.removeSubrange(range)
            return iso8601(calendar.startOfDay(for: now))
        }

        // "last week"
        if let range = lower.range(of: "last week") {
            query.removeSubrange(range)
            return iso8601(calendar.date(byAdding: .weekOfYear, value: -1, to: now)!)
        }

        // "last hour"
        if let range = lower.range(of: "last hour") {
            query.removeSubrange(range)
            return iso8601(calendar.date(byAdding: .hour, value: -1, to: now)!)
        }

        // "N days/hours/minutes ago"
        let agoPattern = /(\d+)\s+(minute|hour|day|week)s?\s+ago/
        if let match = lower.firstMatch(of: agoPattern) {
            guard let amount = Int(match.1) else { return nil }
            let unit: Calendar.Component
            switch match.2 {
            case "minute": unit = .minute
            case "hour": unit = .hour
            case "day": unit = .day
            case "week": unit = .weekOfYear
            default: return nil
            }
            query.removeSubrange(match.range)
            return iso8601(calendar.date(byAdding: unit, value: -amount, to: now)!)
        }

        // Named days: "monday", "tuesday", etc.
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (index, dayName) in dayNames.enumerated() {
            if let range = lower.range(of: dayName) {
                query.removeSubrange(range)
                let weekday = index + 1 // Calendar weekday: 1=Sunday
                let todayWeekday = calendar.component(.weekday, from: now)
                var daysBack = todayWeekday - weekday
                if daysBack <= 0 { daysBack += 7 }
                let targetDate = calendar.date(byAdding: .day, value: -daysBack, to: now)!
                return iso8601(calendar.startOfDay(for: targetDate))
            }
        }

        return nil
    }

    // MARK: - App Extraction

    private func extractApp(from query: inout String) -> String? {
        let lower = query.lowercased()

        // "in <app>" or "from <app>"
        let appPattern = /(?:in|from)\s+(\w[\w\s]*?)(?:\s+(?:today|yesterday|last|this|\d)|$)/
        if let match = lower.firstMatch(of: appPattern) {
            let candidate = String(match.1).trimmingCharacters(in: .whitespaces).lowercased()
            if Self.knownApps.contains(candidate) {
                // Remove just the "in/from <app>" part
                let prefixPattern = try! Regex("(?i)(?:in|from)\\s+" + NSRegularExpression.escapedPattern(for: candidate))
                if let prefixRange = query.firstMatch(of: prefixPattern)?.range {
                    query.removeSubrange(prefixRange)
                }
                // Return with proper casing
                return candidate.prefix(1).uppercased() + candidate.dropFirst()
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    func mergeBestEffort(regex: ParsedQuery, llm: ParsedQuery) -> ParsedQuery {
        let appFilter = regex.appFilter ?? llm.appFilter
        let since = regex.since ?? llm.since

        let llmTerms = llm.searchTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { term in
                guard let appFilter else { return true }
                return term.caseInsensitiveCompare(appFilter) != .orderedSame
            }

        return ParsedQuery(
            searchTerms: llmTerms.isEmpty ? regex.searchTerms : llmTerms,
            since: since,
            appFilter: appFilter,
            rawQuery: regex.rawQuery
        )
    }

    private func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["RERUN_DEBUG_PARSER"] == "1" else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func debugLogParsed(_ parsed: ParsedQuery) {
        guard ProcessInfo.processInfo.environment["RERUN_DEBUG_PARSER"] == "1" else { return }
        let terms = parsed.searchTerms.joined(separator: "|")
        let since = parsed.since ?? "nil"
        let app = parsed.appFilter ?? "nil"
        debugLog("searchTerms=\(terms)")
        debugLog("since=\(since)")
        debugLog("app=\(app)")
    }
}

// MARK: - Foundation Models (macOS 26+)

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
@Generable
struct LLMParsedQuery {
    @Guide(description: "Keywords to search for, excluding time references and app names")
    var searchTerms: [String]

    @Guide(description: "ISO8601 start time if the user specified a time range, nil otherwise")
    var sinceTime: String?

    @Guide(description: "App name if the user mentioned a specific app, nil otherwise")
    var appFilter: String?
}

extension QueryParser {
    @available(macOS 26, *)
    func parseWithLLM(_ query: String, now: Date) async -> ParsedQuery? {
        do {
            let session = LanguageModelSession()
            let currentTime = iso8601(now)
            let prompt = """
                Current UTC time: \(currentTime)

                Parse this search query.
                - Convert relative times such as "today" and "yesterday" relative to the current UTC time.
                - Keep app names out of search terms.
                - Return only meaningful search keywords, not filler words.

                Query: "\(query)"
                """
            let response = try await session.respond(to: prompt, generating: LLMParsedQuery.self)
            let parsed = response.content
            return ParsedQuery(
                searchTerms: parsed.searchTerms,
                since: parsed.sinceTime,
                appFilter: parsed.appFilter,
                rawQuery: query
            )
        } catch {
            return nil
        }
    }
}
#endif
