import Foundation

/// Summarizes OCR text using a locally running Ollama model.
///
/// Usage:
///   AIProviderRegistry.shared.summarizationProvider =
///       OllamaSummarizer(model: "gemma4:e4b")
///
/// Requires Ollama running at http://localhost:11434 (the default).
/// Pull the model first: `ollama pull gemma4:e4b`
struct OllamaSummarizer: SummarizationProvider {

    let model: String
    let baseURL: URL

    var providerID: String { "ollama/\(model)" }

    init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.model = model
        self.baseURL = baseURL
    }

    func summarize(_ text: String, maxWords: Int = 50) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("api/generate")

        let prompt = """
        Summarize the following text from a screenshot in \(maxWords) words or fewer. \
        Be concise and factual. Output only the summary, no preamble.

        TEXT:
        \(text)
        """

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.2]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String
        else {
            throw OllamaError.malformedResponse
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OllamaError: LocalizedError {
    case badStatus(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Ollama returned HTTP \(code)"
        case .malformedResponse: return "Ollama response missing 'response' field"
        }
    }
}
