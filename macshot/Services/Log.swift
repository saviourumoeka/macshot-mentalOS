import Foundation
import os

/// Structured logging for macshot + MentalOS.
///
/// Two destinations for every event:
///   1. `os.Logger` (visible in Console.app, filterable by subsystem/category).
///   2. JSON-lines file at `~/Library/Logs/com.sw33tlie.macshot/macshot.log` —
///      sandboxed apps resolve this to
///      `~/Library/Containers/com.sw33tlie.macshot.macshot/Data/Library/Logs/com.sw33tlie.macshot/macshot.log`.
///      Tail with: `tail -f "$(getconf DARWIN_USER_DIR)..."` — see the
///      `logFileURL()` static for the exact path at runtime.
///
/// Daily rotation: on first write of the day, if today's date differs from
/// the existing file's mtime date, the file is renamed to
/// `macshot-YYYY-MM-DD.log` and a fresh `macshot.log` is started. The 8
/// most-recent rotated files (plus the live one) are kept; older ones are
/// pruned at next rotation.
enum Log {

    static let subsystem = "com.sw33tlie.macshot"

    enum Category: String {
        case capture, ocr, enrichment, ai, workspace, ui, app
    }

    enum Level: String { case debug, info, warn, error }

    // Loggers are lazily created per-category and cached.
    private static var loggers: [Category: Logger] = [:]
    private static let loggerLock = NSLock()

    private static func logger(for category: Category) -> Logger {
        loggerLock.lock(); defer { loggerLock.unlock() }
        if let cached = loggers[category] { return cached }
        let l = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = l
        return l
    }

    // MARK: - Public API

    static func debug(_ message: String, category: Category = .app, _ context: [String: Any] = [:]) {
        emit(.debug, category: category, message: message, context: context)
    }

    static func info(_ message: String, category: Category = .app, _ context: [String: Any] = [:]) {
        emit(.info, category: category, message: message, context: context)
    }

    static func warn(_ message: String, category: Category = .app, _ context: [String: Any] = [:]) {
        emit(.warn, category: category, message: message, context: context)
    }

    static func error(_ message: String, category: Category = .app, _ context: [String: Any] = [:]) {
        emit(.error, category: category, message: message, context: context)
    }

    /// Convenience that flattens an `Error` into the context dict.
    static func error(_ message: String, category: Category = .app, error: Error, _ extra: [String: Any] = [:]) {
        var ctx = extra
        ctx["error"] = String(describing: error)
        ctx["error_localized"] = error.localizedDescription
        emit(.error, category: category, message: message, context: ctx)
    }

    /// Resolved on-disk path to the live log file. Useful for "Open log file"
    /// in Settings and for documenting what to `tail`.
    static func logFileURL() -> URL {
        return logDirectory().appendingPathComponent("macshot.log")
    }

    // MARK: - Implementation

    private static func emit(_ level: Level, category: Category, message: String, context: [String: Any]) {
        let log = logger(for: category)
        let summary = context.isEmpty ? message : "\(message) \(context)"
        switch level {
        case .debug: log.debug("\(summary, privacy: .public)")
        case .info: log.info("\(summary, privacy: .public)")
        case .warn: log.warning("\(summary, privacy: .public)")
        case .error: log.error("\(summary, privacy: .public)")
        }
        fileWriter.append(level: level, category: category, message: message, context: context)
    }

    private static let fileWriter = FileWriter()

    fileprivate static func logDirectory() -> URL {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let dir = library
            .appendingPathComponent("Logs")
            .appendingPathComponent("com.sw33tlie.macshot")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Serialised JSON-lines writer with date-based rotation.
private final class FileWriter {

    private let queue = DispatchQueue(label: "com.sw33tlie.macshot.log.file", qos: .utility)
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var currentDay: String?
    private let maxRotatedFiles = 8

    func append(level: Log.Level, category: Log.Category, message: String, context: [String: Any]) {
        let timestamp = isoFormatter.string(from: Date())
        // Build a sanitised payload that JSONSerialization can handle.
        var ctx: [String: Any] = [:]
        for (k, v) in context {
            ctx[k] = sanitise(v)
        }
        let payload: [String: Any] = [
            "ts": timestamp,
            "level": level.rawValue,
            "category": category.rawValue,
            "msg": message,
            "ctx": ctx,
        ]
        queue.async { [weak self] in
            self?.write(payload: payload)
        }
    }

    private func sanitise(_ value: Any) -> Any {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n
        case let b as Bool: return b
        case let i as Int: return i
        case let d as Double: return d
        case let u as URL: return u.path
        case let arr as [Any]: return arr.map { sanitise($0) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = sanitise(v) }
            return out
        default: return String(describing: value)
        }
    }

    private func write(payload: [String: Any]) {
        rotateIfNeeded()
        let url = Log.logFileURL()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        var line = data
        line.append(0x0A) // newline
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: line)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // Last-ditch fallback: nothing we can do — silent failure here is
            // acceptable because OSLog still received the event.
        }
    }

    private func rotateIfNeeded() {
        let today = dayFormatter.string(from: Date())
        let url = Log.logFileURL()
        let fm = FileManager.default

        // Determine the day stamp of the existing file from its modification date.
        var existingDay: String?
        if fm.fileExists(atPath: url.path),
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            existingDay = dayFormatter.string(from: mtime)
        }

        // Only rotate if a previous day's content exists.
        if let existing = existingDay, existing != today {
            let rotated = Log.logFileURL().deletingLastPathComponent()
                .appendingPathComponent("macshot-\(existing).log")
            try? fm.moveItem(at: url, to: rotated)
            pruneOldRotations()
        }
        currentDay = today
    }

    private func pruneOldRotations() {
        let dir = Log.logFileURL().deletingLastPathComponent()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let rotated = entries
            .filter { $0.lastPathComponent.hasPrefix("macshot-") && $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
        if rotated.count > maxRotatedFiles {
            for old in rotated.dropFirst(maxRotatedFiles) {
                try? fm.removeItem(at: old)
            }
        }
    }
}
