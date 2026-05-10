import Foundation
import AppKit

enum ContextCapture {

    private static let ioQueue = DispatchQueue(label: "com.sw33tlie.macshot.mentalOS.contextIO")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Write the initial context sidecar for a newly captured screenshot.
    /// Called on main thread; disk write is dispatched to background.
    /// Also adds the entry to SearchIndex immediately for instant discoverability.
    static func write(
        id: String,
        app: NSRunningApplication?,
        windowTitle: String?,
        to directory: URL
    ) {
        let metadata = ContextMetadata(
            id: id,
            app: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            windowTitle: windowTitle
        )
        // Update the in-memory index immediately, before the disk write completes.
        SearchIndex.shared.add(metadata: metadata)
        let url = directory.appendingPathComponent("\(id)_context.json")
        ioQueue.async {
            guard let data = try? encoder.encode(metadata) else { return }
            try? data.write(to: url, options: .atomic)
        }
        // Group the capture into the presentation tree (App / Session subfolders of symlinks).
        // Runs after the sidecar write is queued; PresentationTree itself dispatches its disk work off-main.
        PresentationTree.shared.register(metadata: metadata, directory: directory)
    }

    /// Read the context sidecar for a given capture ID. Returns nil if missing.
    static func read(id: String, from directory: URL) -> ContextMetadata? {
        let url = directory.appendingPathComponent("\(id)_context.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ContextMetadata.self, from: data)
    }

    /// Mutate and re-save a context sidecar. No-op if the sidecar doesn't exist.
    /// `completionOnMain` is called on the main thread after the write completes —
    /// used by callers (e.g. CaptureOCR) to reindex the updated entry in SearchIndex.
    static func update(
        id: String,
        in directory: URL,
        completionOnMain: (() -> Void)? = nil,
        transform: @escaping (inout ContextMetadata) -> Void
    ) {
        ioQueue.async {
            guard var metadata = read(id: id, from: directory) else { return }
            transform(&metadata)
            let url = directory.appendingPathComponent("\(id)_context.json")
            guard let data = try? encoder.encode(metadata) else {
                DispatchQueue.main.async { completionOnMain?() }
                return
            }
            try? data.write(to: url, options: .atomic)
            DispatchQueue.main.async { completionOnMain?() }
        }
    }
}
