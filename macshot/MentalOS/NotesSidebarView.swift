import Cocoa

/// Right-side notes pane embedded in the detached editor window.
/// Loads/persists `note` and `tags` on the capture's `_context.json` sidecar
/// via `ContextCapture.update`, which also triggers SearchIndex reindex.
@MainActor
final class NotesSidebarView: NSView {

    static let preferredWidth: CGFloat = 280

    private let header = NSTextField(labelWithString: "Notes")
    private let metaLabel = NSTextField(labelWithString: "")
    private let notesTextView = NSTextView()
    private let notesScroll = NSScrollView()
    private let tagsField = NSTextField()
    private let savedIndicator = NSTextField(labelWithString: "")

    private var entryID: String?
    private var historyDirectory: URL?
    private var saveDebounce: DispatchWorkItem?
    private var loadedSnapshot: (note: String, tags: [String]) = ("", [])

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.height, .minXMargin]

        // Translucent sidebar material — adapts to system appearance.
        let bg = NSVisualEffectView(frame: bounds)
        bg.material = .sidebar
        bg.blendingMode = .withinWindow
        bg.state = .followsWindowActiveState
        bg.autoresizingMask = [.width, .height]
        addSubview(bg)

        // Left separator line
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        header.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.maximumNumberOfLines = 2
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)

        notesScroll.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.hasVerticalScroller = true
        notesScroll.autohidesScrollers = true
        notesScroll.borderType = .lineBorder
        notesScroll.drawsBackground = true
        notesScroll.backgroundColor = .textBackgroundColor

        notesTextView.isEditable = true
        notesTextView.isRichText = false
        notesTextView.allowsUndo = true
        notesTextView.font = NSFont.systemFont(ofSize: 13)
        notesTextView.textColor = .labelColor
        notesTextView.backgroundColor = .textBackgroundColor
        notesTextView.drawsBackground = true
        notesTextView.textContainerInset = NSSize(width: 6, height: 8)
        notesTextView.delegate = self
        notesTextView.autoresizingMask = [.width]

        notesScroll.documentView = notesTextView
        addSubview(notesScroll)

        let tagsLabel = NSTextField(labelWithString: "Tags")
        tagsLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        tagsLabel.textColor = .secondaryLabelColor
        tagsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagsLabel)

        tagsField.placeholderString = "comma-separated"
        tagsField.font = NSFont.systemFont(ofSize: 12)
        tagsField.translatesAutoresizingMaskIntoConstraints = false
        tagsField.target = self
        tagsField.action = #selector(tagsCommitted)
        tagsField.delegate = self
        addSubview(tagsField)

        savedIndicator.font = NSFont.systemFont(ofSize: 10)
        savedIndicator.textColor = .tertiaryLabelColor
        savedIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(savedIndicator)

        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.widthAnchor.constraint(equalToConstant: 0.5),

            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            metaLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),

            notesScroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            notesScroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            notesScroll.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 10),

            tagsLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tagsLabel.topAnchor.constraint(equalTo: notesScroll.bottomAnchor, constant: 12),

            tagsField.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tagsField.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            tagsField.topAnchor.constraint(equalTo: tagsLabel.bottomAnchor, constant: 4),

            savedIndicator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            savedIndicator.topAnchor.constraint(equalTo: tagsField.bottomAnchor, constant: 8),
            savedIndicator.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            notesScroll.bottomAnchor.constraint(equalTo: tagsLabel.topAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Bind the sidebar to a capture. Pass `nil` id to leave it disabled
    /// (e.g. unsaved/non-history captures).
    func configure(entryID: String?, historyDirectory: URL) {
        self.entryID = entryID
        self.historyDirectory = historyDirectory

        guard let id = entryID,
              let metadata = ContextCapture.read(id: id, from: historyDirectory) else {
            notesTextView.string = ""
            tagsField.stringValue = ""
            metaLabel.stringValue = entryID == nil
                ? "Save the capture to enable notes."
                : "No metadata yet."
            notesTextView.isEditable = (entryID != nil)
            tagsField.isEnabled = (entryID != nil)
            loadedSnapshot = ("", [])
            return
        }

        notesTextView.string = metadata.note
        tagsField.stringValue = metadata.tags.joined(separator: ", ")
        loadedSnapshot = (metadata.note, metadata.tags)

        var meta: [String] = []
        if let app = metadata.app, !app.isEmpty { meta.append(app) }
        if let title = metadata.windowTitle, !title.isEmpty { meta.append(title) }
        metaLabel.stringValue = meta.isEmpty ? "Captured \(formatted(metadata.createdAt))" : meta.joined(separator: " · ")

        notesTextView.isEditable = true
        tagsField.isEnabled = true
        savedIndicator.stringValue = ""
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func scheduleSave() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        savedIndicator.stringValue = "Saving…"
    }

    private func saveNow() {
        guard let id = entryID, let dir = historyDirectory else { return }
        let note = notesTextView.string
        let tags = tagsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if note == loadedSnapshot.note && tags == loadedSnapshot.tags {
            savedIndicator.stringValue = ""
            return
        }
        loadedSnapshot = (note, tags)

        ContextCapture.update(id: id, in: dir, completionOnMain: { [weak self] in
            SearchIndex.shared.reindex(id: id, in: dir)
            self?.savedIndicator.stringValue = "Saved"
        }) { metadata in
            metadata.note = note
            metadata.tags = tags
        }
    }

    /// Force-flush any pending debounced save. Call before window closes.
    func flushPendingSave() {
        saveDebounce?.cancel()
        saveDebounce = nil
        saveNow()
    }
}

extension NotesSidebarView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        scheduleSave()
    }
}

extension NotesSidebarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        scheduleSave()
    }

    @objc fileprivate func tagsCommitted() {
        saveNow()
    }
}
