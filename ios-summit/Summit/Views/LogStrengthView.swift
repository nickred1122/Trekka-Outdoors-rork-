import SwiftUI

/// Logging a strength session on the phone — for days the watch stays at home.
///
/// The same kilogram store as the wrist logger: weights are entered in the
/// athlete's chosen unit and converted on the way in, so sessions logged on
/// either device add together into one history.
struct LogStrengthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RouteStore.self) private var store

    @State private var startedAt: Date = .now
    @State private var sets: [StrengthSet] = []
    @State private var exercise: GymExercise?
    @State private var isPickingExercise = false

    // The next set, before it is logged.
    @State private var reps: Int = 8
    @State private var weightSteps: Int = 0

    /// One notch of the weight control: a 2.5 kg jump, or 5 lb — what the
    /// smallest pair of plates in any gym adds. Same convention as the wrist.
    private var stepSize: Double { Formatters.massSystem == .metric ? 2.5 : 5 }
    private var displayWeight: Double { Double(weightSteps) * stepSize }
    private var weightKilograms: Double {
        Formatters.massSystem == .metric ? displayWeight : displayWeight * 0.453_592_37
    }
    private var unitLabel: String { Formatters.massUnit }
    private var maxWeightSteps: Int { Formatters.massSystem == .metric ? 120 : 132 }

    private var totalVolume: Double { sets.reduce(0) { $0 + $1.volume } }
    private var canSave: Bool { !sets.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    exerciseCard
                    entryCard

                    if !sets.isEmpty {
                        setsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Log strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(.subheadline, weight: .bold))
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerSheet { selected in
                    exercise = selected
                    prefill(for: selected)
                }
            }
            .sensoryFeedback(.success, trigger: sets.count)
        }
    }

    // MARK: - Cards

    private var exerciseCard: some View {
        Button {
            isPickingExercise = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? "Choose exercise")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(exercise == nil ? "Tap to pick a movement" : groupTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .panel(radius: 14)
    }

    private var groupTitle: String {
        guard let exercise else { return "" }
        let count = sets.filter { $0.exercise == exercise.name }.count
        let done = count == 0 ? "First set" : "\(count) set\(count == 1 ? "" : "s") done"
        return "\(exercise.group.title) · \(done)"
    }

    /// Reps and weight for the next set, then the button that logs it.
    private var entryCard: some View {
        VStack(spacing: 0) {
            stepperRow(
                symbol: "number",
                title: "Reps",
                value: "\(reps)",
                onIncrement: { reps = min(50, reps + 1) },
                onDecrement: { reps = max(1, reps - 1) }
            )

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.leading, 54)

            stepperRow(
                symbol: "scalemass",
                title: "Weight",
                value: weightSteps == 0 ? "Bodyweight" : "\(Formatters.integer(displayWeight)) \(unitLabel)",
                onIncrement: { weightSteps = min(maxWeightSteps, weightSteps + 1) },
                onDecrement: { weightSteps = max(0, weightSteps - 1) }
            )

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.leading, 54)

            Button {
                addSet()
            } label: {
                Text("Add set")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(exercise == nil ? Theme.textPrimary.opacity(0.35) : Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(exercise == nil ? Theme.surfaceRaised : Theme.accent, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(exercise == nil)
            .padding(12)
        }
        .panel(radius: 14)
    }

    private func stepperRow(
        symbol: String,
        title: String,
        value: String,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            Stepper("", onIncrement: onIncrement, onDecrement: onDecrement)
                .labelsHidden()
        }
        .padding(12)
    }

    /// Everything logged so far, newest last, so the shape of the session reads
    /// top to bottom like a training diary.
    private var setsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This session")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Formatters.integer(totalVolume)) \(unitLabel) moved")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 7) {
                ForEach(sets) { set in
                    HStack(spacing: 10) {
                        Text(set.exercise)
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(setLabel(set))
                            .font(.metric(14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary.opacity(0.75))

                        Button {
                            removeSet(set)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.danger.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove set")
                    }
                }
            }
        }
        .padding(16)
        .panel(radius: 14)
    }

    private func setLabel(_ set: StrengthSet) -> String {
        guard !set.isBodyweight else { return "\(set.reps) × BW" }
        return "\(set.reps) × \(Formatters.integer(Formatters.mass(fromKilograms: set.weightKilograms))) \(unitLabel)"
    }

    // MARK: - Actions

    private func addSet() {
        guard let exercise else { return }
        sets.append(StrengthSet(
            exercise: exercise.name,
            reps: reps,
            weightKilograms: weightKilograms
        ))
    }

    private func removeSet(_ set: StrengthSet) {
        sets.removeAll { $0.id == set.id }
    }

    /// Opens the next set where the last one left off, per movement — the same
    /// courtesy the wrist logger extends.
    private func prefill(for exercise: GymExercise) {
        if let last = sets.last(where: { $0.exercise == exercise.name }) {
            reps = max(1, min(50, last.reps))
            let shown = Formatters.mass(fromKilograms: last.weightKilograms)
            weightSteps = max(0, min(maxWeightSteps, Int((shown / stepSize).rounded())))
        } else if exercise.isBodyweightByDefault {
            reps = 10
            weightSteps = 0
        } else {
            reps = 8
            weightSteps = 0
        }
    }

    private func save() {
        let record = ActivityRecord(
            name: "Strength · \(startedAt.formatted(date: .abbreviated, time: .omitted))",
            activity: .strength,
            startDate: startedAt,
            duration: max(60, Date.now.timeIntervalSince(startedAt)),
            distance: 0,
            elevationGain: 0,
            averageHeartRate: 0,
            calories: 0,
            trainingEffect: 0,
            strengthSets: sets
        )
        store.add(record)
        dismiss()
    }
}

/// Picking a movement, grouped by body part — the phone's comfortable version
/// of the wrist picker, reading the same library.
private struct ExercisePickerSheet: View {
    let onSelect: (GymExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [(group: GymMuscleGroup, exercises: [GymExercise])] {
        let filtered = query.isEmpty
            ? GymExerciseLibrary.all
            : GymExerciseLibrary.all.filter { $0.name.localizedStandardContains(query) }
        return GymMuscleGroup.allCases.compactMap { group in
            let inGroup = filtered.filter { $0.group == group }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches, id: \.group) { entry in
                    Section(entry.group.title) {
                        ForEach(entry.exercises) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                Label(exercise.name, systemImage: exercise.isBodyweightByDefault ? "figure.strengthtraining.functional" : "dumbbell.fill")
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}
