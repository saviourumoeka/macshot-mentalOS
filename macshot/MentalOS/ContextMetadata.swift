import Foundation

struct ContextMetadata: Codable {
    let id: String
    var title: String
    var note: String
    var tags: [String]
    let app: String?
    let bundleID: String?
    let windowTitle: String?
    let browserURL: String?
    var ocrText: String
    let createdAt: Date

    init(
        id: String,
        title: String = "",
        note: String = "",
        tags: [String] = [],
        app: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        browserURL: String? = nil,
        ocrText: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.tags = tags
        self.app = app
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.browserURL = browserURL
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}
