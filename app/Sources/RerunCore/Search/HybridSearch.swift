import Foundation
import os

private let logger = Logger(subsystem: "com.rerun", category: "HybridSearch")

public struct HybridSearch: Sendable {

    public enum SearchMode: String, Sendable, CaseIterable {
        case keyword, semantic, hybrid
    }

    public struct ScoredResult: Sendable {
        public let capture: Capture
        public let score: Float
        public let source: ResultSource
    }

    public enum ResultSource: String, Sendable {
        case keyword, semantic, both
    }

    static let vectorWeight: Float = 0.6
    static let keywordWeight: Float = 0.4

    public init() {}

    public func search(
        query: String,
        mode: SearchMode = .hybrid,
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20,
        db: DatabaseManager,
        embedder: EmbeddingGenerator
    ) async throws -> [ScoredResult] {
        switch mode {
        case .keyword:
            return try await keywordOnly(query: query, app: app, since: since, limit: limit, db: db)
        case .semantic:
            return try await semanticOnly(query: query, app: app, since: since, limit: limit, db: db, embedder: embedder)
        case .hybrid:
            return try await hybrid(query: query, app: app, since: since, limit: limit, db: db, embedder: embedder)
        }
    }

    // MARK: - Modes

    private func keywordOnly(
        query: String, app: String?, since: String?, limit: Int, db: DatabaseManager
    ) async throws -> [ScoredResult] {
        let ranked = try await keywordMatches(query: query, app: app, since: since, limit: limit, db: db)
        return ranked.map { item in
            ScoredResult(
                capture: item.capture,
                score: HybridSearch.normalizeRank(item.rank),
                source: .keyword
            )
        }
    }

    private func semanticOnly(
        query: String, app: String?, since: String?, limit: Int, db: DatabaseManager, embedder: EmbeddingGenerator
    ) async throws -> [ScoredResult] {
        guard let queryEmbedding = embedder.embed(query) else {
            return try await keywordOnly(query: query, app: app, since: since, limit: limit, db: db)
        }
        let results = try await db.findSimilarWithDistance(to: queryEmbedding, app: app, since: since, limit: limit)
        return results.map { item in
            ScoredResult(
                capture: item.capture,
                score: HybridSearch.normalizeDistance(item.distance),
                source: .semantic
            )
        }
    }

    private func hybrid(
        query: String, app: String?, since: String?, limit: Int, db: DatabaseManager, embedder: EmbeddingGenerator
    ) async throws -> [ScoredResult] {
        let queryEmbedding = embedder.embed(query)

        // Keyword results — degrade gracefully if FTS/DB fails
        let keywordResults: [(capture: Capture, rank: Float)]
        do {
            keywordResults = try await keywordMatches(query: query, app: app, since: since, limit: limit, db: db)
        } catch {
            logger.error("Keyword search failed: \(String(describing: error))")
            keywordResults = []
        }

        // If no embeddings available, keyword-only
        guard let embedding = queryEmbedding else {
            return keywordResults.map { item in
                ScoredResult(capture: item.capture, score: HybridSearch.normalizeRank(item.rank), source: .keyword)
            }
        }

        // Vector results — degrade to keyword-only if vec search fails
        let vectorResults: [(capture: Capture, distance: Float)]
        do {
            vectorResults = try await db.findSimilarWithDistance(to: embedding, app: app, since: since, limit: limit)
        } catch {
            logger.error("Vector search failed, using keyword results only: \(String(describing: error))")
            return keywordResults.map { item in
                ScoredResult(capture: item.capture, score: HybridSearch.normalizeRank(item.rank), source: .keyword)
            }
        }

        // Merge with dedup
        return merge(keyword: keywordResults, vector: vectorResults, limit: limit)
    }

    private func keywordMatches(
        query: String,
        app: String?,
        since: String?,
        limit: Int,
        db: DatabaseManager
    ) async throws -> [(capture: Capture, rank: Float)] {
        let normalizedQuery = normalizedKeywordQuery(query)
        for attempt in 0..<2 {
            let ranked = try await db.searchCapturesWithRank(query: query, app: app, since: since, limit: limit)
            if !ranked.isEmpty {
                return ranked
            }

            if !normalizedQuery.isEmpty, normalizedQuery != query {
                let normalizedRanked = try await db.searchCapturesWithRank(
                    query: normalizedQuery,
                    app: app,
                    since: since,
                    limit: limit
                )
                if !normalizedRanked.isEmpty {
                    return normalizedRanked
                }
            }

            let fallback = try await fallbackKeywordMatches(
                query: normalizedQuery.isEmpty ? query : normalizedQuery,
                app: app,
                since: since,
                limit: limit,
                db: db
            )
            if !fallback.isEmpty {
                return fallback
            }

            let substringFallback = try await db.substringSearchCaptures(
                query: normalizedQuery.isEmpty ? query : normalizedQuery,
                app: app,
                since: since,
                limit: limit
            )
            if !substringFallback.isEmpty || attempt == 1 {
                return substringFallback.map { (capture: $0, rank: -1) }
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        return []
    }

    private func normalizedKeywordQuery(_ query: String) -> String {
        let allowedSymbols = CharacterSet(charactersIn: "+#./-_")
        let scalars = query.precomposedStringWithCompatibilityMapping.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
                || allowedSymbols.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func fallbackKeywordMatches(
        query: String,
        app: String?,
        since: String?,
        limit: Int,
        db: DatabaseManager
    ) async throws -> [(capture: Capture, rank: Float)] {
        let stopTerms: Set<String> = [
            "ago", "day", "days", "hour", "hours", "last", "minute", "minutes",
            "past", "week", "weeks",
        ]
        let tokens = normalizedKeywordQuery(query)
            .split(separator: " ")
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) && !stopTerms.contains($0) }
        guard !tokens.isEmpty else { return [] }

        let candidateLimit: Int
        if since != nil {
            candidateLimit = 20_000
        } else if app != nil {
            candidateLimit = 2000
        } else {
            candidateLimit = 500
        }
        let normalizedSince = since.map { SearchTimeParser.parseSince($0) ?? $0 }
        let candidates = try await db.fetchCaptures(limit: candidateLimit)

        let scored = candidates.compactMap { capture -> (capture: Capture, rank: Float, hits: Int)? in
            if let app,
               capture.appName.caseInsensitiveCompare(app) != .orderedSame {
                return nil
            }
            if let normalizedSince,
               capture.timestamp < normalizedSince {
                return nil
            }

            let haystack = [
                capture.appName,
                capture.windowTitle ?? "",
                capture.url ?? "",
                capture.textContent,
            ]
            .joined(separator: "\n")
            .lowercased()

            let hits = tokens.reduce(into: 0) { total, token in
                if haystack.contains(token) {
                    total += 1
                }
            }
            guard hits > 0 else { return nil }

            // More matched tokens should sort ahead of weaker fallbacks.
            let rank = -Float(hits * 100)
            return (capture, rank, hits)
        }

        return scored
            .sorted {
                if $0.hits != $1.hits {
                    return $0.hits > $1.hits
                }
                return $0.capture.timestamp > $1.capture.timestamp
            }
            .prefix(limit)
            .map { (capture: $0.capture, rank: $0.rank) }
    }

    // MARK: - Scoring

    static func normalizeRank(_ rank: Float) -> Float {
        1.0 / (1.0 + abs(rank))
    }

    static func normalizeDistance(_ distance: Float) -> Float {
        1.0 / (1.0 + distance)
    }

    func merge(
        keyword: [(capture: Capture, rank: Float)],
        vector: [(capture: Capture, distance: Float)],
        limit: Int
    ) -> [ScoredResult] {
        var merged: [String: (capture: Capture, keywordScore: Float?, vectorScore: Float?)] = [:]

        for item in keyword {
            merged[item.capture.id] = (item.capture, HybridSearch.normalizeRank(item.rank), nil)
        }

        for item in vector {
            let vecScore = HybridSearch.normalizeDistance(item.distance)
            if var existing = merged[item.capture.id] {
                existing.vectorScore = vecScore
                merged[item.capture.id] = existing
            } else {
                merged[item.capture.id] = (item.capture, nil, vecScore)
            }
        }

        let scored: [ScoredResult] = merged.values.map { entry in
            let kw = entry.keywordScore
            let vec = entry.vectorScore

            let score: Float
            let source: ResultSource
            if let k = kw, let v = vec {
                score = HybridSearch.keywordWeight * k + HybridSearch.vectorWeight * v
                source = .both
            } else if let k = kw {
                score = HybridSearch.keywordWeight * k
                source = .keyword
            } else if let v = vec {
                score = HybridSearch.vectorWeight * v
                source = .semantic
            } else {
                score = 0
                source = .keyword
            }

            return ScoredResult(capture: entry.capture, score: score, source: source)
        }

        let keywordBacked = scored
            .filter { $0.source != .semantic }
            .sorted { $0.score > $1.score }
        let semanticOnly = scored
            .filter { $0.source == .semantic }
            .sorted { $0.score > $1.score }

        return Array((keywordBacked + semanticOnly).prefix(limit))
    }
}
