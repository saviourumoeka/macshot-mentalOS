import Cocoa

/// Standalone window for chatting with a local Gemma (Ollama) model about a
/// specific screenshot. Conversation is persisted to `<uuid>_chat.json`.
@MainActor
final class ChatWindowController: NSObject, NSWindowDelegate {

    // Lifecycle: keep instances alive while their window is open.
    private static var active: [ChatWindowController] = []

    private let entryID: String
    private let historyDirectory: URL
    private let image: NSImage
    private let metadata: ContextMetadata?

    private var window: NSWindow?
    private var transcriptTextView: NSTextView!
    private var inputField: NSTextField!
    private var sendButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var modelLabel: NSTextField!

    private var turns: [ChatTurn] = []
    private var imageBase64: String?
    private var streamTask: Task<Void, Never>?

    /// Open (or focus) a chat window for the given capture.
    static func open(entryID: String, image: NSImage, historyDirectory: URL) {
        if let existing = active.first(where: { $0.entryID == entryID }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = ChatWindowController(entryID: entryID, image: image, historyDirectory: historyDirectory)
        controller.show()
        active.append(controller)
    }

    private init(entryID: String, image: NSImage, historyDirectory: URL) {
        self.entryID = entryID
        self.historyDirectory = historyDirectory
        self.image = image
        self.metadata = ContextCapture.read(id: entryID, from: historyDirectory)
        super.init()
    }

    private func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 520, height: 680)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Chat — \(metadata?.app ?? "Screenshot")"
        win.minSize = NSSize(width: 420, height: 480)
        win.delegate = self
        win.isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]

        // Header — thumbnail + capture metadata.
        let header = makeHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        // Transcript.
        let transcriptScroll = NSScrollView()
        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.autohidesScrollers = true
        transcriptScroll.borderType = .noBorder
        transcriptScroll.drawsBackground = true
        transcriptScroll.backgroundColor = .textBackgroundColor

        transcriptTextView = NSTextView()
        transcriptTextView.isEditable = false
        transcriptTextView.isRichText = true
        transcriptTextView.drawsBackground = true
        transcriptTextView.backgroundColor = .textBackgroundColor
        transcriptTextView.textContainerInset = NSSize(width: 12, height: 14)
        transcriptTextView.font = NSFont.systemFont(ofSize: 13)
        transcriptTextView.autoresizingMask = [.width]
        transcriptScroll.documentView = transcriptTextView
        container.addSubview(transcriptScroll)

        // Input row.
        let inputRow = NSView()
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inputRow)

        inputField = NSTextField()
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "Ask Gemma about this screenshot…"
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.target = self
        inputField.action = #selector(sendClicked)
        inputRow.addSubview(inputField)

        sendButton = NSButton(title: "Send", target: self, action: #selector(sendClicked))
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(sendButton)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isDisplayedWhenStopped = false
        inputRow.addSubview(spinner)

        modelLabel = NSTextField(labelWithString: "via \(OllamaChatClient.defaultModel) · localhost:11434")
        modelLabel.font = NSFont.systemFont(ofSize: 10)
        modelLabel.textColor = .tertiaryLabelColor
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modelLabel)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: 60),

            transcriptScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            transcriptScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            transcriptScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            transcriptScroll.bottomAnchor.constraint(equalTo: inputRow.topAnchor, constant: -8),

            inputRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            inputRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            inputRow.heightAnchor.constraint(equalToConstant: 30),
            inputRow.bottomAnchor.constraint(equalTo: modelLabel.topAnchor, constant: -6),

            inputField.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),
            inputField.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            inputField.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            spinner.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            sendButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),

            modelLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            modelLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        win.contentView = container
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(inputField)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        // Encode the image once for re-use across turns.
        Task.detached(priority: .utility) { [image] in
            let b64 = Self.encodeBase64(image: image)
            await MainActor.run { self.imageBase64 = b64 }
        }

        // Load existing transcript.
        turns = ChatTranscript.read(id: entryID, from: historyDirectory)
        renderTranscript()
    }

    private func makeHeader() -> NSView {
        let row = NSView()
        let thumb = NSImageView()
        thumb.image = image
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 4
        thumb.layer?.masksToBounds = true
        row.addSubview(thumb)

        let title = NSTextField(labelWithString: metadata?.app ?? "Screenshot")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(title)

        let subtitle = NSTextField(labelWithString: subtitleText())
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(subtitle)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            thumb.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 56),
            thumb.heightAnchor.constraint(equalToConstant: 56),
            title.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            title.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
        ])
        return row
    }

    private func subtitleText() -> String {
        var bits: [String] = []
        if let title = metadata?.windowTitle, !title.isEmpty { bits.append(title) }
        if let created = metadata?.createdAt {
            let f = DateFormatter()
            f.dateStyle = .medium; f.timeStyle = .short
            bits.append(f.string(from: created))
        }
        return bits.joined(separator: " · ")
    }

    // MARK: - Rendering

    private func renderTranscript() {
        let attr = NSMutableAttributedString()
        for turn in turns { attr.append(formatted(turn: turn)) }
        transcriptTextView.textStorage?.setAttributedString(attr)
        transcriptTextView.scrollToEndOfDocument(nil)
    }

    private func formatted(turn: ChatTurn) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let prefix = turn.role == "user" ? "You\n" : "Gemma\n"
        let prefixColor: NSColor = turn.role == "user" ? .secondaryLabelColor : .controlAccentColor
        out.append(NSAttributedString(string: prefix, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: prefixColor,
        ]))
        out.append(NSAttributedString(string: turn.content + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]))
        return out
    }

    private func updateLastAssistantContent(_ content: String) {
        guard let last = turns.indices.last, turns[last].role == "assistant" else { return }
        turns[last] = ChatTurn(role: "assistant", content: content, timestamp: turns[last].timestamp)
        renderTranscript()
    }

    // MARK: - Send

    @objc private func sendClicked() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, streamTask == nil else { return }
        inputField.stringValue = ""
        sendUserMessage(text)
    }

    private func sendUserMessage(_ text: String) {
        let userTurn = ChatTurn(role: "user", content: text, timestamp: Date())
        turns.append(userTurn)
        let assistantTurn = ChatTurn(role: "assistant", content: "…", timestamp: Date())
        turns.append(assistantTurn)
        renderTranscript()
        ChatTranscript.write(id: entryID, in: historyDirectory, turns: turns)

        spinner.startAnimation(nil)
        sendButton.isEnabled = false

        let imageB64 = imageBase64
        let outgoing = buildOutgoingMessages(imageBase64: imageB64)
        let client = OllamaChatClient()

        streamTask = Task { [weak self] in
            guard let self = self else { return }
            var accumulated = ""
            do {
                for try await chunk in client.streamReply(messages: outgoing) {
                    accumulated += chunk
                    self.updateLastAssistantContent(accumulated)
                }
                if accumulated.isEmpty { accumulated = "(empty response)" }
                self.updateLastAssistantContent(accumulated)
                ChatTranscript.write(id: self.entryID, in: self.historyDirectory, turns: self.turns)
            } catch {
                let msg = "Error: \(error.localizedDescription)"
                self.updateLastAssistantContent(msg)
                ChatTranscript.write(id: self.entryID, in: self.historyDirectory, turns: self.turns)
            }
            self.spinner.stopAnimation(nil)
            self.sendButton.isEnabled = true
            self.streamTask = nil
        }
    }

    /// Convert persisted turns + the latest user turn into Ollama chat messages.
    /// Image is attached only to the FIRST user turn so the model has visual context
    /// without bloating every request with the base64 payload. The trailing assistant
    /// placeholder we just appended is skipped — it's about to be replaced by the
    /// streamed response.
    private func buildOutgoingMessages(imageBase64: String?) -> [OllamaChatMessage] {
        var msgs: [OllamaChatMessage] = []
        var firstUserSeen = false
        let upperBound = turns.count - 1   // exclude trailing assistant placeholder
        guard upperBound >= 0 else { return msgs }
        for i in 0..<upperBound {
            let turn = turns[i]
            guard turn.role == "user" || turn.role == "assistant" else { continue }
            var images: [String]? = nil
            if turn.role == "user" && !firstUserSeen {
                if let b64 = imageBase64 { images = [b64] }
                firstUserSeen = true
            }
            msgs.append(OllamaChatMessage(role: turn.role, content: turn.content, images: images))
        }
        return msgs
    }

    // MARK: - Image encoding

    nonisolated private static func encodeBase64(image: NSImage) -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return ""
        }
        return png.base64EncodedString()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        streamTask?.cancel()
        streamTask = nil
        Self.active.removeAll { $0 === self }
    }
}

