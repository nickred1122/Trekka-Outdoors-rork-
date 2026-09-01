import SwiftUI

/// Destinations reachable from the activity history.
nonisolated enum ActivitiesDestination: Hashable, Sendable {
    case records
}

struct ActivitiesView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health

    @Binding var path: NavigationPath

    @State private var filter: RouteActivityType?

    private var activities: [ActivityRecord] {
        let sorted = ActivityFeed.merged(store: store, health: health)
        guard let filter else { return sorted }
        return sorted.filter { $0.activity == filter }
    }

    private var weekTotals: (distance: Double, duration: TimeInterval, gain: Double) {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recent = activities.filter { $0.startDate >= cutoff }
        return (
            recent.reduce(0) { $0 + $1.distance },
            recent.reduce(0) { $0 + $1.duration },
            recent.reduce(0) { $0 + $1.elevationGain }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatStrip(items: [
                    StatItem(symbol: "arrow.left.and.right", label: "7-day dist.", value: Formatters.distance(weekTotals.distance), unit: Formatters.units.distanceUnit),
                    StatItem(symbol: "clock", label: "Moving", value: Formatters.compactDuration(weekTotals.duration), unit: ""),
                    StatItem(symbol: "arrow.up.forward", label: "Climbed", value: Formatters.elevation(weekTotals.gain), unit: Formatters.units.elevationUnit),
                ])

                recordsLink

                filterChips

                if activities.isEmpty {
                    ContentUnavailableView(
                        "No activities yet",
                        systemImage: "figure.run",
                        description: Text("Start a workout from Today, or connect Apple Health to bring in past sessions.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(activities) { activity in
                        Button {
                            path.append(activity)
                        } label: {
                            ActivityRow(activity: activity)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(activityID: activity.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
    }

    /// A standing count of bests, so the record book is never buried.
    private var recordsLink: some View {
        let count = PersonalRecords.all(from: activities).count
        return NavigationLink(value: ActivitiesDestination.records) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.highlight)
                    .frame(width: 34, height: 34)
                    .background(Theme.highlight.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Records")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(count == 0
                         ? "Your bests appear here as you record"
                         : "\(count) personal best\(count == 1 ? "" : "s") from your own history")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(12)
            .panel(radius: 14)
        }
        .buttonStyle(TilePressStyle())
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "All", isActive: filter == nil) { filter = nil }
                ForEach(RouteActivityType.allCases, id: \.self) { type in
                    chip(title: type.rawValue, isActive: filter == type) {
                        filter = filter == type ? nil : type
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func chip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isActive ? Theme.accent.opacity(0.16) : Theme.surface, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(isActive ? Theme.accent : Theme.border, lineWidth: 1)
                }
                .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

struct ActivityRow: View {
    let activity: ActivityRecord

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(activity.activity.rawValue) · \(activity.startDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
                if !activity.track.isEmpty {
                    RouteThumbnail(points: activity.track, showsContours: false)
                        .frame(width: 54, height: 40)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }

            HStack(spacing: 0) {
                metric(value: Formatters.distance(activity.distance), unit: Formatters.units.distanceUnit, label: "Distance")
                metric(value: Formatters.duration(activity.duration), unit: "", label: "Time")
                metric(value: Formatters.pace(activity.averagePace), unit: Formatters.units.paceUnit, label: "Pace")
                metric(value: Formatters.elevation(activity.elevationGain), unit: Formatters.units.elevationUnit, label: "Climb")
            }
        }
        .padding(12)
        .panel(radius: 14)
    }

    private func metric(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.metric(16))
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
