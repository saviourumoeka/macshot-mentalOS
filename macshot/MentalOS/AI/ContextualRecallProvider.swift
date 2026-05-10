import Foundation

/// A structured query for contextual recall.
struct RecallQuery {
    /// Natural language description of what to find.
    /// Example: "deployment error I was debugging", "invoice from last week"
    let text: String

    /// Optional time range to restrict the search.
    let timeRange: DateInterval?

    /// Optional app name filter (e.g. "Xcode", "Safari").
    let appFilter: String?

    init(_ text: String, timeRange: DateInterval? = nil, appFilter: String? = nil) {
        self.text = text
        self.timeRange = timeRange
        self.appFilter = appFilter
    }
}

/// A single capture surfaced by a contextual recall query.
struct RecallResult {
    let entry: IndexEntry

    /// Relevance score in [0, 1].
    let score: Float

    /// Optional human-readable explanation of why this result was surfaced.
    /// Example: "You were in Xcode viewing AppDelegate.swift at 2:14 PM"
    let explanation: String?
}

/// Answers intent-based recall queries over the full capture history.
///
/// Unlike keyword search (which matches substrings), recall is intent-based:
/// "What was I debugging last Tuesday?" or "Find the API error I saw in Safari."
///
/// Future hook: a dedicated Recall panel or chat interface queries this provider.
/// The panel is separate from `SearchWindowController` — different UX, different latency.
///
/// Future implementations:
/// - RAG pipeline: embed query → nearest neighbors in `_ai.json` vectors → LLM synthesis
/// - Claude with full OCR text in context window — best comprehension, needs API key
/// - Local Ollama RAG — fully offline
protocol ContextualRecallProvider: Sendable {

    /// Stable identifier for this provider.
    var providerID: String { get }

    /// Return relevant captures for the given recall query.
    /// `entries` is the full in-memory index — provider applies its own filtering.
    func recall(_ query: RecallQuery, from entries: [IndexEntry]) async throws -> [RecallResult]
}
