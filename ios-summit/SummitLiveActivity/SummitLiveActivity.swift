import ActivityKit
import SwiftUI
import WidgetKit

/// Trekka's palette, restated here because an extension cannot see the app's
/// theme. These are the same values as `Theme.accent` and friends.
private enum GlanceTheme {
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.075)
    static let paused = Color(red: 1.0, green: 0.831, blue: 0.286)
    static let label = Color.white.opacity(0.55)
}

private extension Font {
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// The elapsed clock.
///
/// While running this is a system-ticked timer rather than a number the app
/// pushes: the lock screen updates it every second on its own, which keeps the
/// clock smooth without spending a background update — and the budget for those
/// is small enough that spending one per second would get the activity throttled
/// into uselessness within minutes.
private struct ElapsedClock: View {
    let state: TrekkaWorkoutAttributes.ContentState
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let frozen = state.pausedElapsed {
                Text(Self.formatted(frozen))
            } else {
                Text(state.startedAt, style: .timer)
            }
        }
        .font(.metric(size))
        .foregroundStyle(state.isPaused ? GlanceTheme.paused : .white)
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// One metric with its label, as it reads across the whole app.
private struct GlanceMetric: View {
    let value: String
    let unit: String
    let label: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.metric(17))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GlanceTheme.label)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(GlanceTheme.label)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Progress along the planned route, when one is being followed.
private struct RouteProgressBar: View {
    let progress: Double
    let waypoint: String?
    let distance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(GlanceTheme.accent)
                        .frame(width: max(3, proxy.size.width * min(1, max(0, progress))))
                }
            }
            .frame(height: 4)

            if let waypoint {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(GlanceTheme.accent)
                    Text(waypoint)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GlanceTheme.label)
                    if let distance {
                        Text(distance)
                            .font(.metric(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .lineLimit(1)
            }
        }
    }
}

/// The full card shown on the lock screen and in the banner.
private struct LockScreenView: View {
    let context: ActivityViewContext<TrekkaWorkoutAttributes>

    private var state: TrekkaWorkoutAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: context.attributes.activitySymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GlanceTheme.accent)
                Text(context.attributes.activityTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                if let route = context.attributes.routeName {
                    Text("· \(route)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GlanceTheme.label)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(GlanceTheme.paused, in: .capsule)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                ElapsedClock(state: state)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 0) {
                GlanceMetric(
                    value: state.distanceText,
                    unit: state.distanceUnit,
                    label: "DISTANCE"
                )
                Spacer(minLength: 6)
                GlanceMetric(
                    value: state.paceText,
                    unit: state.paceUnit,
                    label: "PACE"
                )
                Spacer(minLength: 6)
                GlanceMetric(
                    value: state.heartRateText,
                    unit: state.heartRateText == "--" ? "" : "bpm",
                    label: "HEART",
                    tint: state.heartRateText == "--" ? .white.opacity(0.5) : .white
                )
                Spacer(minLength: 6)
                GlanceMetric(
                    value: state.ascentText,
                    unit: state.ascentUnit,
                    label: "ASCENT"
                )
            }

            if let progress = state.routeProgress {
                RouteProgressBar(
                    progress: progress,
                    waypoint: state.nextWaypointName,
                    distance: state.distanceToWaypointText
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color.black.opacity(0.82))
        .activitySystemActionForegroundColor(GlanceTheme.accent)
    }
}

struct SummitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrekkaWorkoutAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlanceMetric(
                        value: context.state.distanceText,
                        unit: context.state.distanceUnit,
                        label: "DISTANCE"
                    )
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GlanceMetric(
                        value: context.state.paceText,
                        unit: context.state.paceUnit,
                        label: "PACE"
                    )
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 5) {
                        Image(systemName: context.attributes.activitySymbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(GlanceTheme.accent)
                        Text(context.attributes.activityTitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        ElapsedClock(state: context.state, size: 26)
                        Spacer(minLength: 8)
                        if context.state.heartRateText != "--" {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.271, blue: 0.227))
                                Text(context.state.heartRateText)
                                    .font(.metric(15))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    if let progress = context.state.routeProgress {
                        RouteProgressBar(
                            progress: progress,
                            waypoint: context.state.nextWaypointName,
                            distance: context.state.distanceToWaypointText
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.activitySymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(context.state.isPaused ? GlanceTheme.paused : GlanceTheme.accent)
            } compactTrailing: {
                ElapsedClock(state: context.state, size: 13)
                    // The compact slot is narrow and a running clock grows as it
                    // passes an hour; without a ceiling the digits get clipped.
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: context.attributes.activitySymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(context.state.isPaused ? GlanceTheme.paused : GlanceTheme.accent)
            }
            .keylineTint(GlanceTheme.accent)
        }
    }
}
