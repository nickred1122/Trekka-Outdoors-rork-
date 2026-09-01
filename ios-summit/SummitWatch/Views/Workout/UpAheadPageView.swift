import SwiftUI

/// Everything still to come on the course, in the order you will reach it.
///
/// Waypoints come from the course you loaded; summits are read off its surveyed
/// profile. Arrival times are only shown once you are actually moving, and they
/// are your own average pace carried forward — never a guess about terrain.
struct UpAheadPageView: View {
    let route: WatchRoute?
    let metrics: LiveMetrics

    /// One thing to reach: a named waypoint, a summit, or the finish.
    private struct CoursePoint: Identifiable {
        enum Kind {
            case waypoint, summit, finish

            var symbol: String {
                switch self {
                case .waypoint: "mappin.circle.fill"
                case .summit: "triangle.fill"
                case .finish: "flag.checkered"
                }
            }

            var tint: Color {
                switch self {
                case .waypoint: WatchTheme.accent
                case .summit: WatchTheme.highlight
                case .finish: WatchTheme.positive
                }
            }
        }

        var id: String
        var name: String
        var kind: Kind
        var distanceAlongRoute: Double
        /// Height gain still to come before this point, when it is a summit.
        var climbTo: Double?
    }

    private var points: [CoursePoint] {
        guard let route, route.points.count > 1 else { return [] }

        var all: [CoursePoint] = route.waypoints.map { waypoint in
            CoursePoint(
                id: waypoint.id.uuidString,
                name: waypoint.name,
                kind: .waypoint,
                distanceAlongRoute: waypoint.distanceAlongRoute,
                climbTo: nil
            )
        }

        let climbs = ClimbFinder.climbs(
            distances: WatchRouteMath.cumulativeDistances(of: route.points),
            elevations: route.points.map(\.elevation)
        )
        for climb in climbs {
            all.append(
                CoursePoint(
                    id: "climb-\(climb.id)",
                    name: "\(climb.category.label) summit",
                    kind: .summit,
                    distanceAlongRoute: climb.endDistance,
                    climbTo: climb.gain
                )
            )
        }

        all.append(
            CoursePoint(
                id: "finish",
                name: "Finish",
                kind: .finish,
                distanceAlongRoute: route.distance,
                climbTo: nil
            )
        )

        return all
            .filter { $0.distanceAlongRoute > metrics.courseDistance + 20 }
            .sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }

    var body: some View {
        Group {
            if points.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(4)) {
                ForEach(points.prefix(12)) { point in
                    row(point)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ point: CoursePoint) -> some View {
        let togo = max(0, point.distanceAlongRoute - metrics.courseDistance)

        return HStack(spacing: WatchDisplay.spacing(7)) {
            Image(systemName: point.kind.symbol)
                .font(.watch(10, weight: .bold))
                .foregroundStyle(point.kind.tint)
                .frame(width: WatchDisplay.scaled(14, atLeast: 12))

            VStack(alignment: .leading, spacing: 0) {
                Text(point.name)
                    .font(.watch(11, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let climb = point.climbTo {
                    Text("+\(WatchFormat.elevation(climb)) \(WatchFormat.units.elevationUnit)")
                        .font(.watch(8, weight: .medium))
                        .foregroundStyle(WatchTheme.textSecondary)
                } else if let arrival = arrival(in: togo) {
                    Text(arrival)
                        .font(.watch(8, weight: .medium))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 0) {
                Text(WatchFormat.shortDistance(togo))
                    .font(.metric(14, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Text(WatchFormat.shortDistanceUnit(togo))
                    .font(.watch(8, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, WatchDisplay.spacing(8))
        .padding(.vertical, WatchDisplay.spacing(5))
        .frame(maxWidth: .infinity)
        .watchPanel()
    }

    /// Clock time you would arrive at your average pace so far. Nothing is shown
    /// until enough of the workout has been recorded for that pace to mean
    /// something.
    private func arrival(in metres: Double) -> String? {
        let speed = metrics.averageSpeed
        guard speed > 0.4, metrics.distance > 200 else { return nil }
        let seconds = metres / speed
        guard seconds.isFinite, seconds < 86_400 else { return nil }
        return WatchFormat.clock(Date().addingTimeInterval(seconds))
    }

    private var empty: some View {
        VStack(spacing: WatchDisplay.spacing(5)) {
            Image(systemName: "flag.checkered")
                .font(.title3)
                .foregroundStyle(WatchTheme.textSecondary)
            Text(route == nil ? "No course loaded" : "Nothing left ahead")
                .font(.watch(11, weight: .semibold))
                .foregroundStyle(WatchTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
