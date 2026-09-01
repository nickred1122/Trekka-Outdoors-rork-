import SwiftUI
import WatchKit

/// Power saver: what it does, what it costs, and when it turns itself on.
struct PowerSaverWatchView: View {
    @Environment(WatchScreenSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine

    private var batteryFraction: Double {
        let level = WKInterfaceDevice.current().batteryLevel
        return level >= 0 ? Double(level) : 1
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.isPowerSaverEnabled },
                    set: { engine.applyPowerSaverPreference($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Power saver")
                            .font(.watch(12, weight: .semibold))
                        Text(engine.powerSaverStatusText)
                            .font(.watch(9))
                            .foregroundStyle(
                                settings.isPowerSaverEnabled ? WatchTheme.positive : WatchTheme.textSecondary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(WatchTheme.positive)

                estimateStrip
            }

            Section("Turn on automatically") {
                Stepper(
                    value: Binding(
                        get: { settings.powerSaverThreshold },
                        set: { settings.powerSaverThreshold = $0 }
                    ),
                    in: 0...50,
                    step: 5
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(settings.powerSaverThreshold == 0 ? "Off" : "At \(settings.powerSaverThreshold)% battery")
                            .font(.watch(12, weight: .semibold))
                        Text(settings.powerSaverThreshold == 0
                             ? "Never switches on by itself"
                             : "Mid-workout, without asking")
                            .font(.watch(9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
            }

            Section {
                ForEach(PowerSaverPlan.changes) { change in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: change.symbol)
                            .font(.watch(11, weight: .semibold))
                            .foregroundStyle(WatchTheme.positive)
                            .frame(width: WatchDisplay.scaled(16, atLeast: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(change.title)
                                .font(.watch(11, weight: .semibold))
                                .foregroundStyle(WatchTheme.textPrimary)
                            Text(change.detail)
                                .font(.watch(9))
                                .foregroundStyle(WatchTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            } header: {
                Text("What changes")
            } footer: {
                // Say plainly where this setting's reach ends, so a flat battery
                // is never blamed on a switch that could never have helped.
                Text("This turns down Trekka's own sensors. watchOS Low Power Mode is a separate switch in the Settings app.")
                    .font(.watch(9))
            }

            Section("Still recorded") {
                ForEach(PowerSaverPlan.unchanged, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.watch(10))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }

            Section("Water") {
                Toggle(isOn: Binding(
                    get: { settings.usesWaterLock },
                    set: { settings.usesWaterLock = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto water lock")
                            .font(.watch(12, weight: .semibold))
                        Text("Locks the screen for swims. Turn the crown to clear it.")
                            .font(.watch(9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)
            }
        }
        .navigationTitle("Power")
    }

    /// What this watch has actually been measured doing, in each mode.
    ///
    /// Both cells read `--` until the battery has been observed falling for long
    /// enough in that mode. An honest blank beats a confident guess on the day
    /// somebody plans a route around it.
    private var estimateStrip: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                estimateCell(
                    title: "Normal",
                    value: engine.batteryNormalLabel,
                    tint: WatchTheme.textPrimary
                )
                estimateCell(
                    title: "Saver",
                    value: engine.batterySaverLabel,
                    tint: WatchTheme.positive
                )
            }

            Text(engine.batteryMeasurementText)
                .font(.watch(8))
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func estimateCell(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(title.uppercased())
                .font(.watch(8, weight: .bold))
                .foregroundStyle(WatchTheme.textSecondary)
            Text(value)
                .font(.metric(15, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 9))
    }
}
