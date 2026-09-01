import SwiftUI

/// What the watch does by itself during a workout.
struct WatchBehaviourView: View {
    @Environment(WatchLayoutStore.self) private var layout

    var body: some View {
        @Bindable var layout = layout

        List {
            Section {
                Toggle("Auto lap", isOn: $layout.isAutoLapEnabled)
                if layout.isAutoLapEnabled {
                    Stepper(value: $layout.autoLapKilometres, in: 0.5...10, step: 0.5) {
                        HStack {
                            Text("Every")
                            Spacer()
                            Text("\(layout.autoLapKilometres, specifier: "%.1f") \(layout.unitSystem.distanceUnit)")
                                .font(.metric(15))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            } header: {
                Text("Laps")
            }

            Section {
                Toggle("Auto pause", isOn: $layout.isAutoPauseEnabled)
                Toggle("Automatic rerouting", isOn: $layout.isReroutingEnabled)
            } header: {
                Text("Automatic")
            } footer: {
                Text("Auto pause stops the clock when you stop moving. Rerouting works out a way back to the course whenever you stray off it.")
            }

            Section {
                Toggle("Haptic alerts", isOn: $layout.usesHapticAlerts)
                Toggle("Navigation alerts", isOn: $layout.usesNavigationAlerts)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Navigation alerts buzz when you go off course or reach a waypoint.")
            }

            Section {
                Toggle(isOn: $layout.confirmsWorkoutEnd) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Confirm before stopping")
                        Text(layout.confirmsWorkoutEnd
                             ? "The watch asks before ending a workout"
                             : "End saves the workout straight away")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }

                Toggle(isOn: $layout.usesWaterLock) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto water lock")
                        Text("Locks the watch screen for swims")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("Water lock disables the screen and the Digital Crown until you turn the Crown to release it. It engages only for water sports.")
            }

            Section {
                Stepper(value: $layout.maxHeartRate, in: 140...220) {
                    HStack {
                        Text("Maximum")
                        Spacer()
                        Text("\(layout.maxHeartRate) bpm")
                            .font(.metric(15))
                            .foregroundStyle(Theme.danger)
                    }
                }
            } header: {
                Text("Heart rate")
            } footer: {
                Text("Your zones are worked out from this, on both devices. Heart rate reserve also uses your resting rate, which Trekka reads from Health.")
            }

            Section {
                Picker("Pool length", selection: $layout.poolLengthMetres) {
                    Text("25 m").tag(25.0)
                    Text("33⅓ m").tag(33.33)
                    Text("50 m").tag(50.0)
                    Text("25 yd").tag(22.86)
                    Text("33⅓ yd").tag(30.48)
                }
            } header: {
                Text("Pool swimming")
            } footer: {
                Text("The watch counts lengths by knowing how long one is — there is no way to measure it from your wrist. Lengths and SWOLF depend on getting this right.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("During a workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
