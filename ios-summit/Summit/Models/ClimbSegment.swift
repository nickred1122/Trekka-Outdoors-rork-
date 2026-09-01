import Foundation

/// A sustained climb found in a route's elevation profile.
///
/// Climbs are detected from surveyed elevation on the route itself, so every
/// number here — length, gain, gradient — is measured rather than guessed.
///
/// Duplicated verbatim from `SummitWatch/Models/ClimbSegment.swift`; the watch
/// is a separate binary, so the two copies must stay identical.
nonisolated struct ClimbSegment: Identifiable, Hashable, Sendable {
    var id: Int
    /// Distance from the route start where the climb begins, in metres.
    var startDistance: Double
    /// Distance from the route start where the climb tops out, in metres.
    var endDistance: Double
    var startElevation: Double
    var summitElevation: Double
    /// Steepest sustained stretch inside the climb, as a percentage.
    var maxGrade: Double

    var length: Double { max(0, endDistance - startDistance) }
    var gain: Double { max(0, summitElevation - startElevation) }

    /// Average gradient across the whole climb, as a percentage.
    var averageGrade: Double {
        length > 0 ? gain / length * 100 : 0
    }

    /// Difficulty score: metres gained multiplied by the average gradient. The
    /// same shape cycling uses to categorise passes, so a long shallow drag and
    /// a short wall are ranked by the work each actually costs.
    var score: Double { gain * averageGrade }

    var category: ClimbCategory { ClimbCategory(score: score) }

    /// How far into the climb a given course position sits, 0 to 1.
    func progress(at distanceAlongRoute: Double) -> Double {
        guard length > 0 else { return 0 }
        return min(1, max(0, (distanceAlongRoute - startDistance) / length))
    }

    func contains(_ distanceAlongRoute: Double) -> Bool {
        distanceAlongRoute >= startDistance && distanceAlongRoute < endDistance
    }
}

nonisolated enum ClimbCategory: Int, Sendable, CaseIterable {
    case four = 4, three = 3, two = 2, one = 1, hors = 0

    init(score: Double) {
        switch score {
        case ..<2500: self = .four
        case ..<5000: self = .three
        case ..<9000: self = .two
        case ..<16000: self = .one
        default: self = .hors
        }
    }

    var label: String {
        switch self {
        case .four: "Cat 4"
        case .three: "Cat 3"
        case .two: "Cat 2"
        case .one: "Cat 1"
        case .hors: "HC"
        }
    }

    /// Plain-language read on what the climb will actually cost.
    var summary: String {
        switch self {
        case .four: "A short pull"
        case .three: "A real climb"
        case .two: "A long climb"
        case .one: "A hard climb"
        case .hors: "Beyond category"
        }
    }

    /// Steadily hotter as the climb gets harder.
    var tintIndex: Int {
        switch self {
        case .four: 0
        case .three: 1
        case .two: 2
        case .one: 3
        case .hors: 4
        }
    }
}

nonisolated enum ClimbFinder {
    /// A stretch has to gain this much to count as a climb at all.
    static let minimumGain: Double = 25
    /// …at least this steep on average.
    static let minimumGrade: Double = 2.5
    /// Dips shorter than this don't end a climb — a false flat mid-ascent is
    /// still the same climb to the legs.
    static let mergeDistance: Double = 250
    /// …unless they give back more than this much height.
    static let mergeDrop: Double = 20

    /// Finds every climb in a profile of (distance from start, elevation) pairs.
    ///
    /// Both values must already be in metres and sorted by distance.
    static func climbs(distances: [Double], elevations: [Double]) -> [ClimbSegment] {
        guard distances.count == elevations.count, distances.count > 2 else { return [] }

        // Smooth first: raw barometric and DEM samples jitter enough that every
        // rolling metre would otherwise register as its own climb.
        let smoothed = smooth(elevations)

        var raw: [(start: Int, end: Int)] = []
        var startIndex = 0
        var rising = false

        for index in 1..<smoothed.count {
            let delta = smoothed[index] - smoothed[index - 1]
            if delta > 0 {
                if !rising {
                    rising = true
                    startIndex = index - 1
                }
            } else if rising {
                rising = false
                raw.append((startIndex, index - 1))
            }
        }
        if rising { raw.append((startIndex, smoothed.count - 1)) }

        let merged = merge(raw, distances: distances, elevations: smoothed)

        return merged.enumerated().compactMap { order, span in
            let gain = smoothed[span.end] - smoothed[span.start]
            let length = distances[span.end] - distances[span.start]
            guard gain >= minimumGain, length > 0 else { return nil }
            guard gain / length * 100 >= minimumGrade else { return nil }

            return ClimbSegment(
                id: order,
                startDistance: distances[span.start],
                endDistance: distances[span.end],
                startElevation: smoothed[span.start],
                summitElevation: smoothed[span.end],
                maxGrade: steepestGrade(from: span.start, to: span.end, distances: distances, elevations: smoothed)
            )
        }
    }

    /// Joins ascents separated only by a brief dip or flat.
    private static func merge(
        _ spans: [(start: Int, end: Int)],
        distances: [Double],
        elevations: [Double]
    ) -> [(start: Int, end: Int)] {
        var merged: [(start: Int, end: Int)] = []
        for span in spans {
            guard var last = merged.last else {
                merged.append(span)
                continue
            }
            let gapDistance = distances[span.start] - distances[last.end]
            let drop = elevations[last.end] - elevations[span.start]
            if gapDistance <= mergeDistance, drop <= mergeDrop {
                last.end = span.end
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// Steepest 100 m-ish window inside the climb.
    private static func steepestGrade(
        from start: Int,
        to end: Int,
        distances: [Double],
        elevations: [Double]
    ) -> Double {
        guard end > start else { return 0 }
        var steepest: Double = 0
        var left = start
        for right in (start + 1)...end {
            while distances[right] - distances[left] > 120, left < right - 1 { left += 1 }
            let run = distances[right] - distances[left]
            guard run >= 40 else { continue }
            let rise = elevations[right] - elevations[left]
            steepest = max(steepest, rise / run * 100)
        }
        return steepest
    }

    /// Five-sample moving average.
    private static func smooth(_ values: [Double]) -> [Double] {
        guard values.count > 4 else { return values }
        return values.indices.map { index in
            let lower = max(0, index - 2)
            let upper = min(values.count - 1, index + 2)
            let window = values[lower...upper]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}

extension PlannedRoute {
    /// Every sustained climb on this route, in the order they are ridden or run.
    var climbs: [ClimbSegment] {
        ClimbFinder.climbs(
            distances: RouteMath.cumulativeDistances(of: points),
            elevations: points.map(\.elevation)
        )
    }
}
