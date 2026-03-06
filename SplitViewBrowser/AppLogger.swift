import Foundation
import OSLog

@MainActor
final class AppLogger: ObservableObject {
    enum Level: String, CaseIterable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        var timestamp: Date
        var level: Level
        var category: String
        var message: String
        var repeatCount: Int = 1
    }

    static let shared = AppLogger()

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "com.pdg.SplitViewBrowser", category: "App")
    private let maxEntries = 250
    private static let joinedTextDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func log(_ level: Level, category: String, _ message: String) {
        let now = Date()
        if let lastIndex = entries.indices.last {
            let lastEntry = entries[lastIndex]
            let isDuplicate =
                lastEntry.level == level &&
                lastEntry.category == category &&
                lastEntry.message == message &&
                now.timeIntervalSince(lastEntry.timestamp) < 1.0
            if isDuplicate {
                entries[lastIndex].timestamp = now
                entries[lastIndex].repeatCount += 1
            } else {
                let entry = Entry(timestamp: now, level: level, category: category, message: message)
                entries.append(entry)
            }
        } else {
            let entry = Entry(timestamp: now, level: level, category: category, message: message)
            entries.append(entry)
        }

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        switch level {
        case .info:
            logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning:
            logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error:
            logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
    }

    func clear() {
        entries.removeAll()
    }

    func joinedText() -> String {
        return entries.map { entry in
            let suffix = entry.repeatCount > 1 ? " (x\(entry.repeatCount))" : ""
            return "\(Self.joinedTextDateFormatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)\(suffix)"
        }.joined(separator: "\n")
    }
}
