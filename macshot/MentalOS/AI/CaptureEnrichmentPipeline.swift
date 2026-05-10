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
            do {
                summary = try await summarizer.summarize(text)
                summaryProviderID = summarizer.providerID
            } catch {
                Log.error("Summarization failed", category: .enrichment, error: error, ["id": id, "provider": summarizer.providerID])
            }
        }

        if let embedder = registry.embeddingProvider, !text.isEmpty {
            do {
                embedding = try await embedder.embed(text)
                embeddingProviderID = embedder.providerID
                embeddingDimensions = embedder.dimensions
            } catch {
                Log.error("Embedding failed", category: .enrichment, error: error, ["id": id, "provider": embedder.providerID])
            }
        }

        guard summary != nil || embedding != nil else {
            Log.debug("Enrichment produced no output", category: .enrichment, ["id": id])
            return
        }

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
        do {
            let data = try encoder.encode(sidecar)
            try data.write(to: url, options: .atomic)
            Log.info("AI sidecar written", category: .enrichment, ["id": id, "has_summary": summary != nil, "has_embedding": embedding != nil])
        } catch {
            Log.error("Failed to write AI sidecar", category: .enrichment, error: error, ["id": id, "path": url.path])
        }
    }
}
