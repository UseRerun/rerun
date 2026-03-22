import Foundation

public struct ParsedQuery: Sendable {
    public let searchTerms: [String]
    public let since: String?
    public let appFilter: String?
    public let rawQuery: String

    public init(searchTerms: [String], since: String?, appFilter: String?, rawQuery: String) {
        self.searchTerms = searchTerms
        self.since = since
        self.appFilter = appFilter
        self.rawQuery = rawQuery
    }

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
        "conductor", "dia",
    ]
    private static let fillerTerms: Set<String> = [
        "a", "about", "am", "an", "anything", "are", "at", "been",
        "browse", "browsed", "browsing",
        "chat", "chatted", "chatting",
        "did", "do", "does", "doing", "done",
        "find", "for",
        "happen", "happened", "happening", "has", "have",
        "i", "in", "is", "it",
        "look", "looked", "looking",
        "me", "my",
        "of", "on",
        "say", "said", "search", "see", "seen", "show",
        "talk", "talked", "talking", "tell", "that", "the", "there", "to",
        "up", "use", "used", "using",
        "visit", "visited",
        "website", "websites", "web", "page", "pages", "site", "sites",
        "activity", "activities", "project", "projects", "task", "tasks", "thing", "things",
        "stuff", "everything", "anything", "recent", "recently",
        "was", "were", "what", "when", "where", "which", "who",
        "with", "work", "working", "write", "wrote",
    ]
    private static let timeHintTerms: Set<String> = [
        "today", "yesterday", "morning", "afternoon", "evening",
        "night", "week", "hour", "minute", "ago", "monday",
        "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday",
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

        return finalize(
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

        // "last/past N minutes/hours/days/weeks"
        let lastPattern = /(last|past)\s+(\d+)\s+(minute|hour|day|week)s?/
        if let match = lower.firstMatch(of: lastPattern) {
            guard let amount = Int(match.2) else { return nil }
            let unit: Calendar.Component
            switch match.3 {
            case "minute": unit = .minute
            case "hour": unit = .hour
            case "day": unit = .day
            case "week": unit = .weekOfYear
            default: return nil
            }
            query.removeSubrange(match.range)
            return iso8601(calendar.date(byAdding: unit, value: -amount, to: now)!)
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
        let appPattern = /(?:in|from)\s+(\w[\w\s]*?)(?:\s+(?:today|yesterday|last|this|\d)|[?.!,]|$)/
        if let match = lower.firstMatch(of: appPattern) {
            let candidate = trimNoise(from: String(match.1)).trimmingCharacters(in: .whitespaces).lowercased()
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
        let regexParsed = finalize(
            searchTerms: regex.searchTerms,
            since: regex.since,
            appFilter: regex.appFilter,
            rawQuery: regex.rawQuery
        )
        let llmParsed = finalize(
            searchTerms: llm.searchTerms,
            since: llm.since,
            appFilter: llm.appFilter,
            rawQuery: llm.rawQuery
        )

        let appFilter = regexParsed.appFilter ?? llmParsed.appFilter
        let since = regexParsed.since ?? (containsTimeHint(regexParsed.rawQuery) ? llmParsed.since : nil)
        let llmTerms = cleanSearchTerms(llmParsed.searchTerms, appFilter: appFilter)
        let regexTerms = cleanSearchTerms(regexParsed.searchTerms, appFilter: appFilter)

        return finalize(
            searchTerms: llmTerms.isEmpty ? regexTerms : llmTerms,
            since: since,
            appFilter: appFilter,
            rawQuery: regexParsed.rawQuery
        )
    }

    private func finalize(
        searchTerms: [String],
        since: String?,
        appFilter: String?,
        rawQuery: String
    ) -> ParsedQuery {
        var normalizedApp = normalizeAppFilter(appFilter)
        var normalizedTerms = cleanSearchTerms(searchTerms, appFilter: normalizedApp)

        if normalizedApp == nil,
           normalizedTerms.count == 1,
           let appFromTerm = canonicalAppName(normalizedTerms[0]) {
            normalizedApp = appFromTerm
            normalizedTerms.removeAll()
        } else if normalizedApp == nil {
            let appTerms = normalizedTerms.compactMap { canonicalAppName($0) }
            if let appFromTerms = appTerms.first {
                normalizedApp = appFromTerms
                normalizedTerms.removeAll { canonicalAppName($0) == appFromTerms }
            }
        }

        if normalizedApp == nil, shouldInferMessagesApp(from: rawQuery) {
            normalizedApp = "Messages"
        }

        if normalizedApp == nil, shouldInferBrowserApp(from: rawQuery) {
            normalizedApp = "browser"
            normalizedTerms.removeAll { Self.browserFillerTerms.contains($0.lowercased()) }
        }

        return ParsedQuery(
            searchTerms: normalizedTerms,
            since: normalizeSince(since),
            appFilter: normalizedApp,
            rawQuery: rawQuery
        )
    }

    private func cleanSearchTerms(_ terms: [String], appFilter: String?) -> [String] {
        // Split multi-word terms into individual words first
        let expanded = terms.flatMap { $0.split(separator: " ").map(String.init) }
        let cleaned = expanded
            .map { trimNoise(from: $0) }
            .filter { !$0.isEmpty }
            .filter { term in
                let lower = term.lowercased()
                if Self.fillerTerms.contains(lower) || Self.timeHintTerms.contains(lower) || isTimeLikeTerm(lower) {
                    return false
                }
                guard let appFilter else { return true }
                return lower != appFilter.lowercased()
            }

        return stripTimeSequenceTokens(from: cleaned)
    }

    private func stripTimeSequenceTokens(from terms: [String]) -> [String] {
        let lowerTerms = terms.map { $0.lowercased() }
        let units: Set<String> = [
            "minute", "minutes", "hour", "hours", "day", "days", "week", "weeks",
        ]
        let markers: Set<String> = ["last", "past"]

        return terms.enumerated().compactMap { index, term in
            let lower = lowerTerms[index]
            let previous = index > 0 ? lowerTerms[index - 1] : nil
            let next = index + 1 < lowerTerms.count ? lowerTerms[index + 1] : nil
            let previousIsNumber = previous?.allSatisfy(\.isNumber) == true
            let nextIsTimeUnit = next.map(units.contains) == true
            let nextIsAgo = next == "ago"

            if markers.contains(lower) {
                return nil
            }

            if lower.allSatisfy(\.isNumber),
               previous.map(markers.contains) == true || nextIsTimeUnit {
                return nil
            }

            if units.contains(lower),
               previousIsNumber || nextIsAgo {
                return nil
            }

            if lower == "ago", previousIsNumber || previous.map(units.contains) == true {
                return nil
            }

            return term
        }
    }

    private func trimNoise(from term: String) -> String {
        term.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?:;()[]{}\"'"))
        )
    }

    private func normalizeAppFilter(_ appFilter: String?) -> String? {
        guard let appFilter else { return nil }
        let trimmed = trimNoise(from: appFilter).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "nil", trimmed.lowercased() != "null" else { return nil }
        return canonicalAppName(trimmed) ?? trimmed
    }

    private func canonicalAppName(_ candidate: String) -> String? {
        let lower = candidate.lowercased()
        guard Self.knownApps.contains(lower) else { return nil }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    private func normalizeSince(_ since: String?) -> String? {
        guard let since else { return nil }
        let trimmed = since.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "nil", trimmed.lowercased() != "null" else { return nil }
        return SearchTimeParser.parseSince(trimmed)
    }

    private func shouldInferMessagesApp(from query: String) -> Bool {
        let lower = query.lowercased()
        return lower.contains("chat with")
            || lower.contains("chatted with")
            || lower.contains("message")
            || lower.contains("messages")
            || lower.contains("texted")
            || lower.contains("talk to")
            || lower.contains("talked to")
            || lower.contains("said")
            || lower.contains(" say")
    }

    private static let browserApps: Set<String> = [
        "safari", "chrome", "firefox", "arc", "brave", "edge", "opera", "dia"
    ]
    private static let browserFillerTerms: Set<String> = [
        "websites", "website", "web", "pages", "page", "sites", "site", "urls"
    ]

    private func shouldInferBrowserApp(from query: String) -> Bool {
        let lower = query.lowercased()
        return lower.contains("website") || lower.contains("web page")
            || lower.contains("browsing") || lower.contains("browsed")
            || (lower.contains("sites") && !lower.contains("outside"))
    }

    private func containsTimeHint(_ query: String) -> Bool {
        let lower = query.lowercased()
        if Self.timeHintTerms.contains(where: { lower.contains($0) }) {
            return true
        }
        return lower.contains("last ") || lower.contains("this ") || lower.contains(" ago")
    }

    private func isTimeLikeTerm(_ term: String) -> Bool {
        let lower = term.lowercased()
        if Self.timeHintTerms.contains(where: { lower.contains($0) }) && lower.contains(where: \.isNumber) {
            return true
        }
        return lower.hasPrefix("last ") || lower.hasPrefix("past ")
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
