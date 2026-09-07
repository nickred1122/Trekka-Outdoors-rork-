import Foundation
import SwiftUI

/// One stage of a night, as Apple Health records it.
///
/// The app used to collapse all four asleep values into a single total the
/// moment they were read, which is why the sleep tile could only ever say how
/// long you slept. The stages were always there in Health; they were being
/// discarded on the way in.
nonisolated enum SleepStage: String, Sendable, CaseIterable, Identifiable {
    case awake
    case rem
    case core
    case deep
    /// Recorded as asleep with no stage attached — a manual entry, or a tracker
    /// that does not detect stages. Kept separate rather than quietly counted as
    /// core, because guessing which stage it was would be inventing data.
    case unspecified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Asleep"
        }
    }

    /// Plain-language meaning, for the legend.
    var meaning: String {
        switch self {
        case .awake: "Brief wakings — normal in small amounts"
        case .rem: "Dreaming sleep, where memory consolidates"
        case .core: "The bulk of the night"
        case .deep: "Physical recovery happens here"
        case .unspecified: "Recorded without stage detail"
        }
    }

    var tint: Color {
        switch self {
        case .awake: Color(red: 0.98, green: 0.62, blue: 0.28)
        case .rem: Color(red: 0.35, green: 0.72, blue: 0.96)
        case .core: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .deep: Color(red: 0.29, green: 0.24, blue: 0.72)
        case .unspecified: Color(red: 0.55, green: 0.55, blue: 0.62)
        }
    }

    /// Row in the hypnogram, shallowest at the top — the convention every sleep
    /// chart uses, so the shape reads the way people expect.
    var lane: Int {
        switch self {
        case .awake: 0
        case .rem: 1
        case .core, .unspecified: 2
        case .deep: 3
        }
    }

    /// Which stage wins when two trackers describe the same minute differently.
    ///
    /// Being asleep beats being awake, and a named stage beats an unnamed one.
    /// Without this, a phone that only knows "in bed" could overwrite the
    /// watch's actual stage detail for the same minute.
    var confidence: Int {
        switch self {
        case .deep: 5
        case .rem: 4
        case .core: 3
        case .unspecified: 2
        case .awake: 1
        }
    }

    var isAsleep: Bool { self != .awake }

    /// The lanes drawn in a hypnogram, top to bottom.
    static let lanes: [SleepStage] = [.awake, .rem, .core, .deep]
}

/// A single continuous stretch of one stage.
nonisolated struct SleepSegment: Sendable, Equatable, Identifiable {
    let stage: SleepStage
    let start: Date
    let end: Date

    var id: String { "\(stage.rawValue)-\(start.timeIntervalSince1970)" }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One night, stage by stage.
nonisolated struct SleepNight: Sendable, Equatable {
    var segments: [SleepSegment] = []

    static let empty = SleepNight()

    var isEmpty: Bool { segments.isEmpty }

    /// When the night began and ended. Nil for a night with nothing recorded.
    var bedtime: Date? { segments.first?.start }
    var wakeTime: Date? { segments.last?.end }

    /// True when a tracker actually detected stages, rather than only logging
    /// that you were asleep. Drives whether the hypnogram is worth drawing.
    var hasStageDetail: Bool {
        segments.contains { $0.stage == .rem || $0.stage == .deep }
    }

    func total(_ stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var asleepSeconds: TimeInterval {
        segments.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
    }

    /// Bedtime to waking, including time spent awake in between.
    var timeInBedSeconds: TimeInterval {
        guard let bedtime, let wakeTime else { return 0 }
        return wakeTime.timeIntervalSince(bedtime)
    }

    /// Share of the night actually spent asleep.
    var efficiency: Double {
        guard timeInBedSeconds > 0 else { return 0 }
        return min(1, asleepSeconds / timeInBedSeconds)
    }

    /// Wakings long enough to notice, not counting finally getting up.
    ///
    /// A few seconds of movement registers as awake on any tracker, so counting
    /// every one of those would report a broken night to someone who slept
    /// straight through.
    var awakenings: Int {
        segments
            .dropLast()
            .filter { $0.stage == .awake && $0.duration >= 300 }
            .count
    }

    func fraction(_ stage: SleepStage) -> Double {
        guard asleepSeconds > 0 else { return 0 }
        return total(stage) / asleepSeconds
    }

    /// A quality score out of 100, built only from what was actually measured.
    ///
    /// Duration carries the most weight because it is the one input every
    /// tracker records. Deep and REM are scored against the share of a night
    /// they normally occupy in a healthy adult — roughly 13-23% deep and 20-25%
    /// REM — and reaching that band is full marks rather than more being better.
    /// When no stages were detected the score falls back to duration alone,
    /// rescaled so a full night still reads as a good one.
    var quality: Int {
        guard asleepSeconds > 0 else { return 0 }
        let hours = asleepSeconds / 3600
        let durationPoints = min(1, hours / 8) * (hasStageDetail ? 50 : 92)

        guard hasStageDetail else {
            return max(20, min(100, Int(durationPoints.rounded())))
        }

        let deepPoints = min(1, fraction(.deep) / 0.13) * 20
        let remPoints = min(1, fraction(.rem) / 0.20) * 20
        let continuityPoints = efficiency * 10
        let raw = durationPoints + deepPoints + remPoints + continuityPoints
        return max(1, min(100, Int(raw.rounded())))
    }

    /// One honest line about the night, naming whichever thing stands out.
    var summary: String {
        guard asleepSeconds > 0 else { return "No sleep recorded" }
        guard hasStageDetail else {
            return "Recorded without stage detail, so only duration is known"
        }
        if fraction(.deep) < 0.10 {
            return "Light on deep sleep, the stage that repairs muscle"
        }
        if fraction(.rem) < 0.15 {
            return "Short on REM, which usually means a late night or a drink"
        }
        if awakenings >= 3 {
            return "Broken by \(awakenings) wakings, so it counted for less than its length"
        }
        if efficiency > 0.9, asleepSeconds >= 7 * 3600 {
            return "Long and unbroken — the best kind of night"
        }
        return "A balanced night across all three stages"
    }

    /// Builds a night from overlapping samples, resolving disagreements.
    ///
    /// Apple Watch, iPhone and any third-party sleep app each write their own
    /// samples for the same night. Adding them up would count the same minutes
    /// two or three times over, so the timeline is cut at every boundary and
    /// each slice is awarded to the most confident stage covering it.
    static func resolving(_ samples: [(stage: SleepStage, start: Date, end: Date)]) -> SleepNight {
        let valid = samples.filter { $0.end > $0.start }
        guard !valid.isEmpty else { return .empty }

        let boundaries = Set(valid.flatMap { [$0.start, $0.end] }).sorted()
        guard boundaries.count > 1 else { return .empty }

        var resolved: [SleepSegment] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }

            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let covering = valid.filter { $0.start <= midpoint && $0.end > midpoint }
            guard let winner = covering.max(by: { $0.stage.confidence < $1.stage.confidence }) else { continue }

            // Join onto the previous slice when it is the same stage and there is
            // no gap, so one continuous stretch stays one segment.
            if let last = resolved.last, last.stage == winner.stage, last.end == start {
                resolved[resolved.count - 1] = SleepSegment(stage: last.stage, start: last.start, end: end)
            } else {
                resolved.append(SleepSegment(stage: winner.stage, start: start, end: end))
            }
        }

        // A night is bracketed by sleep, not by a stray awake reading before bed
        // or after getting up.
        while let first = resolved.first, !first.stage.isAsleep {
            resolved.removeFirst()
        }
        while let last = resolved.last, !last.stage.isAsleep {
            resolved.removeLast()
        }

        return SleepNight(segments: resolved)
    }
}
