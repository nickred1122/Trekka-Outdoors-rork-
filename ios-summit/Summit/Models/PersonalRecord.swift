import Foundation

/// A best-ever performance found in the athlete's own recorded history.
///
/// Records are only ever derived from workouts that were actually recorded. A
/// split record needs a track with real timestamps behind it, so a session
/// imported from Health without one is counted for distance and climbing but
/// never credited with a race time it cannot prove.
nonisolated struct PersonalRecord: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case split
        case effort

        var sectionTitle: String {
            switch self {
            case .split: "Fastest splits"
            case .effort: "Biggest efforts"
            }
        }
    }

    var id: String
    var title: String
    var kind: Kind
    /// Trekka's own mark for the record.
    var glyph: TrekkaGlyph
    /// Already-formatted headline, e.g. `21:04` or `42.6`.
    var value: String
    var unit: String
    var achievedAt: Date
    var activityName: String
    var activityID: UUID?
    /// True while the record is younger than a month, so the list can say so.
    var isRecent: Bool {
        achievedAt > Date().addingTimeInterval(-30 * 86_400)
    }
}

/// The standard race distances a split record can be set over.
nonisolated enum RecordDistance: Double, CaseIterable, Sendable {
    case oneKilometre = 1000
    case oneMile = 1609.344
    case fiveK = 5000
    case tenK = 10000
    case halfMarathon = 21097.5
    case marathon = 42195

    var title: String {
        switch self {
        case .oneKilometre: "1 km"
        case .oneMile: "1 mile"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half marathon"
        case .marathon: "Marathon"
        }
    }
}

nonisolated enum PersonalRecords {
    /// Builds the full record book from an activity history.
    static func all(from activities: [ActivityRecord]) -> [PersonalRecord] {
        splits(from: activities) + efforts(from: activities)
    }

    // MARK: - Splits

    /// Fastest measured time over each standard distance.
    ///
    /// Only foot sports are considered — a 5K split on a bike is not the same
    /// record and pretending otherwise would flatter the number.
    static func splits(from activities: [ActivityRecord]) -> [PersonalRecord] {
        let onFoot = activities.filter { $0.activity != .ride }

        return RecordDistance.allCases.compactMap { target in
            var best: (seconds: TimeInterval, activity: ActivityRecord)?

            for activity in onFoot where activity.distance >= target.rawValue {
                guard let seconds = fastestWindow(of: target.rawValue, in: activity.track) else { continue }
                if best == nil || seconds < best!.seconds {
                    best = (seconds, activity)
                }
            }

            guard let best else { return nil }
            return PersonalRecord(
                id: "split-\(target.title)",
                title: target.title,
                kind: .split,
                glyph: .pace,
                value: Formatters.duration(best.seconds),
                unit: "",
                achievedAt: best.activity.startDate,
                activityName: best.activity.name,
                activityID: best.activity.id
            )
        }
    }

    /// Quickest continuous stretch covering `target` metres inside one track.
    ///
    /// Returns nil when the track has no timestamps, because without them there
    /// is no measured time to report.
    private static func fastestWindow(of target: Double, in track: [RoutePoint]) -> TimeInterval? {
        guard track.count > 2 else { return nil }
        let times = track.map(\.timestamp)
        guard times.allSatisfy({ $0 != nil }) else { return nil }

        let distances = RouteMath.cumulativeDistances(of: track)
        guard let total = distances.last, total >= target else { return nil }

        var best: TimeInterval?
        var left = 0

        for right in 1..<track.count {
            // Walk the left edge forward while the window is still long enough,
            // which keeps the whole scan linear.
            while distances[right] - distances[left + 1] >= target, left + 1 < right {
                left += 1
            }
            guard distances[right] - distances[left] >= target else { continue }
            guard let start = times[left] ?? nil, let end = times[right] ?? nil else { continue }
            let elapsed = end.timeIntervalSince(start)
            guard elapsed > 0 else { continue }
            if best == nil || elapsed < best! { best = elapsed }
        }

        return best
    }

    // MARK: - Efforts

    /// Single-session and single-week bests that need no track to be true.
    static func efforts(from activities: [ActivityRecord]) -> [PersonalRecord] {
        guard !activities.isEmpty else { return [] }
        var records: [PersonalRecord] = []

        if let longest = activities.max(by: { $0.distance < $1.distance }), longest.distance > 500 {
            records.append(
                PersonalRecord(
                    id: "effort-distance",
                    title: "Longest distance",
                    kind: .effort,
                    glyph: .distance,
                    value: Formatters.distance(longest.distance),
                    unit: Formatters.units.distanceUnit,
                    achievedAt: longest.startDate,
                    activityName: longest.name,
                    activityID: longest.id
                )
            )
        }

        if let highest = activities.max(by: { $0.elevationGain < $1.elevationGain }), highest.elevationGain > 50 {
            records.append(
                PersonalRecord(
                    id: "effort-ascent",
                    title: "Most climbing",
                    kind: .effort,
                    glyph: .elevation,
                    value: Formatters.elevation(highest.elevationGain),
                    unit: Formatters.units.elevationUnit,
                    achievedAt: highest.startDate,
                    activityName: highest.name,
                    activityID: highest.id
                )
            )
        }

        if let longestTime = activities.max(by: { $0.duration < $1.duration }), longestTime.duration > 600 {
            records.append(
                PersonalRecord(
                    id: "effort-duration",
                    title: "Longest time",
                    kind: .effort,
                    glyph: .pace,
                    value: Formatters.compactDuration(longestTime.duration),
                    unit: "",
                    achievedAt: longestTime.startDate,
                    activityName: longestTime.name,
                    activityID: longestTime.id
                )
            )
        }

        if let week = biggestWeek(in: activities) {
            records.append(week)
        }

        return records
    }

    /// The seven-day window in which the most ground was covered.
    private static func biggestWeek(in activities: [ActivityRecord]) -> PersonalRecord? {
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        guard sorted.count > 1 else { return nil }

        var best: (distance: Double, end: Date)?
        var left = 0
        var running: Double = 0

        for right in sorted.indices {
            running += sorted[right].distance
            while sorted[right].startDate.timeIntervalSince(sorted[left].startDate) > 7 * 86_400 {
                running -= sorted[left].distance
                left += 1
            }
            if best == nil || running > best!.distance {
                best = (running, sorted[right].startDate)
            }
        }

        guard let best, best.distance > 1000 else { return nil }
        return PersonalRecord(
            id: "effort-week",
            title: "Biggest week",
            kind: .effort,
            glyph: .load,
            value: Formatters.distance(best.distance),
            unit: Formatters.units.distanceUnit,
            achievedAt: best.end,
            activityName: "Seven days to \(best.end.formatted(date: .abbreviated, time: .omitted))",
            activityID: nil
        )
    }
}
