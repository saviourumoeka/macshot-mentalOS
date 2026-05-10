import Cocoa
import QuickLookUI

// MARK: - Panel subclass

private final class KeyableSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Search text field

/// NSTextField that routes ↑↓ / Return / ESC to the controller
/// instead of moving the text cursor.
private final class SearchTextField: NSTextField {
    var onArrow: ((Bool) -> Void)?  // true = up, false = down
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrow?(true)   // ↑
        case 125: onArrow?(false)  // ↓
        case 36, 76: onReturn?()   // Return / KP Enter
        case 53: onEscape?()        // ESC
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - Table view that routes unhandled keys back to the search field

private final class SearchTableView: NSTableView {
    weak var searchField: SearchTextField?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125, 126: // ↑↓ — table handles these natively
            super.keyDown(with: event)
        case 36, 76: // Return — forward to field's handler
            searchField?.onReturn?()
        case 53: // ESC
            searchField?.onEscape?()
        default:
            // Route any typing back to the search field
            window?.makeFirstResponder(searchField)
            searchField?.keyDown(with: event)
        }
    }
}

// MARK: - Row cell

private final class SearchResultCell: NSView {

    private let selectionBg = NSView()
    private let thumbView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")

    private static let thumbW: CGFloat = 88
    private static let thumbH: CGFloat = 56
    private static let padLeft: CGFloat = 14
    private static let padRight: CGFloat = 14
    private static let textGap: CGFloat = 10

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)

        selectionBg.wantsLayer = true
        selectionBg.layer?.cornerRadius = 7
        addSubview(selectionBg)

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 5
        thumbView.layer?.masksToBounds = true
        addSubview(thumbView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        dateLabel.alignment = .right
        addSubview(dateLabel)

        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        metaLabel.lineBreakMode = .byTruncatingTail
        addSubview(metaLabel)

        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = NSColor.white.withAlphaComponent(0.38)
        snippetLabel.lineBreakMode = .byTruncatingTail
        addSubview(snippetLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(result: SearchResult, isSelected: Bool, thumbnail: NSImage?) {
        let e = result.entry

        // Selection background
        selectionBg.frame = bounds.insetBy(dx: 4, dy: 2)
        selectionBg.layer?.backgroundColor = isSelected
            ? ToolbarLayout.accentColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor

        // Thumbnail — non-flipped: y=0 is bottom
        let thumbY = (bounds.height - Self.thumbH) / 2
        let thumbX = Self.padLeft
        thumbView.frame = NSRect(x: thumbX, y: thumbY, width: Self.thumbW, height: Self.thumbH)
        thumbView.image = thumbnail

        // Text area
        let textX = thumbX + Self.thumbW + Self.textGap
        let textW = bounds.width - textX - Self.padRight
        let dateW: CGFloat = 76

        // Row heights in non-flipped coords (bottom-up)
        let snippetH: CGFloat = 15
        let metaH: CGFloat = 15
        let titleH: CGFloat = 17

        let snippetY: CGFloat = thumbY + 3
        let metaY = snippetY + snippetH + 2
        let titleY = metaY + metaH + 2

        titleLabel.frame = NSRect(x: textX, y: titleY, width: textW - dateW - 4, height: titleH)
        titleLabel.stringValue = e.title.isEmpty ? L("Untitled") : e.title

        dateLabel.frame = NSRect(x: bounds.width - Self.padRight - dateW, y: titleY, width: dateW, height: titleH)
        dateLabel.stringValue = Self.dateFormatter.string(from: e.createdAt)

        var metaParts: [String] = []
        if !e.app.isEmpty { metaParts.append(e.app) }
        if !e.windowTitle.isEmpty { metaParts.append(e.windowTitle) }
        metaLabel.frame = NSRect(x: textX, y: metaY, width: textW, height: metaH)
        metaLabel.stringValue = metaParts.joined(separator: " · ")

        snippetLabel.frame = NSRect(x: textX, y: snippetY, width: textW, height: snippetH)
        snippetLabel.stringValue = snippet(for: result)
    }

    private func snippet(for result: SearchResult) -> String {
        let e = result.entry
        if result.matchedFields.contains(.note), !e.note.isEmpty {
            return e.note.count > 80 ? String(e.note.prefix(80)) + "…" : e.note
        }
        if result.matchedFields.contains(.tag), !e.tags.isEmpty {
            return e.tags.map { "#\($0)" }.joined(separator: " ")
        }
        if result.matchedFields.contains(.ocrText), !e.ocrText.isEmpty {
            let t = e.ocrText
            return t.count > 80 ? String(t.prefix(80)) + "…" : t
        }
        if !e.tags.isEmpty { return e.tags.map { "#\($0)" }.joined(separator: " ") }
        if !e.note.isEmpty { return e.note.count > 80 ? String(e.note.prefix(80)) + "…" : e.note }
        return ""
    }
}

// MARK: - Controller

final class SearchWindowController: NSObject,
    NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate,
    QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    private var panel: KeyableSearchPanel?
    private weak var searchField: SearchTextField?
    private weak var tableView: SearchTableView?
    private weak var emptyLabel: NSTextField?

    private var results: [SearchResult] = []
    private var debounceTimer: Timer?
    private var previousSelectedRow: Int = -1
    private var thumbnailCache: [String: NSImage] = [:]
    private var loadsInFlight: Set<String> = []

    // Keeps self alive for QuickLook after dismiss
    private var qlRetainSelf: SearchWindowController?
    private var qlPreviewID: String?

    var onDismiss: (() -> Void)?

    private static let panelWidth: CGFloat = 620
    private static let panelHeight: CGFloat = 440
    static let rowHeight: CGFloat = 72

    // MARK: - Show / Dismiss

    func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            searchField?.selectText(nil)
            return
        }

        guard let screen = NSScreen.main else { return }

        let pw = Self.panelWidth, ph = Self.panelHeight
        let px = screen.frame.midX - pw / 2
        // Position slightly above center (spotlight-style)
        let py = screen.frame.midY - ph / 2 + screen.frame.height * 0.08

        let win = KeyableSearchPanel(
            contentRect: NSRect(x: px, y: py, width: pw, height: ph),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        win.alphaValue = 0

        win.contentView = buildContentView(size: NSSize(width: pw, height: ph))
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(searchField)
        self.panel = win

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1.0
        }

        // Warm the index; re-run search if field has text when load completes
        SearchIndex.shared.load { [weak self] in
            guard let self, let field = self.searchField, !field.stringValue.isEmpty else { return }
            self.runSearch()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didResignActiveNotification, object: nil)
        debounceTimer?.invalidate()
        debounceTimer = nil

        previousSelectedRow = -1

        guard let win = panel else {
            onDismiss?()
            return
        }
        panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            win.orderOut(nil)
            win.close()
            self?.results = []
            self?.onDismiss?()
        })
    }

    @objc private func appResignedActive() { dismiss() }

    // MARK: - Content View Construction

    private func buildContentView(size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        // Background
        let bg = CALayer()
        bg.frame = CGRect(origin: .zero, size: size)
        bg.backgroundColor = NSColor(white: 0.10, alpha: 0.95).cgColor
        bg.cornerRadius = 14
        container.layer?.addSublayer(bg)

        // 1pt border
        let border = CALayer()
        let bInset = CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
        border.frame = bInset
        border.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        border.borderWidth = 1
        border.cornerRadius = 13.5
        container.layer?.addSublayer(border)

        let searchBarH: CGFloat = 50
        let tableAreaH = size.height - searchBarH - 1

        // Table scroll area (bottom)
        let scrollView = buildTableScrollView(
            frame: NSRect(x: 0, y: 0, width: size.width, height: tableAreaH))
        container.addSubview(scrollView)

        // Empty / loading state label
        let empty = NSTextField(labelWithString: L("Type to search captures"))
        empty.font = .systemFont(ofSize: 13, weight: .medium)
        empty.textColor = NSColor.white.withAlphaComponent(0.28)
        empty.alignment = .center
        empty.frame = NSRect(x: 0, y: tableAreaH / 2 - 11, width: size.width, height: 22)
        container.addSubview(empty)
        emptyLabel = empty

        // Divider
        let div = NSView(frame: NSRect(x: 0, y: tableAreaH, width: size.width, height: 1))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        container.addSubview(div)

        // Search bar (top)
        let barView = buildSearchBar(width: size.width, height: searchBarH)
        barView.frame = NSRect(x: 0, y: size.height - searchBarH, width: size.width, height: searchBarH)
        container.addSubview(barView)

        return container
    }

    private func buildSearchBar(width: CGFloat, height: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Magnifying glass icon
        let iconSize: CGFloat = 17
        let iconX: CGFloat = 16
        let iconY = (height - iconSize) / 2
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            let iv = NSImageView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            iv.image = img
            iv.contentTintColor = NSColor.white.withAlphaComponent(0.38)
            bar.addSubview(iv)
        }

        // Search text field
        let fieldH: CGFloat = 28
        let field = SearchTextField(
            frame: NSRect(x: 42, y: (height - fieldH) / 2, width: width - 96, height: fieldH))
        field.placeholderAttributedString = NSAttributedString(
            string: L("Search captures…"),
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.32),
                .font: NSFont.systemFont(ofSize: 15),
            ])
        field.font = .systemFont(ofSize: 15)
        field.textColor = .white
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.delegate = self

        field.onArrow = { [weak self] up in self?.moveSelection(up: up) }
        field.onReturn = { [weak self] in self?.activateSelected() }
        field.onEscape = { [weak self] in self?.dismiss() }

        bar.addSubview(field)
        searchField = field

        // ESC hint
        let escH: CGFloat = 18
        let esc = NSTextField(labelWithString: "esc")
        esc.font = .systemFont(ofSize: 11, weight: .medium)
        esc.textColor = NSColor.white.withAlphaComponent(0.28)
        esc.frame = NSRect(x: width - 38, y: (height - escH) / 2, width: 28, height: escH)
        bar.addSubview(esc)

        return bar
    }

    private func buildTableScrollView(frame: NSRect) -> NSScrollView {
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.backgroundColor = .clear
        scroll.drawsBackground = false

        let table = SearchTableView(frame: NSRect(origin: .zero, size: frame.size))
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(tableDoubleClicked)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.width = frame.width
        table.addTableColumn(col)
        scroll.documentView = table
        tableView = table
        table.searchField = searchField

        return scroll
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.runSearch()
        }
    }

    private func runSearch() {
        guard let field = searchField else { return }
        let query = field.stringValue

        if query.isEmpty {
            results = []
            previousSelectedRow = -1
            emptyLabel?.stringValue = L("Type to search captures")
            emptyLabel?.isHidden = false
            tableView?.reloadData()
            return
        }

        results = SearchIndex.shared.search(query: query)
        previousSelectedRow = -1

        emptyLabel?.isHidden = !results.isEmpty
        emptyLabel?.stringValue = L("No results")
        tableView?.reloadData()

        if !results.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(up: Bool) {
        guard let table = tableView, !results.isEmpty else { return }
        let cur = table.selectedRow
        let next: Int
        if cur < 0 {
            next = up ? results.count - 1 : 0
        } else {
            next = max(0, min(results.count - 1, cur + (up ? -1 : 1)))
        }
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func activateSelected() {
        guard let table = tableView, table.selectedRow >= 0,
              table.selectedRow < results.count else { return }
        openInEditor(index: table.selectedRow)
    }

    @objc private func tableDoubleClicked() {
        guard let table = tableView, table.clickedRow >= 0,
              table.clickedRow < results.count else { return }
        openInEditor(index: table.clickedRow)
    }

    // MARK: - Actions

    private func openInEditor(index: Int) {
        guard index < results.count else { return }
        let id = results[index].entry.id
        dismiss()

        let entries = ScreenshotHistory.shared.entries
        guard let he = entries.first(where: { $0.id == id }) else { return }

        if he.hasAnnotations,
           let raw = ScreenshotHistory.shared.loadRawImage(for: he),
           let annotations = ScreenshotHistory.shared.loadAnnotations(for: he) {
            DispatchQueue.main.async {
                DetachedEditorWindowController.open(
                    image: raw, annotations: annotations, historyEntryID: id)
            }
        } else if let img = ScreenshotHistory.shared.loadImage(for: he) {
            DispatchQueue.main.async {
                DetachedEditorWindowController.open(
                    image: img, historyEntryID: id, disableBeautify: true)
            }
        }
    }

    func copyCapture(index: Int) {
        guard index < results.count else { return }
        let id = results[index].entry.id
        let entries = ScreenshotHistory.shared.entries
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        ScreenshotHistory.shared.copyEntry(at: i)
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        if soundEnabled { AppDelegate.captureSound?.play() }
        dismiss()
    }

    func quickLookCapture(index: Int) {
        guard index < results.count else { return }
        let id = results[index].entry.id
        qlPreviewID = id
        qlRetainSelf = self // keep self alive during QL session
        dismiss()
        guard let ql = QLPreviewPanel.shared() else { return }
        ql.dataSource = self
        ql.delegate = self
        ql.reloadData()
        ql.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("searchCell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? SearchResultCell
            ?? SearchResultCell(frame: NSRect(
                x: 0, y: 0, width: tableView.bounds.width, height: Self.rowHeight))
        cell.identifier = cellID
        let selected = row == tableView.selectedRow
        cell.configure(result: results[row], isSelected: selected,
                       thumbnail: thumbnail(for: results[row].entry.id))
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Self.rowHeight }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = tableView else { return }
        var toReload = IndexSet()
        if previousSelectedRow >= 0 { toReload.insert(previousSelectedRow) }
        let newRow = table.selectedRow
        if newRow >= 0 { toReload.insert(newRow) }
        previousSelectedRow = newRow
        if !toReload.isEmpty {
            table.reloadData(forRowIndexes: toReload, columnIndexes: IndexSet(integer: 0))
        }
    }

    // Handle Cmd+C / Space on a selected row via keyDown in the table
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    // MARK: - Thumbnail Loading

    private func thumbnail(for id: String) -> NSImage? {
        if let img = thumbnailCache[id] { return img }
        guard !loadsInFlight.contains(id) else { return nil }
        loadsInFlight.insert(id)

        let entries = ScreenshotHistory.shared.entries
        guard let he = entries.first(where: { $0.id == id }) else {
            loadsInFlight.remove(id)
            return nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = ScreenshotHistory.shared.loadPreview(for: he)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadsInFlight.remove(id)
                if let img {
                    self.thumbnailCache[id] = img
                    self.tableView?.reloadData()
                }
            }
        }
        return nil
    }

    // MARK: - QLPreviewPanelDataSource / Delegate

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { qlPreviewID != nil ? 1 : 0 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let id = qlPreviewID else { return nil }
        let entries = ScreenshotHistory.shared.entries
        guard let he = entries.first(where: { $0.id == id }) else { return nil }
        return ScreenshotHistory.shared.fileURL(for: he) as NSURL?
    }

    func previewPanelDidClose(_ panel: QLPreviewPanel!) {
        qlRetainSelf = nil
    }
}
