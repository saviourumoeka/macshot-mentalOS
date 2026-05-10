import Foundation

/// One persisted message in a screenshot's chat thread. The image is attached
/// to the FIRST user message of the thread only — subsequent turns reference
/// the same conversation context already loaded by the model.
struct ChatTurn: Codable {
    let role: String        // "user" | "assistant"
    let content: String
    let timestamp: Date
}

/// Persistence for per-screenshot chat threads, stored alongside the other
/// MentalOS sidecars at `<historyDir>/<uuid>_chat.json`.
enum ChatTranscript {

    private static let ioQueue = DispatchQueue(label: "com.sw33tlie.macshot.mentalOS.chatIO")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func url(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id)_chat.json")
    }

    static func read(id: String, from directory: URL) -> [ChatTurn] {
        let u = url(id: id, in: directory)
        guard let data = try? Data(contentsOf: u),
              let turns = try? decoder.decode([ChatTurn].self, from: data) else { return [] }
        return turns
    }

    /// Write off-main; safe to call from main thread.
    static func write(id: String, in directory: URL, turns: [ChatTurn]) {
        let u = url(id: id, in: directory)
        ioQueue.async {
            guard let data = try? encoder.encode(turns) else { return }
            try? data.write(to: u, options: .atomic)
        }
    }

    /// Append a single turn and persist. Returns the updated transcript.
    static func append(id: String, in directory: URL, turn: ChatTurn) -> [ChatTurn] {
        var turns = read(id: id, from: directory)
        turns.append(turn)
        write(id: id, in: directory, turns: turns)
        return turns
    }
}
