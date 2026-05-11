import Cocoa

/// Workspace window: 3-pane split view (Sources | Chat | Notes) for
/// multi-source, RAG-augmented work sessions. Phase-2 MentalOS feature.
///
/// Usage: `WorkspaceWindowController.open()` from AppDelegate.
/// Multiple instances are supported — each is independent.
@MainActor
final class WorkspaceWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var splitViewController: WorkspaceSplitView?

    // Keep instances alive until the window closes.
    private static var activeControllers: [WorkspaceWindowController] = []

    // MARK: - Factory

    static func open() {
        let controller = WorkspaceWindowController()
        controller.show()
        activeControllers.append(controller)
        // Switch to .regular so the Dock icon and Window menu appear.
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
    }

    // MARK: - Setup

    private func show() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame

        let defaultW: CGFloat = 1280
        let defaultH: CGFloat = 800
        let originX = sf.midX - defaultW / 2
        let originY = sf.midY - defaultH / 2

        let win = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: defaultW, height: defaultH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "MentalOS Workspace"
        win.minSize = NSSize(width: 800, height: 500)
        win.isReleasedWhenClosed = false
        win.delegate = self
        // Frame autosave — persists size/position across relaunches.
        win.setFrameAutosaveName("WorkspaceWindow")
        // Restore previously saved frame if available; keeps default otherwise.
        if !win.setFrameUsingName("WorkspaceWindow") {
            win.center()
        }
        win.collectionBehavior = [.fullScreenPrimary, .managed]

        let split = WorkspaceSplitView()
        win.contentViewController = split
        splitViewController = split

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Log.info("workspace opened", category: .workspace, ["windowNumber": win.windowNumber])
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Self.activeControllers.removeAll { $0 === self }
        if Self.activeControllers.isEmpty {
            // Only return to accessory if no other titled windows remain open
            // (editor windows manage this too via their own close handlers).
            let hasOtherTitledWindows = NSApp.windows.contains {
                $0.styleMask.contains(.titled) && $0.isVisible && $0 !== window
            }
            if !hasOtherTitledWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
