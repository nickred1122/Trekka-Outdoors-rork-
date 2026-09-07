import SwiftUI

/// Choosing how much of a food was actually eaten, then logging it.
struct FoodPortionView: View {
    let food: FoodItem
    let meal: Meal
    let date: Date
    /// Closes the whole add flow, not just this screen.
    var onDone: () -> Void

    @Environment(NutritionStore.self) private var nutrition
    @Environment(HealthService.self) private var health

    @State private var grams: Double = 100
    @State private var selectedMeal: Meal = .snacks
    @State private var amountText: String = ""
    @State private var hasPrepared = false
    @State private var feedback = 0

    private var facts: NutritionFacts { food.per100.scaled(toGrams: grams) }
    private var canSave: Bool { grams > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                amountCard
                factsCard

                if hasDetail {
                    detailCard
                }

                sourceNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { save() }
                    .font(.system(.subheadline, weight: .bold))
                    .disabled(!canSave)
            }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear(perform: prepare)
    }

    /// Opens on the packet's own serving, which is the portion most people eat.
    private func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        selectedMeal = meal
        grams = food.defaultPortion.grams
        amountText = Self.text(for: grams)
    }

    // MARK: - Cards

    private var headerCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let brand = food.subtitle {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(1)
                }

                Text("\(Int(food.per100.energyKilocalories.rounded())) kcal per 100 \(food.measureUnit)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .panel()
    }

    private var amountCard: some View {
        VStack(spacing: 14) {
            // Quick portions first, since tapping one is the common case and
            // typing an exact weight is the exception.
            if food.selectablePortions.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(food.selectablePortions) { portion in
                            portionChip(portion)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 14)
            }

            HStack(spacing: 12) {
                stepButton("minus", enabled: grams > stepSize) {
                    setGrams(grams - stepSize)
                }

                VStack(spacing: 1) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.metric(30))
                        .foregroundStyle(Theme.textPrimary)
                        .onChange(of: amountText) { _, text in
                            guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
                            grams = min(max(0, value), 5_000)
                        }

                    Text(food.measureUnit)
                        .font(.system(.caption2, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                stepButton("plus", enabled: grams < 5_000) {
                    setGrams(grams + stepSize)
                }
            }
            .padding(.horizontal, 14)

            Picker("Meal", selection: $selectedMeal) {
                ForEach(Meal.allCases) { meal in
                    Text(meal.title).tag(meal)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 14)
        .panel()
    }

    /// Steps by a size that suits the food: the packet's serving when it has
    /// one, so a 330 ml can does not have to be nudged up ten grams at a time.
    private var stepSize: Double {
        let serving = food.selectablePortions.first { $0.grams != 100 }?.grams
        guard let serving, serving >= 5 else { return 10 }
        return serving.rounded()
    }

    private func portionChip(_ portion: FoodPortion) -> some View {
        let isActive = abs(portion.grams - grams) < 0.5
        return Button {
            setGrams(portion.grams)
        } label: {
            Text(portion.name)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(isActive ? Theme.canvas : Theme.textPrimary.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isActive ? Theme.accent : Theme.textPrimary.opacity(0.07),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
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

    private func setGrams(_ value: Double) {
        let clamped = min(max(0, value), 5_000)
        grams = clamped
        amountText = Self.text(for: clamped)
    }

    private static func text(for grams: Double) -> String {
        grams == grams.rounded()
            ? String(Int(grams))
            : String(format: "%.1f", grams)
    }

    /// What this portion actually adds to the day.
    private var factsCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(facts.energyKilocalories.rounded()))")
                    .font(.metric(32))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 14) {
                ForEach(Macro.allCases) { macro in
                    // No target here — this is one portion, not the whole day.
                    MacroBar(macro: macro, grams: macro.grams(in: facts), target: 0)
                }
            }
        }
        .padding(16)
        .panel()
        .animation(.snappy(duration: 0.25), value: grams)
    }

    private var hasDetail: Bool {
        facts.saturatedFatGrams != nil || facts.sugarGrams != nil
            || facts.fibreGrams != nil || facts.sodiumMilligrams != nil
    }

    /// Only the values the food database actually holds — a blank panel is left
    /// blank rather than filled with zeroes nobody verified.
    private var detailCard: some View {
        VStack(spacing: 0) {
            detailRow("Saturated fat", facts.saturatedFatGrams, "g")
            detailRow("Sugars", facts.sugarGrams, "g")
            detailRow("Fibre", facts.fibreGrams, "g")
            detailRow("Sodium", facts.sodiumMilligrams, "mg")
        }
        .padding(.vertical, 4)
        .panel()
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: Double?, _ unit: String) -> some View {
        if let value {
            HStack {
                Text(label)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                Spacer(minLength: 0)
                Text("\(value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))) \(unit)")
                    .font(.metric(14))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private var sourceNote: some View {
        if food.source == .openFoodFacts {
            Text("Nutrition from Open Food Facts, contributed by its community. Check it against the packet if something looks wrong.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }

        let entry = FoodEntry(
            food: food,
            grams: grams,
            meal: selectedMeal,
            loggedAt: loggedAt
        )
        nutrition.add(entry)
        feedback += 1

        // Health is written after the diary, so a failure there never costs the
        // athlete the entry itself.
        Task {
            let ids = await health.saveFood(entry)
            nutrition.attachHealthSamples(ids, entryID: entry.id)
        }

        onDone()
    }

    /// Logging into a past day keeps the time of day, so the entry lands on the
    /// day being viewed rather than jumping to now.
    private var loggedAt: Date {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(date) else { return .now }
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }
}
