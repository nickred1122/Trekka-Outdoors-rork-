import SwiftUI

/// Adds a new page to a sport, either a preset data screen or a special page.
struct AddWatchPageView: View {
    let sport: WatchSportProfile

    @Environment(WatchLayoutStore.self) private var layout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Data screens") {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        layout.addPage(.data(preset.fields, layout: preset.layout), to: sport)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            WatchLayoutGlyph(layout: preset.layout, tint: sport.tint, isSelected: true)
                                .frame(width: 30, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(preset.fields.isEmpty ? "Start from nothing" : preset.fields.map(\.title).joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section("Special pages") {
                ForEach(WatchPageKind.allCases.filter { $0 != .data }) { kind in
                    Button {
                        layout.addPage(.page(kind), to: sport)
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(kind.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(sport.tint)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Add Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// Starting points, each with the shape it is meant to be read in. Every one
    /// can be rearranged afterwards.
    private var presets: [(name: String, fields: [WatchMetric], layout: WatchPageLayout?)] {
        let tempo: WatchMetric = sport.usesPace ? .pace : .speed
        return [
            ("Single big number", [tempo], WatchPageLayout(rows: [1])),
            ("Classic three", [.duration, .distance, tempo], WatchPageLayout(rows: [1, 2])),
            ("Four up", [.duration, .distance, tempo, .heartRate], WatchPageLayout(rows: [2, 2])),
            ("One, pair, one", [tempo, .distance, .heartRate, .duration], WatchPageLayout(rows: [1, 2, 1])),
            ("Climbing", [.grade, .ascent, .altitude, .verticalSpeed], WatchPageLayout(rows: [1, 3])),
            ("Lap focus", [.lapTime, .lapDistance, .lapPace, .averageHeartRate], WatchPageLayout(rows: [2, 2])),
            ("Navigation", [.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint], WatchPageLayout(rows: [1, 2, 1])),
            ("Everything", [.duration, .distance, tempo, .heartRate, .ascent, .calories], WatchPageLayout(rows: [2, 2, 2])),
            ("Blank screen", [], nil),
        ]
    }
}
