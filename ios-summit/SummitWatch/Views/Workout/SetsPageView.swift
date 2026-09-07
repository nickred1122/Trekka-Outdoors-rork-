import SwiftUI

/// The gym session so far, and the way into logging the next set.
///
/// Kept separate from the logger itself: this is a page in the workout carousel
/// and so cannot own the Digital Crown, while the logger needs it for the dials.
struct SetsPageView: View {
    let sport: WatchSport
    let session: StrengthSession
    let currentExercise: GymExercise?
    let onLog: () -> Void

    @Environment(WatchScreenSettings.self) private var settings

    private var units: UnitSystem { settings.unitSystem }

    var body: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(6)) {
                logButton

                if session.isEmpty {
                    emptyState
                } else {
                    totals
                    exerciseList
                }
            }
            .padding(.bottom, WatchDisplay.spacing(8))
        }
    }

    private var logButton: some View {
        Button(action: onLog) {
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .font(.watch(12, weight: .bold))
                Text(currentExercise?.name ?? "Log a set")
                    .font(.watch(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(WatchTheme.canvas)
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchDisplay.spacing(9))
            .background(sport.tint, in: .rect(cornerRadius: WatchTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 3) {
            Text("No sets yet")
                .font(.watch(11, weight: .semibold))
                .foregroundStyle(WatchTheme.textPrimary)
            Text("Pick a movement and dial in reps and weight with the Crown.")
                .font(.watch(9))
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WatchDisplay.spacing(10))
        .padding(.horizontal, WatchDisplay.spacing(6))
        .watchPanel()
    }

    private var totals: some View {
        HStack(spacing: WatchDisplay.spacing(5)) {
            total("Sets", "\(session.sets.count)")
            total("Reps", "\(session.totalReps)")
            total("Volume", volumeText)
        }
    }

    /// Total load shifted. Shown in thousands past 10,000 so it still fits.
    private var volumeText: String {
        let shown = units.mass(fromKilograms: session.totalVolume)
        guard shown >= 10_000 else { return WatchFormat.integer(shown) }
        return String(format: "%.1fk", shown / 1000)
    }

    private func total(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.metric(16, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .fieldLabelStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WatchDisplay.spacing(6))
        .watchPanel()
    }

    private var exerciseList: some View {
        VStack(spacing: WatchDisplay.spacing(4)) {
            ForEach(session.byExercise, id: \.exercise) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.exercise)
                        .font(.watch(11, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(summary(of: entry.sets))
                        .font(.metric(10, weight: .semibold))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WatchDisplay.spacing(7))
                .padding(.vertical, WatchDisplay.spacing(6))
                .watchPanel()
            }
        }
    }

    private func summary(of sets: [StrengthSet]) -> String {
        sets.map { set in
            guard !set.isBodyweight else { return "\(set.reps)" }
            return "\(set.reps)×\(WatchFormat.integer(units.mass(fromKilograms: set.weightKilograms)))"
        }
        .joined(separator: "  ")
    }
}
