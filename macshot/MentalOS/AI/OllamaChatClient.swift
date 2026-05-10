import Foundation

/// One turn in an Ollama chat. `images` is non-empty only on user turns that
/// include attachments (base64-encoded PNG/JPEG without the data URI prefix).
struct OllamaChatMessage: Codable, Equatable {
    let role: String   // "user" or "assistant" (or "system")
    var content: String
    var images: [String]?
}

enum OllamaChatError: LocalizedError {
    case badStatus(Int, body: String)
    case decodeFailure(String)
    case cancelled
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "Ollama returned HTTP \(code): \(body.prefix(200))"
        case .decodeFailure(let detail):
            return "Could not decode Ollama response: \(detail)"
        case .cancelled:
            return "Cancelled"
        case .unreachable(let detail):
            return "Could not reach Ollama at localhost:11434 (\(detail)). Is `ollama serve` running?"
        }
    }
}

/// Streaming chat client for a locally running Ollama server. Defaults to
/// gemma4:e4b (multimodal: vision + audio + tools). Override via UserDefaults
/// `mentalOSChatModel` or by passing `model` explicitly.
///
/// Requires Ollama running at http://localhost:11434.
/// Pull the model first: `ollama pull gemma4:e4b`
final class OllamaChatClient {

    let model: String
    let baseURL: URL

    static var defaultModel: String {
        let stored = UserDefaults.standard.string(forKey: "mentalOSChatModel") ?? ""
        return stored.isEmpty ? "gemma4:e4b" : stored
    }

    init(model: String = OllamaChatClient.defaultModel,
         baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.model = model
        self.baseURL = baseURL
    }

    /// Streams the assistant's response chunk-by-chunk. Each yielded String is
    /// an incremental delta to append; concatenating them gives the full reply.
    func streamReply(messages: [OllamaChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 120
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": try messages.map { try $0.asDictionary() },
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch {
                        continuation.finish(throwing: OllamaChatError.unreachable(error.localizedDescription))
                        return
                    }

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 500 { break } }
                        continuation.finish(throwing: OllamaChatError.badStatus(http.statusCode, body: body))
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: OllamaChatError.cancelled)
                            return
                        }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        if let msg = obj["message"] as? [String: Any],
                           let chunk = msg["content"] as? String, !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                        if let done = obj["done"] as? Bool, done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension OllamaChatMessage {
    func asDictionary() throws -> [String: Any] {
        var dict: [String: Any] = ["role": role, "content": content]
        if let images = images, !images.isEmpty { dict["images"] = images }
        return dict
    }
}
