import SwiftUI

/// The state of the link between the two devices, and what crosses it.
struct WatchSyncView: View {
    @Environment(WatchLayoutStore.self) private var layout

    var body: some View {
        List {
            Section {
                switch layout.delivery {
                case .sending(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sending layout…")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ProgressView(value: progress)
                            .tint(Theme.accent)
                    }
                case .delivered(let date):
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Layout on your watch")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Transferred \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.positive)
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't send", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                case .idle:
                    Label {
                        Text("Not sent since the last change")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.highlight)
                    }
                }

                Button {
                    layout.sendToWatch()
                } label: {
                    Label("Send layout to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(isConnected
                    ? "Transfers run over WatchConnectivity. The watch stores the layout itself, so your screens work with the phone left at home."
                    : "No Apple Watch running Trekka detected. Pair your watch, install the app, then send again.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Today dashboard mirrored")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your tiles, readiness, zones and history appear on the watch with the same layout.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } icon: {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(Theme.accent)
                }

                if let summary = WatchLink.shared.lastWatchEditSummary,
                   let date = WatchLink.shared.lastWatchEditAt {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(summary)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Applied here \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    } icon: {
                        Image(systemName: "arrow.down.left.arrow.up.right")
                            .foregroundStyle(Theme.highlight)
                    }
                }

                if let workout = WatchLink.shared.lastWorkout {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Workout received from watch")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(WatchSportProfile(rawValue: workout.sport)?.title ?? workout.sport) · \(Formatters.compactDuration(workout.duration)) · \(Formatters.distance(workout.distance)) km")
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    } icon: {
                        Image(systemName: "arrow.down.heart")
                            .foregroundStyle(Theme.highlight)
                    }
                }
            } header: {
                Text("Two-way sync")
            } footer: {
                Text("Edit on either device. Changes made on the watch — screens, options or dashboard tiles — come straight back to this app.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isConnected: Bool {
        WatchLink.shared.isPaired && WatchLink.shared.isWatchAppInstalled
    }
}
