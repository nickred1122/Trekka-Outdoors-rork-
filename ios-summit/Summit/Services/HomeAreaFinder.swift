import Foundation
import CoreLocation

/// A place the athlete keeps setting off from.
nonisolated struct HomeArea: Sendable, Hashable {
    let centre: CLLocationCoordinate2D
    /// How many recorded outings started here.
    let visits: Int
    /// Borrowed from the most recent activity that began here, so the pack has
    /// a name a human recognises rather than a coordinate.
    let name: String

    static func == (lhs: HomeArea, rhs: HomeArea) -> Bool {
        lhs.centre.latitude == rhs.centre.latitude
            && lhs.centre.longitude == rhs.centre.longitude
            && lhs.visits == rhs.visits
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(centre.latitude)
        hasher.combine(centre.longitude)
        hasher.combine(visits)
    }
}

/// Finds the trailheads an athlete returns to.
///
/// The point is to have ground ready for the outing nobody planned — walking out
/// of the front door, or driving to the same forest car park every Saturday. A
/// place only qualifies once it has been used more than once, so a single trip
/// away from home never quietly costs storage.
nonisolated enum HomeAreaFinder {
    /// Starts within this distance of each other count as the same place.
    static let clusterRadiusMetres: Double = 1_500

    /// How many separate outings make somewhere a regular haunt.
    static let visitThreshold = 2

    /// Only recent history counts, so a place the athlete has moved away from
    /// stops being kept ready.
    static let lookbackDays: Double = 120

    /// The athlete's regular starting places, most used first.
    static func areas(from activities: [ActivityRecord], now: Date = Date()) -> [HomeArea] {
        let cutoff = now.addingTimeInterval(-lookbackDays * 86_400)

        // Newest first, so a cluster takes its name from the most recent outing.
        let starts: [(coordinate: CLLocationCoordinate2D, name: String)] = activities
            .filter { $0.startDate >= cutoff }
            .sorted { $0.startDate > $1.startDate }
            .compactMap { activity in
                guard let first = activity.track.first else { return nil }
                return (first.coordinate, activity.name)
            }

        guard !starts.isEmpty else { return [] }

        var clusters: [(sumLatitude: Double, sumLongitude: Double, count: Int, name: String)] = []

        for start in starts {
            let location = CLLocation(latitude: start.coordinate.latitude, longitude: start.coordinate.longitude)
            var matched = false

            for index in clusters.indices {
                let centre = CLLocation(
                    latitude: clusters[index].sumLatitude / Double(clusters[index].count),
                    longitude: clusters[index].sumLongitude / Double(clusters[index].count)
                )
                if location.distance(from: centre) <= clusterRadiusMetres {
                    clusters[index].sumLatitude += start.coordinate.latitude
                    clusters[index].sumLongitude += start.coordinate.longitude
                    clusters[index].count += 1
                    matched = true
                    break
                }
            }

            if !matched {
                clusters.append((start.coordinate.latitude, start.coordinate.longitude, 1, start.name))
            }
        }

        return clusters
            .filter { $0.count >= visitThreshold }
            .map { cluster in
                HomeArea(
                    centre: CLLocationCoordinate2D(
                        latitude: cluster.sumLatitude / Double(cluster.count),
                        longitude: cluster.sumLongitude / Double(cluster.count)
                    ),
                    visits: cluster.count,
                    name: Self.placeName(from: cluster.name)
                )
            }
            .sorted { $0.visits > $1.visits }
    }

    /// Turns an activity's name into something that reads as a place.
    ///
    /// Activity names carry the time of day — "Morning Trail Run" — which makes
    /// no sense on a stored area, so that part is dropped.
    private static func placeName(from activityName: String) -> String {
        let periods = ["Morning", "Midday", "Afternoon", "Evening", "Night"]
        var trimmed = activityName
        for period in periods where trimmed.hasPrefix("\(period) ") {
            trimmed = String(trimmed.dropFirst(period.count + 1))
            break
        }
        let cleaned = trimmed.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Usual start" : "Around \(cleaned)"
    }
}
