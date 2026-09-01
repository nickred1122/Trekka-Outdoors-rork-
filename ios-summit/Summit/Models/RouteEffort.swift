import Foundation
import CoreLocation

/// One completed run of a saved route, ranked against every other run of it.
nonisolated struct RouteEffort: Identifiable, Sendable, Hashable {
    var id: UUID
    var activityName: String
    var date: Date
    var duration: TimeInterval
    var distance: Double
    var averageHeartRate: Double
    /// 1 for the fastest recorded time on this route.
    var rank: Int
    /// How much slower than the best this one was. Zero for the best itself.
    var behindBest: TimeInterval
    /// Share of the route actually covered, 0–1.
    var coverage: Double

    var isPersonalBest: Bool { rank == 1 }

    var pace: TimeInterval {
        guard distance > 100 else { return 0 }
        return duration / (distance / 1000)
    }
}

/// Matches recorded workouts against a saved route, so a route can show your
/// own history on it rather than only its shape.
///
/// A workout counts as a run of the route only when the two genuinely covered
/// the same ground — both directions are checked, because a track that merely
/// crosses the route, or runs along a third of it, is not the same effort and
/// ranking it against a full lap would be a lie.
nonisolated enum RouteEfforts {
    /// How close a point has to pass to count as being on the route.
    ///
    /// Generous enough for GPS drift under trees and for the difference between
    /// a planned centreline and the path actually trodden; tight enough that a
    /// parallel road does not count as the trail.
    private static let corridorMetres: Double = 45

    /// How much of the route has to be covered, and how much of the workout has
    /// to have stayed on it. Both matter: the first stops a half-lap counting,
    /// the second stops a long run that happens to include the route counting as
    /// a run of it.
    private static let requiredRouteCoverage: Double = 0.85
    private static let requiredTrackContainment: Double = 0.70

    /// Comparing every point against every point is quadratic, so both lines are
    /// thinned to this many samples first. At 300 the spacing on a 10 km route is
    /// about 33 m, well inside the corridor, so thinning cannot change the verdict.
    private static let sampleLimit = 300

    /// Every recorded effort on `route`, fastest first.
    static func efforts(on route: PlannedRoute, from activities: [ActivityRecord]) -> [RouteEffort] {
        let routeSamples = sampled(route.points)
        guard routeSamples.count > 2 else { return [] }

        // Only sessions of a plausible length are even considered, so a 400 m
        // warm-up cannot be matched against a 12 km route.
        let routeDistance = route.distance
        guard routeDistance > 200 else { return [] }

        var matches: [(activity: ActivityRecord, coverage: Double)] = []
        for activity in activities where !activity.track.isEmpty {
            // A session far shorter than the route cannot have covered it, and
            // checking that first skips the expensive comparison entirely.
            guard activity.distance >= routeDistance * 0.7 else { continue }
            let trackSamples = sampled(activity.track)
            guard trackSamples.count > 2 else { continue }

            let coverage = fraction(of: routeSamples, within: trackSamples)
            guard coverage >= requiredRouteCoverage else { continue }

            let containment = fraction(of: trackSamples, within: routeSamples)
            guard containment >= requiredTrackContainment else { continue }

            matches.append((activity, coverage))
        }

        let ranked = matches.sorted { $0.activity.duration < $1.activity.duration }
        guard let best = ranked.first else { return [] }

        return ranked.enumerated().map { index, match in
            RouteEffort(
                id: match.activity.id,
                activityName: match.activity.name,
                date: match.activity.startDate,
                duration: match.activity.duration,
                distance: match.activity.distance,
                averageHeartRate: match.activity.averageHeartRate,
                rank: index + 1,
                behindBest: match.activity.duration - best.activity.duration,
                coverage: match.coverage
            )
        }
    }

    /// Thins a line to at most `sampleLimit` evenly spaced points.
    private static func sampled(_ points: [RoutePoint]) -> [CLLocationCoordinate2D] {
        guard points.count > sampleLimit else { return points.map(\.coordinate) }
        let stride = Double(points.count - 1) / Double(sampleLimit - 1)
        return (0..<sampleLimit).map { index in
            points[Int((Double(index) * stride).rounded())].coordinate
        }
    }

    /// Share of `subject` points that pass within the corridor of `reference`.
    ///
    /// A bounding-box reject comes first: most comparisons are between lines in
    /// completely different places, and a cheap degree-space test throws those
    /// out before any distance is computed.
    private static func fraction(
        of subject: [CLLocationCoordinate2D],
        within reference: [CLLocationCoordinate2D]
    ) -> Double {
        guard !subject.isEmpty, !reference.isEmpty else { return 0 }

        // One degree of latitude is ~111 km everywhere; longitude shrinks with
        // the cosine of latitude. Converting the corridor into degrees once lets
        // the inner loop stay in plain arithmetic.
        let midLatitude = reference[reference.count / 2].latitude
        let latitudeDegrees = corridorMetres / 111_000
        let longitudeDegrees = corridorMetres / (111_000 * max(0.1, cos(midLatitude * .pi / 180)))

        var hits = 0
        for point in subject {
            var isNear = false
            for candidate in reference {
                guard abs(candidate.latitude - point.latitude) <= latitudeDegrees,
                      abs(candidate.longitude - point.longitude) <= longitudeDegrees else { continue }
                isNear = true
                break
            }
            if isNear { hits += 1 }
        }
        return Double(hits) / Double(subject.count)
    }
}
