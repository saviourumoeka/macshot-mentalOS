import Foundation

/// Generates a concise summary of text.
///
/// Future implementations:
/// - Ollama (gemma3, llama3, mistral) — local, no API key
/// - Claude (Anthropic API) — cloud, API key required
/// - Apple Foundation model (future, on-device)
protocol SummarizationProvider: Sendable {

    /// Stable identifier for this provider and model.
    /// Example: "ollama/gemma3", "claude/claude-haiku-4-5"
    var providerID: String { get }

    /// Summarize the given text. `maxWords` is a soft target, not a hard limit.
    func summarize(_ text: String, maxWords: Int) async throws -> String
}

extension SummarizationProvider {

    func summarize(_ text: String) async throws -> String {
        try await summarize(text, maxWords: 50)
    }
}
