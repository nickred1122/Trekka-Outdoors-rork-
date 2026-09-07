import SwiftUI
import WatchKit

/// Logging sets and reps on the wrist, between sets.
///
/// Deliberately a full-screen layer rather than a page in the workout carousel.
/// That carousel is a vertical `TabView`, and a vertical page TabView owns the
/// Digital Crown for its own scrolling — it keeps owning it even when hidden.
/// A Crown dial inside it would be fighting the pager for every turn, which is
/// the same fault that made map zoom look dead. Out here the Crown is ours.
struct SetLoggerView: View {
    let sport: WatchSport
    let onDismiss: () -> Void

    @Environment(WorkoutEngine.self) private var engine
    @Environment(WatchScreenSettings.self) private var settings

    /// Which dial the Crown is currently driving.
    private enum Dial { case reps, weight }

    @State private var dial: Dial = .reps
    @State private var reps: Int = 8
    /// Load counted in plate-sized steps rather than raw kilograms, so the Crown
    /// lands on weights that exist rather than on 61.3 kg.
    @State private var weightSteps: Int = 0
    @State private var crown: Double = 8
    @State private var isPickingExercise = false

    private var units: UnitSystem { settings.unitSystem }

    /// One notch of the dial: a 2.5 kg jump, or 5 lb, which is what the smallest
    /// pair of plates in any gym actually adds.
    private var stepSize: Double { units == .metric ? 2.5 : 5 }

    private var displayWeight: Double { Double(weightSteps) * stepSize }

    private var weightKilograms: Double {
        units == .metric ? displayWeight : displayWeight * 0.453_592_37
    }

    private var maxSteps: Int { units == .metric ? 120 : 132 }

    var body: some View {
        ZStack {
            WatchTheme.canvas.ignoresSafeArea()

            if isPickingExercise || engine.currentExercise == nil {
                ExercisePickerView { exercise in
                    engine.selectExercise(exercise)
                    prefill(for: exercise)
                    isPickingExercise = false
                }
            } else {
                logger
            }
        }
        .onAppear {
            if let exercise = engine.currentExercise {
                prefill(for: exercise)
            }
        }
    }

    // MARK: - Logging

    private var logger: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(7)) {
                exerciseHeader
                restRow
                dials
                logButton
                sessionSets
                footer
            }
            .padding(.horizontal, WatchDisplay.spacing(6))
            .padding(.bottom, WatchDisplay.spacing(10))
        }
        // The Crown belongs to whichever dial is selected. Bounds move with the
        // selection so a turn never runs into a dead stop belonging to the other
        // dial, which would mean winding all the way back to reach a real value.
        .focusable(true)
        .digitalCrownRotation(
            $crown,
            from: dial == .reps ? 1 : 0,
            through: dial == .reps ? 50 : Double(maxSteps),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, value in
            let rounded = Int(value.rounded())
            switch dial {
            case .reps: reps = max(1, min(50, rounded))
            case .weight: weightSteps = max(0, min(maxSteps, rounded))
            }
        }
    }

    private var exerciseHeader: some View {
        Button {
            isPickingExercise = true
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.currentExercise?.name ?? "Pick an exercise")
                        .font(.watch(13, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.75)
                    Text(setCountLabel)
                        .font(.watch(9, weight: .semibold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.watch(9, weight: .bold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .padding(.horizontal, WatchDisplay.spacing(8))
            .padding(.vertical, WatchDisplay.spacing(6))
            .frame(maxWidth: .infinity)
            .watchPanel()
        }
        .buttonStyle(.plain)
        .padding(.top, WatchDisplay.spacing(3))
    }

    private var setCountLabel: String {
        guard let name = engine.currentExercise?.name else { return "Tap to choose" }
        let count = engine.strength.sets(for: name).count
        guard count > 0 else { return "First set" }
        return count == 1 ? "1 set done" : "\(count) sets done"
    }

    /// Time since the last set. Only shown once there is something to rest from.
    @ViewBuilder
    private var restRow: some View {
        if engine.restStartedAt != nil {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.watch(10, weight: .bold))
                Text(WatchFormat.duration(engine.restElapsed))
                    .font(.metric(15, weight: .bold))
                Text("rest")
                    .font(.watch(9, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .foregroundStyle(WatchTheme.highlight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchDisplay.spacing(4))
            .watchPanel(fill: WatchTheme.surface.opacity(0.6))
        }
    }

    private var dials: some View {
        HStack(spacing: WatchDisplay.spacing(5)) {
            dialTile(
                title: "Reps",
                value: "\(reps)",
                unit: nil,
                isActive: dial == .reps
            ) {
                select(.reps)
            }

            dialTile(
                title: "Weight",
                value: weightSteps == 0 ? "BW" : WatchFormat.integer(displayWeight),
                unit: weightSteps == 0 ? nil : units.massUnit,
                isActive: dial == .weight
            ) {
                select(.weight)
            }
        }
    }

    private func dialTile(
        title: String,
        value: String,
        unit: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .fieldLabelStyle(isActive ? sport.tint : WatchTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.metric(WatchDisplay.isCompact ? 24 : 28, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .font(.watch(9, weight: .semibold))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchDisplay.spacing(7))
            .watchPanel(fill: isActive ? WatchTheme.surfaceRaised : WatchTheme.surface)
            .overlay {
                // The active dial is outlined, because on a small screen a fill
                // change alone is easy to miss with a sleeve half over the watch.
                RoundedRectangle(cornerRadius: WatchTheme.cardRadius)
                    .strokeBorder(isActive ? sport.tint : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isActive)
    }

    private func select(_ next: Dial) {
        guard dial != next else { return }
        dial = next
        // Hand the Crown the value it is now driving, or the next turn would
        // snap the dial to wherever the other one happened to be sitting.
        crown = next == .reps ? Double(reps) : Double(weightSteps)
        WKInterfaceDevice.current().play(.click)
    }

    private var logButton: some View {
        Button {
            engine.logSet(reps: reps, weightKilograms: weightKilograms)
        } label: {
            Text("Log set")
                .font(.watch(13, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WatchDisplay.spacing(8))
                .background(sport.tint, in: .rect(cornerRadius: WatchTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    /// What has already been logged for this movement, newest last, so the
    /// athlete can see the shape of the session without leaving the dial.
    @ViewBuilder
    private var sessionSets: some View {
        let done = engine.currentExercise.map { engine.strength.sets(for: $0.name) } ?? []
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: WatchDisplay.spacing(3)) {
                Text("This session")
                    .fieldLabelStyle()
                ForEach(Array(done.enumerated()), id: \.element.id) { index, set in
                    HStack(spacing: 5) {
                        Text("\(index + 1)")
                            .font(.metric(10, weight: .bold))
                            .foregroundStyle(WatchTheme.canvas)
                            .frame(width: 15, height: 15)
                            .background(sport.tint.opacity(0.85), in: .circle)
                        Text(description(of: set))
                            .font(.metric(12, weight: .semibold))
                            .foregroundStyle(WatchTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WatchDisplay.spacing(7))
            .padding(.vertical, WatchDisplay.spacing(6))
            .watchPanel()
        }
    }

    private func description(of set: StrengthSet) -> String {
        guard !set.isBodyweight else { return "\(set.reps) × bodyweight" }
        let shown = units.mass(fromKilograms: set.weightKilograms)
        return "\(set.reps) × \(WatchFormat.integer(shown)) \(units.massUnit)"
    }

    private var footer: some View {
        HStack(spacing: WatchDisplay.spacing(5)) {
            Button {
                engine.removeLastSet()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.watch(10, weight: .bold))
                    .foregroundStyle(engine.strength.isEmpty ? WatchTheme.textSecondary : WatchTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchDisplay.spacing(6))
                    .watchPanel()
            }
            .buttonStyle(.plain)
            .disabled(engine.strength.isEmpty)

            Button(action: onDismiss) {
                Label("Done", systemImage: "chevron.right")
                    .font(.watch(10, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchDisplay.spacing(6))
                    .watchPanel()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Defaults

    /// Opens the dials on the last set of this movement, so a working weight is
    /// dialled in once rather than at the top of every set.
    private func prefill(for exercise: GymExercise) {
        if let last = engine.strength.lastSet(for: exercise.name) {
            reps = max(1, min(50, last.reps))
            let shown = units.mass(fromKilograms: last.weightKilograms)
            weightSteps = max(0, min(maxSteps, Int((shown / stepSize).rounded())))
        } else if exercise.isBodyweightByDefault {
            reps = 10
            weightSteps = 0
        } else {
            reps = 8
            // No invented starting weight for a movement never logged — the
            // athlete dials their own rather than being handed a stranger's.
            weightSteps = 0
        }
        crown = dial == .reps ? Double(reps) : Double(weightSteps)
    }
}

/// Choosing what to lift, grouped by body part.
struct ExercisePickerView: View {
    let onSelect: (GymExercise) -> Void

    @State private var group: GymMuscleGroup?

    var body: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(4)) {
                if let group {
                    header(group.title) { self.group = nil }
                    ForEach(GymExerciseLibrary.exercises(in: group)) { exercise in
                        row(exercise.name) { onSelect(exercise) }
                    }
                } else {
                    header("Exercise", back: nil)
                    ForEach(GymMuscleGroup.allCases) { candidate in
                        row(candidate.title, symbol: candidate.symbol) {
                            group = candidate
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                }
            }
            .padding(.horizontal, WatchDisplay.spacing(6))
            .padding(.bottom, WatchDisplay.spacing(10))
        }
    }

    @ViewBuilder
    private func header(_ title: String, back: (() -> Void)? = nil) -> some View {
        HStack(spacing: 5) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.watch(11, weight: .bold))
                        .foregroundStyle(WatchTheme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(title)
                .font(.watch(13, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, WatchDisplay.spacing(3))
        .padding(.bottom, WatchDisplay.spacing(2))
    }

    private func row(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.watch(11, weight: .semibold))
                        .foregroundStyle(WatchTheme.accent)
                        .frame(width: 16)
                }
                Text(title)
                    .font(.watch(12, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WatchDisplay.spacing(8))
            .padding(.vertical, WatchDisplay.spacing(7))
            .frame(maxWidth: .infinity)
            .watchPanel()
        }
        .buttonStyle(.plain)
    }
}
