import Cocoa

/// Three-pane split view for the MentalOS Workspace window.
///
/// Layout (left → right):
///   [Sources pane] | [Chat pane] | [Notes pane]
///
/// Each pane currently renders placeholder content. TASK-003, TASK-004,
/// and TASK-005 will replace the placeholders with real views.
final class WorkspaceSplitView: NSSplitViewController {

    // Expose child controllers so WorkspaceWindowController can replace them later.
    let sourcesPane  = WorkspacePlaceholderViewController(title: "Sources",  symbol: "doc.on.doc",         detail: "Drop screenshots, PDFs, or markdown files here")
    let chatPane     = WorkspacePlaceholderViewController(title: "Chat",     symbol: "bubble.left.and.bubble.right", detail: "Ask questions about your sources")
    let notesPane    = WorkspacePlaceholderViewController(title: "Notes",    symbol: "note.text",           detail: "Write markdown notes for this session")

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sourceItem = NSSplitViewItem(viewController: sourcesPane)
        sourceItem.minimumThickness = 180
        sourceItem.maximumThickness = 320
        sourceItem.canCollapse = true
        addSplitViewItem(sourceItem)

        let chatItem = NSSplitViewItem(viewController: chatPane)
        chatItem.minimumThickness = 300
        addSplitViewItem(chatItem)

        let notesItem = NSSplitViewItem(viewController: notesPane)
        notesItem.minimumThickness = 220
        notesItem.maximumThickness = 400
        notesItem.canCollapse = true
        addSplitViewItem(notesItem)
    }
}

// MARK: - Placeholder view controller

/// Temporary placeholder used by each pane until the real implementation lands.
final class WorkspacePlaceholderViewController: NSViewController {

    private let paneTitle: String
    private let symbolName: String
    private let detailText: String

    init(title: String, symbol: String, detail: String) {
        self.paneTitle  = title
        self.symbolName = symbol
        self.detailText = detail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .tertiaryLabelColor
        icon.setContentHuggingPriority(.required, for: .vertical)

        let title = NSTextField(labelWithString: paneTitle)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center

        let detail = NSTextField(wrappingLabelWithString: detailText)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .tertiaryLabelColor
        detail.alignment = .center
        detail.preferredMaxLayoutWidth = 180

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(detail)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
        ])
    }
}
