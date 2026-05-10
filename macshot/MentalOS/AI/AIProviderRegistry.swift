import Foundation

/// Central registry for AI provider implementations.
///
/// Configure providers at app startup, before any captures occur.
/// Providers are read from background threads — set them only from the main thread
/// before the first capture, not concurrently with ongoing enrichment.
///
/// Usage:
///   AIProviderRegistry.shared.embeddingProvider = MyOllamaEmbedder()
///   AIProviderRegistry.shared.summarizationProvider = MyOllamaSummarizer()
final class AIProviderRegistry: @unchecked Sendable {

    static let shared = AIProviderRegistry()
    private init() {}

    private let lock = NSLock()

    private var _embeddingProvider: (any EmbeddingProvider)?
    /// Converts OCR text to embedding vectors. Stored in `_ai.json` for semantic search.
    var embeddingProvider: (any EmbeddingProvider)? {
        get { lock.withLock { _embeddingProvider } }
        set { lock.withLock { _embeddingProvider = newValue } }
    }

    private var _summarizationProvider: (any SummarizationProvider)?
    /// Generates a short summary of OCR text. Stored in `_ai.json`.
    var summarizationProvider: (any SummarizationProvider)? {
        get { lock.withLock { _summarizationProvider } }
        set { lock.withLock { _summarizationProvider = newValue } }
    }

    private var _searchRankingProvider: (any SearchRankingProvider)?
    /// Re-ranks substring search results by semantic relevance.
    /// Wired into `SearchIndex` when a future async search path is added.
    var searchRankingProvider: (any SearchRankingProvider)? {
        get { lock.withLock { _searchRankingProvider } }
        set { lock.withLock { _searchRankingProvider = newValue } }
    }

    private var _contextualRecallProvider: (any ContextualRecallProvider)?
    /// Answers intent-based recall queries over the full capture history.
    /// Wired into a future Recall panel or chat interface.
    var contextualRecallProvider: (any ContextualRecallProvider)? {
        get { lock.withLock { _contextualRecallProvider } }
        set { lock.withLock { _contextualRecallProvider = newValue } }
    }

    /// True if any provider that produces per-capture enrichment is configured.
    /// Used by `CaptureEnrichmentPipeline` to short-circuit when no AI is active.
    var hasEnrichmentProvider: Bool {
        embeddingProvider != nil || summarizationProvider != nil
    }
}
