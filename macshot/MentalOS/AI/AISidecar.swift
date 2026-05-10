import Foundation

/// AI-generated enrichment for a single capture.
/// Stored as `{uuid}_ai.json` alongside `_context.json` and `_ocr.json`.
///
/// This file is fully regenerable — user data in `_context.json` is never touched.
/// The orphan pruner in `ScreenshotHistory` cleans it up automatically when the
/// parent capture is deleted (same UUID prefix convention as all other sidecars).
///
/// `embeddingProviderID` lets future code detect stale embeddings when the
/// configured provider changes and trigger selective re-embedding.
struct AISidecar: Codable {
    let id: String
    let generatedAt: Date

    // MARK: Summarization
    let summary: String?
    let summaryProviderID: String?

    // MARK: Embedding
    let embedding: [Float]?
    let embeddingProviderID: String?
    let embeddingDimensions: Int?
}
