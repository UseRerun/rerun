import Testing
import Foundation
import GRDB
@testable import RerunCore

@Suite("Embeddings")
struct EmbeddingTests {

    private func makeDB(reverseUnorderedSelects: Bool = false) throws -> DatabaseManager {
        let path = NSTemporaryDirectory() + "rerun-test-\(UUID().uuidString).db"
        let extraPrepareDatabase: (@Sendable (Database) throws -> Void)? =
            reverseUnorderedSelects
                ? { @Sendable (db: Database) in try db.execute(sql: "PRAGMA reverse_unordered_selects = ON") }
                : nil
        return try DatabaseManager(path: path, extraPrepareDatabase: extraPrepareDatabase)
    }

    private func makeCapture(
        id: String = UUID().uuidString,
        textContent: String = "Stripe API charges endpoint POST /v1/charges"
    ) -> Capture {
        Capture(
            id: id,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Stripe API Reference",
            url: "https://stripe.com/docs/api/charges",
            textSource: "accessibility",
            captureTrigger: "app_switch",
            textContent: textContent,
            textHash: UUID().uuidString
        )
    }

    @Test func vecTableCreated() async throws {
        let db = try makeDB()
        let results = try await db.findSimilar(to: [Float](repeating: 0, count: 512), limit: 1)
        #expect(results.isEmpty)
    }

    @Test func insertAndFindEmbedding() async throws {
        let db = try makeDB()
        let capture = makeCapture()
        try await db.insertCapture(capture)

        let embedding = [Float](repeating: 0.5, count: 512)
        try await db.insertEmbedding(captureId: capture.id, embedding: embedding)

        let similar = try await db.findSimilar(to: embedding, limit: 5)
        #expect(similar.count == 1)
        #expect(similar[0].captureId == capture.id)
        #expect(similar[0].distance < 0.001)
    }

    @Test func knnOrdering() async throws {
        let db = try makeDB()

        // Create 3 captures with different embeddings
        let c1 = makeCapture(textContent: "close match")
        let c2 = makeCapture(textContent: "medium match")
        let c3 = makeCapture(textContent: "far match")
        try await db.insertCapture(c1)
        try await db.insertCapture(c2)
        try await db.insertCapture(c3)

        // Embeddings at increasing distances from query
        let e1 = [Float](repeating: 1.0, count: 512)
        let e2 = [Float](repeating: 0.5, count: 512)
        let e3 = [Float](repeating: 0.0, count: 512)

        try await db.insertEmbedding(captureId: c1.id, embedding: e1)
        try await db.insertEmbedding(captureId: c2.id, embedding: e2)
        try await db.insertEmbedding(captureId: c3.id, embedding: e3)

        // Query with embedding closest to c1
        let query = [Float](repeating: 1.0, count: 512)
        let results = try await db.findSimilar(to: query, limit: 3)

        #expect(results.count == 3)
        #expect(results[0].captureId == c1.id)
        #expect(results[0].distance < results[1].distance)
        #expect(results[1].distance < results[2].distance)
    }

    @Test func findSimilarCaptures() async throws {
        let db = try makeDB()
        let capture = makeCapture()
        try await db.insertCapture(capture)

        let embedding = [Float](repeating: 0.5, count: 512)
        try await db.insertEmbedding(captureId: capture.id, embedding: embedding)

        let captures = try await db.findSimilarCaptures(to: embedding, limit: 5)
        #expect(captures.count == 1)
        #expect(captures[0].id == capture.id)
        #expect(captures[0].appName == "Safari")
        #expect(captures[0].textContent == capture.textContent)
    }

    @Test func findSimilarCapturesPreservesOrdering() async throws {
        let db = try makeDB(reverseUnorderedSelects: true)

        let c1 = makeCapture(textContent: "close match")
        let c2 = makeCapture(textContent: "medium match")
        let c3 = makeCapture(textContent: "far match")
        try await db.insertCapture(c1)
        try await db.insertCapture(c2)
        try await db.insertCapture(c3)

        try await db.insertEmbedding(captureId: c1.id, embedding: [Float](repeating: 1.0, count: 512))
        try await db.insertEmbedding(captureId: c2.id, embedding: [Float](repeating: 0.5, count: 512))
        try await db.insertEmbedding(captureId: c3.id, embedding: [Float](repeating: 0.0, count: 512))

        let captures = try await db.findSimilarCaptures(to: [Float](repeating: 1.0, count: 512), limit: 3)
        #expect(captures.map(\.id) == [c1.id, c2.id, c3.id])
    }

    @Test func embeddingGeneratorAvailability() {
        // Should return a bool without crashing, regardless of system
        let _ = EmbeddingGenerator.isAvailable
    }

    // MARK: - Text Chunking

    @Test func chunkShortText() {
        let gen = EmbeddingGenerator()
        let chunks = gen.chunkText("Hello world", maxChars: 1000)
        #expect(chunks == ["Hello world"])
    }

    @Test func chunkEmptyText() {
        let gen = EmbeddingGenerator()
        let chunks = gen.chunkText("", maxChars: 1000)
        #expect(chunks.isEmpty)
    }

    @Test func chunkLongText() {
        let gen = EmbeddingGenerator()
        let p1 = String(repeating: "a", count: 600)
        let p2 = String(repeating: "b", count: 600)
        let text = p1 + "\n\n" + p2
        let chunks = gen.chunkText(text, maxChars: 1000)
        #expect(chunks.count == 2)
        #expect(chunks[0] == p1)
        #expect(chunks[1] == p2)
    }

    @Test func chunkMergesShortParagraphs() {
        let gen = EmbeddingGenerator()
        let text = "short one\n\nshort two\n\nshort three"
        let chunks = gen.chunkText(text, maxChars: 1000)
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    @Test func chunkSingleLongParagraph() {
        let gen = EmbeddingGenerator()
        let text = String(repeating: "a", count: 2500)
        let chunks = gen.chunkText(text, maxChars: 1000)
        #expect(chunks.count == 3)
        #expect(chunks.map(\.count) == [1000, 1000, 500])
        #expect(chunks.joined() == text)
    }

    // MARK: - Embedding Averaging

    @Test func averageSingleEmbedding() {
        let gen = EmbeddingGenerator()
        let emb: [Float] = [1.0, 2.0, 3.0]
        let result = gen.averageEmbeddings([emb])
        #expect(result == emb)
    }

    @Test func averageMultipleEmbeddings() {
        let gen = EmbeddingGenerator()
        let e1: [Float] = [1.0, 0.0, 3.0]
        let e2: [Float] = [3.0, 4.0, 1.0]
        let result = gen.averageEmbeddings([e1, e2])
        #expect(result == [2.0, 2.0, 2.0])
    }
}
