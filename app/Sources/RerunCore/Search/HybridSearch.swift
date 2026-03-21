import Foundation

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
        let ranked = try await db.searchCapturesWithRank(query: query, app: app, since: since, limit: limit)
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

        // Keyword results
        let keywordResults = try await db.searchCapturesWithRank(query: query, app: app, since: since, limit: limit)

        // If no embeddings available, keyword-only
        guard let embedding = queryEmbedding else {
            return keywordResults.map { item in
                ScoredResult(capture: item.capture, score: HybridSearch.normalizeRank(item.rank), source: .keyword)
            }
        }

        // Vector results
        let vectorResults = try await db.findSimilarWithDistance(to: embedding, app: app, since: since, limit: limit)

        // Merge with dedup
        return merge(keyword: keywordResults, vector: vectorResults, limit: limit)
    }

    // MARK: - Scoring

    static func normalizeRank(_ rank: Float) -> Float {
        1.0 / (1.0 + abs(rank))
    }

    static func normalizeDistance(_ distance: Float) -> Float {
        1.0 / (1.0 + distance)
    }

    private func merge(
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

        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }
}
