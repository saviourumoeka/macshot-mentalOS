import Foundation

/// In-memory full-text search index over MentalOS context sidecars.
/// All mutating access must happen on the main thread.
final class SearchIndex {

    static let shared = SearchIndex()

    private var entries: [IndexEntry] = []
    private var isLoaded = false
    private var isLoading = false
    private var pendingCallbacks: [() -> Void] = []
    private var loadGeneration = 0

    private var historyDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.sw33tlie.macshot/history")
    }

    private init() {}

    // MARK: - Load

    /// Load the index from disk, then call `completion` on the main thread.
    /// Safe to call multiple times — redundant calls are coalesced.
    func load(then completion: @escaping () -> Void) {
        if isLoaded { completion(); return }
        pendingCallbacks.append(completion)
        guard !isLoading else { return }
        isLoading = true

        let dir = historyDirectory
        let gen = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let loaded: [IndexEntry] = files
                .filter { $0.lastPathComponent.hasSuffix("_context.json") }
                .compactMap { url -> IndexEntry? in
                    guard let data = try? Data(contentsOf: url),
                          let meta = try? decoder.decode(ContextMetadata.self, from: data)
                    else { return nil }
                    return IndexEntry(metadata: meta)
                }
                .sorted { $0.createdAt > $1.createdAt }

            DispatchQueue.main.async { self?.finishLoad(loaded, generation: gen) }
        }
    }

    private func finishLoad(_ loaded: [IndexEntry], generation: Int) {
        guard generation == loadGeneration else { return }
        // Merge: preserve any entries added during the background load (new captures)
        var merged = loaded
        for existing in entries where !merged.contains(where: { $0.id == existing.id }) {
            merged.append(existing)
        }
        entries = merged.sorted { $0.createdAt > $1.createdAt }
        isLoaded = true
        isLoading = false
        let callbacks = pendingCallbacks
        pendingCallbacks = []
        callbacks.forEach { $0() }
    }

    // MARK: - Search

    /// Synchronous substring search with multi-field scoring.
    /// Returns results sorted by score descending, then by createdAt descending.
    func search(query: String) -> [SearchResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var results: [SearchResult] = []
        for entry in entries {
            var score = 0
            var matched: Set<SearchResult.Field> = []

            for tagLC in entry.tagsLC {
                if tagLC == q {
                    score += 4; matched.insert(.tag)
                } else if tagLC.contains(q) {
                    score += 2; matched.insert(.tag)
                }
            }
            if entry.titleLC.contains(q)       { score += 3; matched.insert(.title) }
            if entry.noteLC.contains(q)         { score += 2; matched.insert(.note) }
            if entry.appLC.contains(q)          { score += 2; matched.insert(.app) }
            if entry.windowTitleLC.contains(q)  { score += 1; matched.insert(.windowTitle) }
            if entry.ocrTextLC.contains(q)      { score += 1; matched.insert(.ocrText) }

            if score > 0 {
                results.append(SearchResult(entry: entry, score: score, matchedFields: matched))
            }
        }

        return results.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.entry.createdAt > $1.entry.createdAt
        }
    }

    // MARK: - Mutation

    /// Called immediately after a new capture is written — adds to index without
    /// waiting for disk write to complete.
    func add(metadata: ContextMetadata) {
        let entry = IndexEntry(metadata: metadata)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    /// Called after a sidecar is patched (e.g. OCR completion, note/tag edit).
    /// Reads the file on a background thread to avoid blocking the main thread.
    func reindex(id: String, in directory: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let metadata = ContextCapture.read(id: id, from: directory) else { return }
            DispatchQueue.main.async { self?.add(metadata: metadata) }
        }
    }

    /// Called when history is cleared.
    func reset() {
        entries = []
        isLoaded = false
        isLoading = false
        pendingCallbacks = []
        loadGeneration += 1
    }
}
