import Foundation

/// Persistent store for `WorkspaceSession` objects.
///
/// Sessions are stored as individual JSON files at:
///   `<appSupport>/com.sw33tlie.macshot/workspaces/<uuid>.json`
///
/// All public methods are safe to call from the main thread; disk I/O is
/// dispatched to a private background queue.
final class WorkspaceStore: @unchecked Sendable {

    static let shared = WorkspaceStore()

    private let ioQueue = DispatchQueue(label: "com.sw33tlie.macshot.mentalOS.workspaceIO", qos: .utility)

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Debounce: pending auto-save work items keyed by session UUID.
    private var pendingSaves: [UUID: DispatchWorkItem] = [:]
    private let saveLock = NSLock()

    private static let autoSaveDelay: DispatchTimeInterval = .milliseconds(800)

    private init() {}

    // MARK: - Directory

    private var workspacesDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.sw33tlie.macshot/workspaces")
    }

    private func ensureDirectory() {
        let dir = workspacesDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.error("WorkspaceStore: failed to create workspaces dir", category: .workspace, error: error)
        }
    }

    private func jsonURL(for id: UUID) -> URL {
        workspacesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - CRUD

    /// Returns all persisted sessions sorted by `createdAt` descending.
    func list(completion: @escaping ([WorkspaceSession]) -> Void) {
        ioQueue.async { [self] in
            ensureDirectory()
            let dir = workspacesDirectory
            var sessions: [WorkspaceSession] = []
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil)
                for url in urls where url.pathExtension == "json" {
                    if let session = decode(url: url) {
                        sessions.append(session)
                    }
                }
            } catch {
                Log.error("WorkspaceStore: list failed", category: .workspace, error: error)
            }
            sessions.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { completion(sessions) }
        }
    }

    /// Load a single session by id. Calls `completion(nil)` when not found or corrupt.
    func load(id: UUID, completion: @escaping (WorkspaceSession?) -> Void) {
        ioQueue.async { [self] in
            let session = decode(url: jsonURL(for: id))
            DispatchQueue.main.async { completion(session) }
        }
    }

    /// Persist a session immediately (not debounced).
    func save(session: WorkspaceSession, completion: ((Error?) -> Void)? = nil) {
        ioQueue.async { [self] in
            ensureDirectory()
            do {
                let data = try encoder.encode(session)
                try data.write(to: jsonURL(for: session.id), options: .atomic)
                Log.debug("WorkspaceStore: saved", category: .workspace, ["id": session.id.uuidString])
                DispatchQueue.main.async { completion?(nil) }
            } catch {
                Log.error("WorkspaceStore: save failed", category: .workspace, error: error,
                          ["id": session.id.uuidString])
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    /// Queue a debounced auto-save (coalesces rapid edits).
    func saveDebounced(session: WorkspaceSession) {
        saveLock.lock()
        pendingSaves[session.id]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.save(session: session)
            self.saveLock.lock()
            self.pendingSaves.removeValue(forKey: session.id)
            self.saveLock.unlock()
        }
        pendingSaves[session.id] = item
        saveLock.unlock()
        ioQueue.asyncAfter(deadline: .now() + Self.autoSaveDelay, execute: item)
    }

    /// Delete a session's JSON file.
    func delete(id: UUID, completion: ((Error?) -> Void)? = nil) {
        ioQueue.async { [self] in
            let url = jsonURL(for: id)
            do {
                try FileManager.default.removeItem(at: url)
                Log.info("WorkspaceStore: deleted", category: .workspace, ["id": id.uuidString])
                DispatchQueue.main.async { completion?(nil) }
            } catch {
                Log.error("WorkspaceStore: delete failed", category: .workspace, error: error,
                          ["id": id.uuidString])
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    // MARK: - Helpers

    private func decode(url: URL) -> WorkspaceSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(WorkspaceSession.self, from: data)
        } catch {
            Log.error("WorkspaceStore: decode failed", category: .workspace, error: error,
                      ["path": url.lastPathComponent])
            return nil
        }
    }
}
