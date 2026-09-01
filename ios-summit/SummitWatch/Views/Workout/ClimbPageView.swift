import SwiftUI

/// The climb you are on: how much is left of it, how steep it stays, and what
/// is waiting after the summit.
///
/// Every figure is read off the loaded course's surveyed profile, so nothing
/// here is modelled — if the course has no climbs worth the name, the page says
/// so rather than inventing one.
struct ClimbPageView: View {
    let route: WatchRoute?
    let metrics: LiveMetrics

    private var climbs: [ClimbSegment] {
        guard let route, route.points.count > 2 else { return [] }
        return ClimbFinder.climbs(
            distances: WatchRouteMath.cumulativeDistances(of: route.points),
            elevations: route.points.map(\.elevation)
        )
    }

    private var progress: Double { metrics.courseDistance }

    private var current: ClimbSegment? {
        climbs.first { $0.contains(progress) }
    }

    private var next: ClimbSegment? {
        climbs.first { $0.startDistance > progress }
    }

    var body: some View {
        Group {
            if let current {
                onClimb(current)
            } else if let next {
                approaching(next)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - On a climb

    private func onClimb(_ climb: ClimbSegment) -> some View {
        let fraction = climb.progress(at: progress)
        let remaining = max(0, climb.endDistance - progress)
        let toGo = max(0, climb.summitElevation - metrics.altitude)

        return VStack(spacing: WatchDisplay.spacing(6)) {
            HStack(spacing: 5) {
                Text(climb.category.label)
                    .font(.watch(9, weight: .bold))
                    .foregroundStyle(WatchTheme.canvas)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tint(for: climb), in: .capsule)
                Text("\(WatchFormat.integer(fraction * 100))% up")
                    .font(.metric(10, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                Spacer(minLength: 0)
                Text("\(WatchFormat.decimal(climb.averageGrade, places: 1))% avg")
                    .font(.metric(10, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            profile(climb, fraction: fraction)

            HStack(spacing: WatchDisplay.spacing(6)) {
                readout(
                    "TO TOP",
                    value: WatchFormat.shortDistance(remaining),
                    unit: WatchFormat.shortDistanceUnit(remaining),
                    tint: WatchTheme.accent
                )
                readout(
                    "CLIMB LEFT",
                    value: WatchFormat.elevation(toGo),
                    unit: WatchFormat.units.elevationUnit,
                    tint: WatchTheme.highlight
                )
                readout(
                    "GRADE",
                    value: WatchFormat.signedDecimal(metrics.grade, places: 0),
                    unit: "%",
                    tint: gradeTint
                )
            }
        }
    }

    /// Bar chart of the climb, one slice per stretch, with the athlete's
    /// position filled in behind it.
    private func profile(_ climb: ClimbSegment, fraction: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(WatchTheme.surface)

                // A wedge that rises left to right, the way the climb does.
                Path { path in
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.closeSubpath()
                }
                .fill(tint(for: climb).opacity(0.28))

                Path { path in
                    let height = geometry.size.height
                    let x = width * fraction
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: x, y: height))
                    path.addLine(to: CGPoint(x: x, y: height - height * fraction))
                    path.closeSubpath()
                }
                .fill(tint(for: climb))

                Rectangle()
                    .fill(WatchTheme.textPrimary)
                    .frame(width: 1.5)
                    .offset(x: max(0, min(width - 1.5, width * fraction)))
            }
            .clipShape(.rect(cornerRadius: 4))
        }
        .frame(height: WatchDisplay.scaled(44, atLeast: 32))
        .animation(.easeOut(duration: 0.4), value: fraction)
    }

    // MARK: - Between climbs

    private func approaching(_ climb: ClimbSegment) -> some View {
        VStack(spacing: WatchDisplay.spacing(7)) {
            Image(systemName: "arrow.up.right")
                .font(.watch(18, weight: .bold))
                .foregroundStyle(tint(for: climb))

            Text("Next climb")
                .fieldLabelStyle()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(WatchFormat.shortDistance(distanceToNext(climb)))
                    .font(.metric(30, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Text(WatchFormat.shortDistanceUnit(distanceToNext(climb)))
                    .font(.watch(11, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            HStack(spacing: WatchDisplay.spacing(6)) {
                readout(
                    "GAIN",
                    value: WatchFormat.elevation(climb.gain),
                    unit: WatchFormat.units.elevationUnit,
                    tint: WatchTheme.highlight
                )
                readout(
                    "AVG",
                    value: WatchFormat.decimal(climb.averageGrade, places: 1),
                    unit: "%",
                    tint: tint(for: climb)
                )
                readout("CAT", value: climb.category.label, unit: "", tint: tint(for: climb))
            }
        }
        .padding(.top, WatchDisplay.spacing(4))
    }

    private var empty: some View {
        VStack(spacing: WatchDisplay.spacing(5)) {
            Image(systemName: "flag.checkered")
                .font(.title3)
                .foregroundStyle(WatchTheme.textSecondary)
            Text(climbs.isEmpty ? "No climbs on this course" : "Last climb done")
                .font(.watch(11, weight: .semibold))
                .foregroundStyle(WatchTheme.textPrimary)
                .multilineTextAlignment(.center)
            if !climbs.isEmpty {
                Text("\(climbs.count) climbed · \(WatchFormat.elevation(climbs.reduce(0) { $0 + $1.gain })) \(WatchFormat.units.elevationUnit) total")
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    private func readout(_ label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .fieldLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.metric(17, weight: .bold))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.watch(8, weight: .semibold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func distanceToNext(_ climb: ClimbSegment) -> Double {
        max(0, climb.startDistance - progress)
    }

    private func tint(for climb: ClimbSegment) -> Color {
        WatchTheme.zoneColors[max(0, min(4, climb.category.tintIndex))]
    }

    private var gradeTint: Color {
        metrics.grade > 8 ? WatchTheme.danger : (metrics.grade > 3 ? WatchTheme.accent : WatchTheme.textPrimary)
    }
}
