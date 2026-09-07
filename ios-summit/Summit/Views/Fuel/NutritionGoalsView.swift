import SwiftUI

/// Setting the daily targets the diary is read against.
///
/// The energy figure is chosen rather than calculated: the app knows nothing
/// about someone's build, job or week, and a confident guess dressed up as a
/// recommendation would be worse than asking. What it does know is what they
/// burned today, which is offered as an option rather than assumed.
struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NutritionStore.self) private var nutrition
    @Environment(HealthService.self) private var health

    @State private var goals: NutritionGoals = .default
    @State private var hasPrepared = false

    /// Energy moves in 50 kcal steps — finer than that is false precision for a
    /// daily target.
    private static let energyStep: Double = 50
    private static let energyRange: ClosedRange<Double> = 1_200...5_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    energyCard
                    trainingCard
                    splitCard
                    macrosCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Daily targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        nutrition.setGoals(goals)
                        dismiss()
                    }
                    .font(.system(.subheadline, weight: .bold))
                }
            }
            .onAppear {
                guard !hasPrepared else { return }
                hasPrepared = true
                goals = nutrition.goals
            }
        }
    }

    // MARK: - Cards

    private var energyCard: some View {
        VStack(spacing: 12) {
            Text("Daily energy")
                .font(.system(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                stepButton("minus", enabled: goals.energyKilocalories > Self.energyRange.lowerBound) {
                    adjustEnergy(-Self.energyStep)
                }

                VStack(spacing: 0) {
                    Text("\(Int(goals.energyKilocalories.rounded()))")
                        .font(.metric(34))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.system(.caption2, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                stepButton("plus", enabled: goals.energyKilocalories < Self.energyRange.upperBound) {
                    adjustEnergy(Self.energyStep)
                }
            }
        }
        .padding(16)
        .panel()
        .animation(.snappy(duration: 0.25), value: goals.energyKilocalories)
    }

    private var trainingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $goals.addsActiveEnergy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add training on top")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Raise the target by the energy you actually burn each day.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Theme.accent)

            if goals.addsActiveEnergy {
                let burned = health.snapshot.activeCalories
                Text(
                    burned > 0
                        ? "You've burned \(Int(burned.rounded())) kcal today, so today's target is \(Int(goals.energyTarget(activeEnergy: burned).rounded())) kcal."
                        : "No active energy recorded yet today, so the target is \(Int(goals.energyKilocalories.rounded())) kcal until you move."
                )
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
        }
        .padding(16)
        .panel()
    }

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macro split")
                .font(.system(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MacroSplit.allCases) { split in
                        splitChip(split)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text(goals.split.detail)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .padding(16)
        .panel()
    }

    private func splitChip(_ split: MacroSplit) -> some View {
        let isActive = goals.split == split
        // Custom is a state you land in by moving a slider, not one you pick.
        return Button {
            withAnimation(.snappy(duration: 0.25)) { goals.apply(split) }
        } label: {
            Text(split.title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(isActive ? Theme.canvas : Theme.textPrimary.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? Theme.accent : Theme.textPrimary.opacity(0.07), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(split == .custom)
        .opacity(split == .custom && !isActive ? 0.35 : 1)
    }

    /// Each macro as a share of the day, with the grams that implies. Moving one
    /// adjusts the other two, so the three always describe a whole day.
    private var macrosCard: some View {
        VStack(spacing: 16) {
            macroSlider(
                .protein,
                percent: goals.proteinPercent,
                grams: goals.proteinTarget(activeEnergy: 0)
            ) { goals.setProteinPercent($0) }

            macroSlider(
                .carbohydrate,
                percent: goals.carbohydratePercent,
                grams: goals.carbohydrateTarget(activeEnergy: 0)
            ) { goals.setCarbohydratePercent($0) }

            macroSlider(
                .fat,
                percent: goals.fatPercent,
                grams: goals.fatTarget(activeEnergy: 0)
            ) { goals.setFatPercent($0) }
        }
        .padding(16)
        .panel()
    }

    private func macroSlider(
        _ macro: Macro,
        percent: Double,
        grams: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(macro.color)
                    .frame(width: 8, height: 8)

                Text(macro.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                Text("\(Int(grams.rounded())) g")
                    .font(.metric(14))
                    .foregroundStyle(Theme.textPrimary)

                Text("· \(Int(percent.rounded()))%")
                    .font(.system(.caption, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Slider(
                value: Binding(
                    get: { percent },
                    set: { onChange($0) }
                ),
                in: 5...70,
                step: 1
            )
            .tint(macro.color)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func adjustEnergy(_ delta: Double) {
        let value = goals.energyKilocalories + delta
        goals.energyKilocalories = min(max(value, Self.energyRange.lowerBound), Self.energyRange.upperBound)
    }
}
