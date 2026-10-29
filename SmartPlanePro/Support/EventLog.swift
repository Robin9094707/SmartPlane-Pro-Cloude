import Foundation
import Observation

/// App-wide event log. Everything Bluetooth related ends up here so the
/// "Labor" tab can show a complete, exportable protocol trace.
@Observable
final class EventLog {
    enum Level: String, CaseIterable, Codable {
        case debug, info, tx, rx, warning, error

        var symbol: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .tx: return "arrow.up.circle"
            case .rx: return "arrow.down.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String
    }

    static let shared = EventLog()

    private(set) var entries: [Entry] = []
    var maxEntries = 3000
    /// Control-loop writes happen 25x per second; they are only logged when enabled.
    var logControlTraffic = false

    func add(_ level: Level, _ category: String, _ message: String) {
        let entry = Entry(date: Date(), level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        #if DEBUG
        print("[\(category)] \(level.rawValue.uppercased()): \(message)")
        #endif
    }

    func clear() { entries.removeAll() }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map {
            "\(formatter.string(from: $0.date)) [\($0.category)] \($0.level.rawValue.uppercased()) \($0.message)"
        }.joined(separator: "\n")
    }
}

func appLog(_ level: EventLog.Level, _ category: String, _ message: String) {
    EventLog.shared.add(level, category, message)
}
