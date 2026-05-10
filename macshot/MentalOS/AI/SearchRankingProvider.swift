import Foundation

/// Re-ranks substring search results using semantic relevance.
///
/// Receives `[IndexEntry]` already filtered by substring matching and returns
/// them reordered (and optionally filtered) by semantic relevance to the query.
///
/// Future hook: `SearchIndex` gains an async `semanticSearch(query:completion:)`
/// method that calls `SearchRankingProvider.rerank()` after substring pre-filtering.
/// `SearchWindowController` debounces and calls this path when a provider is configured.
///
/// Future implementations:
/// - Embedding-backed cosine re-ranker (uses stored `_ai.json` vectors)
/// - Cross-encoder model (slower but more accurate than bi-encoder)
/// - Claude-based semantic filter (best quality, cloud, API key required)
protocol SearchRankingProvider: Sendable {

    /// Re-rank `entries` by relevance to `query`.
    /// Returns entries paired with a relevance score in [0, 1], sorted descending.
    /// May return fewer entries than received (irrelevant results filtered out).
    func rerank(query: String, entries: [IndexEntry]) async throws -> [(entry: IndexEntry, score: Float)]
}
