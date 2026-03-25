import Foundation
import NaturalLanguage

public struct EmbeddingGenerator: Sendable {

    /// Whether NLContextualEmbedding is available on this system.
    public static var isAvailable: Bool {
        NLContextualEmbedding(language: .english) != nil
    }

    public init() {}

    /// Generate a 512-dim embedding for the given text.
    /// Returns nil if NLContextualEmbedding is unavailable or generation fails.
    public func embed(_ text: String) -> [Float]? {
        guard let model = NLContextualEmbedding(language: .english) else {
            return nil
        }

        do {
            try model.load()
        } catch {
            return nil
        }

        let dim = model.dimension
        guard dim == 512 else { return nil }
        let chunks = chunkText(text, maxChars: 1000)
        var allEmbeddings: [[Float]] = []

        for chunk in chunks {
            guard let result = try? model.embeddingResult(for: chunk, language: .english) else {
                continue
            }
            let averaged = averageTokenEmbeddings(result, dimension: dim)
            if !averaged.isEmpty {
                allEmbeddings.append(averaged)
            }
        }

        guard !allEmbeddings.isEmpty else { return nil }
        return averageEmbeddings(allEmbeddings)
    }

    // MARK: - Text Chunking

    func chunkText(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maxChars else { return [trimmed] }

        let paragraphs = trimmed.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""

        for paragraph in paragraphs {
            let p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }

            if p.count > maxChars {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }

                var start = p.startIndex
                while start < p.endIndex {
                    let end = p.index(start, offsetBy: maxChars, limitedBy: p.endIndex) ?? p.endIndex
                    chunks.append(String(p[start..<end]))
                    start = end
                }
                continue
            }

            let separator = current.isEmpty ? "" : "\n\n"
            if current.count + separator.count + p.count > maxChars && !current.isEmpty {
                chunks.append(current)
                current = p
            } else {
                current += separator + p
            }
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks
    }

    // MARK: - Embedding Averaging

    private func averageTokenEmbeddings(_ result: NLContextualEmbeddingResult, dimension: Int) -> [Float] {
        var sum = [Float](repeating: 0, count: dimension)
        var count = 0

        result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) { vector, _ in
            for i in 0..<dimension {
                sum[i] += Float(vector[i])
            }
            count += 1
            return true
        }

        guard count > 0 else { return [] }
        return sum.map { $0 / Float(count) }
    }

    func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        guard embeddings.count > 1 else { return first }

        let dim = first.count
        var result = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            for i in 0..<dim {
                result[i] += emb[i]
            }
        }
        let scale = Float(embeddings.count)
        return result.map { $0 / scale }
    }
}
