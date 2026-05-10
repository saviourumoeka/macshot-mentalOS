import Foundation

// MARK: - IndexEntry

struct IndexEntry {
    let id: String
    let title: String
    let note: String
    let tags: [String]
    let app: String
    let windowTitle: String
    let ocrText: String
    let createdAt: Date

    // Pre-lowercased for O(1) case-insensitive contains checks
    let titleLC: String
    let noteLC: String
    let tagsLC: [String]
    let appLC: String
    let windowTitleLC: String
    let ocrTextLC: String

    init(metadata: ContextMetadata) {
        id = metadata.id
        title = metadata.title
        note = metadata.note
        tags = metadata.tags
        app = metadata.app ?? ""
        windowTitle = metadata.windowTitle ?? ""
        ocrText = metadata.ocrText
        createdAt = metadata.createdAt
        titleLC = title.lowercased()
        noteLC = note.lowercased()
        tagsLC = tags.map { $0.lowercased() }
        appLC = app.lowercased()
        windowTitleLC = windowTitle.lowercased()
        ocrTextLC = ocrText.lowercased()
    }
}

// MARK: - SearchResult

struct SearchResult {
    enum Field {
        case title, note, tag, app, windowTitle, ocrText
    }

    let entry: IndexEntry
    let score: Int
    let matchedFields: Set<Field>
}
