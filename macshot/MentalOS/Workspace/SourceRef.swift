import Foundation

/// A typed reference to an external source ingested into a WorkspaceSession.
enum SourceRef: Codable, Hashable, Sendable {
    case screenshot(uuid: String)
    case pdf(path: String, sha256: String)
    case markdown(path: String, sha256: String)

    // MARK: - Stable identifier for deduplication / VectorStore keying

    var sourceID: String {
        switch self {
        case .screenshot(let uuid): return "screenshot:\(uuid)"
        case .pdf(let path, _): return "pdf:\(path)"
        case .markdown(let path, _): return "markdown:\(path)"
        }
    }

    // MARK: - Codable (manual to support associated values portably)

    private enum CodingKeys: String, CodingKey {
        case type, uuid, path, sha256
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "screenshot":
            self = .screenshot(uuid: try c.decode(String.self, forKey: .uuid))
        case "pdf":
            self = .pdf(path: try c.decode(String.self, forKey: .path),
                        sha256: try c.decode(String.self, forKey: .sha256))
        case "markdown":
            self = .markdown(path: try c.decode(String.self, forKey: .path),
                             sha256: try c.decode(String.self, forKey: .sha256))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown SourceRef type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .screenshot(let uuid):
            try c.encode("screenshot", forKey: .type)
            try c.encode(uuid, forKey: .uuid)
        case .pdf(let path, let sha256):
            try c.encode("pdf", forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(sha256, forKey: .sha256)
        case .markdown(let path, let sha256):
            try c.encode("markdown", forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(sha256, forKey: .sha256)
        }
    }
}
