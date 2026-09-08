import SwiftUI

/// Power saver, set up on the phone and applied on the wrist.
struct WatchPowerView: View {
    @Environment(WatchLayoutStore.self) private var layout

    var body: some View {
        @Bindable var layout = layout

        List {
            Section {
                Toggle(isOn: $layout.isPowerSaverEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Power saver")
                        Text("Start every watch workout in low power")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }

                Stepper(value: $layout.powerSaverThreshold, in: 0...50, step: 5) {
                    HStack {
                        Text("Switch on at")
                        Spacer()
                        Text(layout.powerSaverThreshold == 0 ? "Off" : "\(layout.powerSaverThreshold)%")
                            .font(.metric(15))
                            .foregroundStyle(layout.powerSaverThreshold == 0 ? Theme.textPrimary.opacity(0.5) : Theme.positive)
                    }
                }
            } header: {
                Text("Power saver")
            } footer: {
                // This used to say heart rate was the only thing traded away,
                // which the list two sections below plainly contradicts — GPS is
                // eased off, the map steps aside and haptics go quiet as well.
                // A footer that argues with the screen it sits on teaches the
                // athlete to trust neither.
                Text("Time, distance, elevation and laps are recorded exactly the same in either mode. What you trade is listed below.")
            }

            Section {
                Toggle("Always-on metrics", isOn: $layout.keepsScreenOn)
            } footer: {
                Text("Keeps your numbers readable with your wrist down. Switching this off is the single biggest saving after power saver itself.")
            }

            Section {
                ForEach(PowerSaverPlan.changes) { change in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.title)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(change.detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    } icon: {
                        Image(systemName: change.symbol)
                            .foregroundStyle(Theme.positive)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("What power saver changes")
            }

            Section {
                ForEach(PowerSaverPlan.unchanged, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            } header: {
                Text("Still recorded")
            } footer: {
                // Says where this setting's reach ends, in the same words the
                // watch uses, so a flat battery is never blamed on a switch that
                // could never have helped.
                Text("This turns down Trekka's own sensors. watchOS Low Power Mode is a separate switch in the Settings app on your watch.")
            }

            Section {
                // No hours are quoted here on purpose. Only the watch can watch
                // its own battery, and that measurement never reaches this phone
                // — so anything printed here would be a constant pretending to
                // be a forecast, and wrong by hours on a cold day.
                Label(
                    "Your watch measures its own battery drain during workouts and shows the hours it has left under Power on the wrist.",
                    systemImage: "battery.100percent.bolt"
                )
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Battery")
        .navigationBarTitleDisplayMode(.inline)
    }
}
