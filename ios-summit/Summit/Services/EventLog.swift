import Foundation
import Observation

/// How much a recorded event matters.
nonisolated enum EventLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case info
    case warning
    case failure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .failure: "Failure"
        }
    }

    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .failure: "xmark.octagon"
        }
    }
}

/// One thing that happened, as it happened.
nonisolated struct LoggedEvent: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var at: Date = .now
    var level: EventLevel
    /// Which part of the app spoke — "Health", "Offline map", "Watch".
    var category: String
    var message: String
    /// The underlying reason, when there is one worth keeping.
    var detail: String?

    /// One line, for the copyable report.
    var line: String {
        let stamp = at.formatted(.iso8601.year().month().day().timeZone(separator: .omitted)
            .time(includingFractionalSeconds: false))
        let base = "\(stamp) [\(level.rawValue.uppercased())] \(category): \(message)"
        guard let detail, !detail.isEmpty else { return base }
        return base + " — " + detail
    }
}

/// A running record of what the app actually did, kept so a failure can be
/// reported rather than described from memory.
///
/// Deliberately not a crash reporter and not analytics: nothing leaves the
/// device unless the athlete copies it out themselves. It exists because "the
/// download didn't work" is impossible to act on, and "the download failed at
/// 14:02 with a network timeout after 340 of 900 tiles" is.
@Observable
final class EventLog {
    /// Reached directly by services rather than passed down through views, the
    /// same way the metric-style and unit holders are.
    static let shared = EventLog()

    private(set) var events: [LoggedEvent] = []

    /// Enough to cover a long day out without growing without bound.
    private static let limit = 400

    private let fileURL: URL? = {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return base.appendingPathComponent("trekka-events.json")
    }()

    init() {
        load()
    }

    var failureCount: Int {
        events.filter { $0.level == .failure }.count
    }

    /// Newest first, which is the order anybody diagnosing something reads in.
    var newestFirst: [LoggedEvent] {
        events.reversed()
    }

    func record(
        _ level: EventLevel,
        category: String,
        message: String,
        detail: String? = nil
    ) {
        events.append(
            LoggedEvent(level: level, category: category, message: message, detail: detail)
        )
        if events.count > Self.limit {
            events.removeFirst(events.count - Self.limit)
        }
        persist()
    }

    func info(_ category: String, _ message: String, detail: String? = nil) {
        record(.info, category: category, message: message, detail: detail)
    }

    func warning(_ category: String, _ message: String, detail: String? = nil) {
        record(.warning, category: category, message: message, detail: detail)
    }

    func failure(_ category: String, _ message: String, detail: String? = nil) {
        record(.failure, category: category, message: message, detail: detail)
    }

    func clear() {
        events = []
        persist()
    }

    /// The whole log as text, for pasting into a bug report.
    func report() -> String {
        guard !events.isEmpty else { return "No events recorded." }
        return newestFirst.map(\.line).joined(separator: "\n")
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        events = (try? JSONDecoder().decode([LoggedEvent].self, from: data)) ?? []
    }

    /// Written to disk so a failure survives the relaunch that often follows it.
    /// Failing to write the log must never itself become a problem, so this
    /// stays silent — there is nowhere left to report it to.
    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
