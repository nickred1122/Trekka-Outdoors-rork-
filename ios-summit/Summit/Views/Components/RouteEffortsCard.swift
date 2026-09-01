import SwiftUI

/// Your own history on one route, ranked fastest first.
///
/// Only sessions that genuinely covered this ground are listed. A run that
/// merely passed through, or covered half of it, is not the same effort and is
/// left out rather than ranked against a full lap.
struct RouteEffortsCard: View {
    let route: PlannedRoute

    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health

    @State private var efforts: [RouteEffort] = []
    @State private var hasSearched = false
    @State private var isExpanded = false

    private var visible: [RouteEffort] {
        isExpanded ? efforts : Array(efforts.prefix(3))
    }

    var body: some View {
        Group {
            if !efforts.isEmpty {
                card
            } else if hasSearched {
                emptyCard
            }
        }
        .task(id: signature) { await search() }
    }

    private var signature: String {
        "\(route.id)-\(store.recentActivities.count)-\(health.healthActivities.count)"
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your times here")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(efforts.count) \(efforts.count == 1 ? "effort" : "efforts")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 8) {
                ForEach(visible) { effort in
                    row(effort)
                }
            }

            if efforts.count > 3 {
                Button {
                    withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show fewer" : "Show all \(efforts.count)")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func row(_ effort: RouteEffort) -> some View {
        HStack(spacing: 10) {
            // The rank badge, with the best one marked out.
            ZStack {
                Circle()
                    .fill(effort.isPersonalBest ? Theme.accent : Theme.surfaceRaised)
                if effort.isPersonalBest {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.surface)
                } else {
                    Text("\(effort.rank)")
                        .font(.metric(12))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(effort.activityName)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(effort.date.formatted(date: .abbreviated, time: .omitted))
                    if effort.averageHeartRate > 0 {
                        Text("·")
                        Text("\(Int(effort.averageHeartRate.rounded())) bpm")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Formatters.duration(effort.duration))
                    .font(.metric(15))
                    .foregroundStyle(effort.isPersonalBest ? Theme.accent : Theme.textPrimary)
                if effort.isPersonalBest {
                    Text("Best")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                } else {
                    Text("+\(Formatters.duration(effort.behindBest))")
                        .font(.metric(10))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }
        }
    }

    private var emptyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text("No times here yet")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Record this route and your fastest run of it will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .panel()
    }

    /// Comparing tracks is real geometry, so it runs off the main actor.
    private func search() async {
        let activities = ActivityFeed.merged(store: store, health: health)
        let target = route
        let found = await Task.detached(priority: .utility) {
            RouteEfforts.efforts(on: target, from: activities)
        }.value
        efforts = found
        hasSearched = true
    }
}
