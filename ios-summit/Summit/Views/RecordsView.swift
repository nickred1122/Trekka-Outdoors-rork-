import SwiftUI

/// The record book: every best the athlete has actually recorded.
struct RecordsView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health

    @Binding var path: NavigationPath

    private var activities: [ActivityRecord] {
        ActivityFeed.merged(store: store, health: health)
    }

    private var records: [PersonalRecord] {
        PersonalRecords.all(from: activities)
    }

    private var splits: [PersonalRecord] { records.filter { $0.kind == .split } }
    private var efforts: [PersonalRecord] { records.filter { $0.kind == .effort } }

    /// Sessions the split scan could actually read — a track without timestamps
    /// can't prove a time, so it is excluded and the footer says as much.
    private var timedSessions: Int {
        activities.filter { activity in
            activity.track.count > 2 && activity.track.allSatisfy { $0.timestamp != nil }
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No records yet",
                        systemImage: "trophy",
                        description: Text("Record a few workouts and your bests will collect here automatically.")
                    )
                    .padding(.top, 60)
                } else {
                    if !efforts.isEmpty {
                        section(title: PersonalRecord.Kind.effort.sectionTitle, records: efforts)
                    }
                    if !splits.isEmpty {
                        section(title: PersonalRecord.Kind.split.sectionTitle, records: splits)
                    }
                    footer
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func section(title: String, records: [PersonalRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 8) {
                ForEach(records) { record in
                    row(record)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    @ViewBuilder
    private func row(_ record: PersonalRecord) -> some View {
        let content = HStack(spacing: 12) {
            TrekkaIcon(record.glyph, size: 16, tint: Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if record.isRecent {
                        Text("NEW")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Theme.canvas)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Theme.highlight, in: .capsule)
                    }
                }
                Text("\(record.activityName) · \(record.achievedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(record.value)
                    .font(.metric(18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if !record.unit.isEmpty {
                    Text(record.unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .lineLimit(1)
        }

        if let id = record.activityID, let activity = activities.first(where: { $0.id == id }) {
            Button {
                path.append(activity)
            } label: {
                content
            }
            .buttonStyle(TilePressStyle())
        } else {
            content
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("How these are measured", systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
            Text("Split records come from the fastest continuous stretch inside a recorded track, so they need a workout this app timed — \(timedSessions) of your \(activities.count) so far. Distance, climbing and week totals count every session, including ones imported from Apple Health.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
