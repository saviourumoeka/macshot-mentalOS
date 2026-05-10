import Foundation
import AppKit

/// Maintains a human-friendly directory tree of symlinks pointing at the flat
/// history storage, so users (and external AI tools) can browse captures by
/// app and session.
///
/// Layout:
///   <appSupport>/com.sw33tlie.macshot/groups/
///     <App Name>/
///       Session 2026-05-10 14-32-15/
///         14-32-15 ab12cd34.png  -> ../../../history/<uuid>.png
///
/// A capture starts a new session unless the previous capture was from the same
/// app within `sessionWindow` seconds (default 120). Real files stay in the
/// existing flat history directory — this tree is purely a presentation layer.
@MainActor
final class PresentationTree {

    static let shared = PresentationTree()

    private let queue = DispatchQueue(label: "com.sw33tlie.macshot.mentalOS.presentation", qos: .utility)

    private var lastCaptureTime: Date?
    private var lastApp: String?
    private var lastSessionID: String?
    private var lastSessionLabel: String?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHistoryRemoved(_:)),
            name: .screenshotHistoryEntryWillRemove, object: nil)
    }

    /// Seconds between captures within which the same-app capture extends the previous session.
    var sessionWindow: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "mentalOSSessionWindowSeconds")
        return v > 0 ? v : 120
    }

    /// Root of the presentation tree (always writable — lives inside App Support).
    var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("com.sw33tlie.macshot/groups")
    }

    /// Suggested user-facing path. The app cannot create the symlink itself
    /// (sandbox blocks writing to ~/Documents); this is shown to the user
    /// alongside the `ln -s` command they run once.
    static var documentsShortcutPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/MentalOS/Screen Captures"
    }

    /// Shell command the user runs once to expose the tree under ~/Documents.
    static var setupCommand: String {
        let target = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.sw33tlie.macshot/groups").path) ?? "<groups path>"
        return "mkdir -p \"$HOME/Documents/MentalOS\" && ln -sfn \"\(target)\" \"$HOME/Documents/MentalOS/Screen Captures\""
    }

    /// Called from ContextCapture.write after the sidecar is queued. Decides the
    /// session bucket, writes sessionID back to the sidecar, and links the
    /// composited PNG into the presentation tree.
    func register(metadata: ContextMetadata, directory: URL) {
        let now = metadata.createdAt
        let app = (metadata.app?.isEmpty == false ? metadata.app! : "Unknown")

        let withinWindow: Bool
        if let last = lastCaptureTime { withinWindow = now.timeIntervalSince(last) < sessionWindow }
        else { withinWindow = false }
        let sameApp = (lastApp == app)

        let sessionID: String
        let sessionLabel: String
        if withinWindow && sameApp, let lid = lastSessionID, let llabel = lastSessionLabel {
            sessionID = lid
            sessionLabel = llabel
        } else {
            sessionID = UUID().uuidString
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH-mm-ss"
            sessionLabel = "Session \(f.string(from: now))"
        }

        lastCaptureTime = now
        lastApp = app
        lastSessionID = sessionID
        lastSessionLabel = sessionLabel

        // Persist sessionID so the bucket can be reconstructed from sidecars alone.
        ContextCapture.update(id: metadata.id, in: directory) { meta in
            meta.sessionID = sessionID
        }

        let appBucket = sanitize(app)
        let sessionBucket = sanitize(sessionLabel)
        let sourceFileName = "\(metadata.id).png"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH-mm-ss"
        let linkName = "\(timeFmt.string(from: now)) \(metadata.id.prefix(8)).png"
        let linkDir = rootURL
            .appendingPathComponent(appBucket)
            .appendingPathComponent(sessionBucket)
        let linkURL = linkDir.appendingPathComponent(linkName)
        let sourceURL = directory.appendingPathComponent(sourceFileName)

        queue.async {
            try? FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? FileManager.default.removeItem(at: linkURL)
            // Copy the actual image file so Finder shows a real image, not a shortcut.
            try? FileManager.default.copyItem(at: sourceURL, to: linkURL)
        }
    }

    /// Wipe the presentation tree and re-derive it from existing `_context.json` sidecars.
    /// Intended for first-run after deploying this feature, or recovery.
    func rebuildAll() {
        let history = ScreenshotHistory.shared.historyDirectory
        let root = rootURL
        queue.async { [weak self] in
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: history.path) else { return }
            // Sort by createdAt so session continuity rebuilds correctly.
            var metadatas: [ContextMetadata] = []
            for filename in files where filename.hasSuffix("_context.json") {
                let id = filename.replacingOccurrences(of: "_context.json", with: "")
                if let m = ContextCapture.read(id: id, from: history) { metadatas.append(m) }
            }
            metadatas.sort { $0.createdAt < $1.createdAt }
            DispatchQueue.main.async {
                self?.lastCaptureTime = nil
                self?.lastApp = nil
                self?.lastSessionID = nil
                self?.lastSessionLabel = nil
                for m in metadatas { self?.register(metadata: m, directory: history) }
            }
        }
    }

    @objc private func handleHistoryRemoved(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String else { return }
        let prefix = String(id.prefix(8))
        let root = rootURL
        queue.async {
            guard let appDirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
            for appDir in appDirs {
                guard let sessions = try? FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) else { continue }
                for session in sessions {
                    if let files = try? FileManager.default.contentsOfDirectory(at: session, includingPropertiesForKeys: nil) {
                        for f in files where f.lastPathComponent.contains(prefix) {
                            try? FileManager.default.removeItem(at: f)
                        }
                    }
                    if let remaining = try? FileManager.default.contentsOfDirectory(at: session, includingPropertiesForKeys: nil), remaining.isEmpty {
                        try? FileManager.default.removeItem(at: session)
                    }
                }
                if let remaining = try? FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil), remaining.isEmpty {
                    try? FileManager.default.removeItem(at: appDir)
                }
            }
        }
    }

    private func sanitize(_ s: String) -> String {
        let bad: Set<Character> = ["/", "\\", ":", "?", "*", "\"", "<", ">", "|", "\0"]
        let cleaned = String(s.map { bad.contains($0) ? "_" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.isEmpty ? "Unknown" : String(cleaned.prefix(64))
        return trimmed
    }
}
