import Foundation

/// Runs AI enrichment tasks after OCR completes for a new capture.
///
/// Integration point: called from `CaptureOCR.persist()` after sidecar writes.
/// No-op when no AI providers are configured in `AIProviderRegistry`.
///
/// To add a new enrichment step:
///   1. Define a provider protocol in this directory
///   2. Add an optional slot to `AIProviderRegistry`
///   3. Call it inside `enrich()` below and persist the result to `AISidecar`
enum CaptureEnrichmentPipeline {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Entry point. Safe to call from any thread. Immediate no-op if no providers configured.
    static func run(id: String, ocrText: String, historyDirectory: URL) {
        guard AIProviderRegistry.shared.hasEnrichmentProvider else { return }
        Task.detached(priority: .utility) {
            await enrich(id: id, ocrText: ocrText, historyDirectory: historyDirectory)
        }
    }

    // MARK: - Private

    private static func enrich(id: String, ocrText: String, historyDirectory: URL) async {
        let registry = AIProviderRegistry.shared
        let text = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)

        var summary: String?
        var summaryProviderID: String?
        var embedding: [Float]?
        var embeddingProviderID: String?
        var embeddingDimensions: Int?

        if let summarizer = registry.summarizationProvider, !text.isEmpty {
            summary = try? await summarizer.summarize(text)
            if summary != nil { summaryProviderID = summarizer.providerID }
        }

        if let embedder = registry.embeddingProvider, !text.isEmpty {
            embedding = try? await embedder.embed(text)
            if embedding != nil {
                embeddingProviderID = embedder.providerID
                embeddingDimensions = embedder.dimensions
            }
        }

        guard summary != nil || embedding != nil else { return }

        let sidecar = AISidecar(
            id: id,
            generatedAt: Date(),
            summary: summary,
            summaryProviderID: summaryProviderID,
            embedding: embedding,
            embeddingProviderID: embeddingProviderID,
            embeddingDimensions: embeddingDimensions
        )

        let url = historyDirectory.appendingPathComponent("\(id)_ai.json")
        guard let data = try? encoder.encode(sidecar) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
