import Foundation

/// Converts text into a fixed-length vector embedding.
///
/// Future implementations:
/// - Ollama (nomic-embed-text, mxbai-embed-large) — local, no API key
/// - CoreML / Apple NLP CreateML text embedder — fully offline, bundled model
/// - OpenAI text-embedding-3-small / 3-large — cloud, API key required
/// - Sentence Transformers via local HTTP bridge
protocol EmbeddingProvider: Sendable {

    /// Dimensionality of the embedding vectors this provider produces.
    var dimensions: Int { get }

    /// Stable identifier for this provider and model.
    /// Stored in `_ai.json` to detect stale embeddings when the provider changes.
    /// Example: "ollama/nomic-embed-text", "openai/text-embedding-3-small"
    var providerID: String { get }

    /// Produce an embedding vector for the given text.
    /// Throws on model error, network failure, or empty input.
    func embed(_ text: String) async throws -> [Float]
}

extension EmbeddingProvider {

    /// Cosine similarity between two equal-length vectors. Returns 0 for zero-magnitude inputs.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(Float(0)) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(Float(0)) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
