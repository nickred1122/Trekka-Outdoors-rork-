import SwiftUI

/// Training history synced from the phone, plus anything recorded on the wrist.
struct ActivitiesWatchView: View {
    @Environment(WatchDashboardStore.self) private var dashboard

    @State private var filter: HistoryFilter = .all

    private enum HistoryFilter: String, CaseIterable, Identifiable {
        case all, run, ride, hike

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .run: "Run"
            case .ride: "Ride"
            case .hike: "Hike"
            }
        }

        var kind: WatchActivityKind? {
            switch self {
            case .all: nil
            case .run: .run
            case .ride: .ride
            case .hike: .hike
            }
        }
    }

    private var activities: [ActivityTransfer] {
        let all = dashboard.activities.sorted { $0.startDate > $1.startDate }
        guard let kind = filter.kind else { return all }
        return all.filter { $0.activity == kind.rawValue }
    }

    private var weekTotals: (distance: Double, duration: TimeInterval, ascent: Double) {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recent = dashboard.activities.filter { $0.startDate >= cutoff }
        return (
            recent.reduce(0) { $0 + $1.distance },
            recent.reduce(0) { $0 + $1.duration },
            recent.reduce(0) { $0 + $1.elevationGain }
        )
    }

    var body: some View {
        List {
            if !dashboard.activities.isEmpty {
                Section {
                    VStack(spacing: 5) {
                        WatchStatRow(title: "Distance", value: "\(WatchFormat.distance(weekTotals.distance)) \(WatchFormat.units.distanceUnit)")
                        WatchStatRow(title: "Time", value: WatchFormat.compactDuration(weekTotals.duration))
                        WatchStatRow(
                            title: "Ascent",
                            value: "\(WatchFormat.elevation(weekTotals.ascent)) \(WatchFormat.units.elevationUnit)",
                            tint: WatchTheme.highlight
                        )
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Last 7 days")
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(.system(size: 12))
                }
            }

            Section {
                if activities.isEmpty {
                    Text(dashboard.hasData
                         ? "No workouts match this filter."
                         : "Your history appears here once Trekka on iPhone syncs.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.textSecondary)
                } else {
                    ForEach(activities) { activity in
                        NavigationLink(value: TodayWatchRoute.activity(activity.id)) {
                            WatchActivityRow(activity: activity)
                        }
                    }
                }
            }
        }
        .navigationTitle("Activities")
    }
}

/// A single workout in full: track, headline stats and time in zones.
struct ActivityDetailWatchView: View {
    let activity: ActivityTransfer

    private var kind: WatchActivityKind {
        WatchActivityKind(rawValue: activity.activity) ?? .hike
    }

    private var zoneTotal: Double {
        activity.zoneMinutes.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if activity.track.count > 1 {
                    RouteGlyph(points: activity.routePoints, tint: kind.tint)
                        .frame(height: 62)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .watchPanel()
                }

                HStack(spacing: 5) {
                    Capsule()
                        .fill(kind.tint)
                        .frame(width: 3, height: 12)
                    Text(activity.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.textSecondary)
                }

                VStack(spacing: 5) {
                    WatchStatRow(title: "Distance", value: "\(WatchFormat.distance(activity.distance)) \(WatchFormat.units.distanceUnit)")
                    WatchStatRow(title: "Time", value: WatchFormat.duration(activity.duration))
                    WatchStatRow(
                        title: "Ascent",
                        value: "\(WatchFormat.elevation(activity.elevationGain)) \(WatchFormat.units.elevationUnit)",
                        tint: WatchTheme.highlight
                    )
                    WatchStatRow(title: "Avg pace", value: WatchFormat.pace(activity.averagePace))
                    WatchStatRow(
                        title: "Avg HR",
                        value: "\(WatchFormat.integer(activity.averageHeartRate)) bpm",
                        tint: WatchTheme.danger
                    )
                    WatchStatRow(title: "Calories", value: "\(WatchFormat.integer(activity.calories)) kcal")
                    if activity.trainingEffect > 0 {
                        WatchStatRow(
                            title: "Effect",
                            value: WatchFormat.decimal(activity.trainingEffect, places: 1),
                            tint: WatchTheme.accent
                        )
                    }
                }
                .padding(9)
                .watchPanel()

                if zoneTotal > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Time in zones")
                            .fieldLabelStyle()
                        ForEach(Array(activity.zoneMinutes.enumerated()), id: \.offset) { index, minutes in
                            ZoneRow(
                                zone: index + 1,
                                seconds: minutes * 60,
                                fraction: minutes / (activity.zoneMinutes.max() ?? 1),
                                isCurrent: false
                            )
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity)
                    .watchPanel()
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(activity.name)
    }
}
