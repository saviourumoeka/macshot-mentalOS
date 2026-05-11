import Foundation

/// A named research session that groups sources, a chat thread, and freeform notes.
struct WorkspaceSession: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var sources: [SourceRef]
    /// Freeform Markdown notes scoped to this workspace.
    var notesMarkdown: String
    /// UUID of the associated ChatTranscript (stored separately as `<id>_chat.json`).
    var chatTranscriptID: String?

    init(
        id: UUID = UUID(),
        title: String = "Untitled Workspace",
        createdAt: Date = Date(),
        sources: [SourceRef] = [],
        notesMarkdown: String = "",
        chatTranscriptID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sources = sources
        self.notesMarkdown = notesMarkdown
        self.chatTranscriptID = chatTranscriptID
    }

    mutating func addSource(_ ref: SourceRef) {
        guard !sources.contains(ref) else { return }
        sources.append(ref)
    }

    mutating func removeSource(_ ref: SourceRef) {
        sources.removeAll { $0 == ref }
    }
}
