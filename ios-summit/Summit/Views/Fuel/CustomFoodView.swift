import SwiftUI

/// Entering a food by hand, for anything the database has never heard of —
/// a home-cooked meal, a bakery item, the café down the road.
struct CustomFoodView: View {
    let meal: Meal
    let date: Date
    var onDone: () -> Void

    @Environment(NutritionStore.self) private var nutrition
    @Environment(HealthService.self) private var health

    @State private var name = ""
    @State private var brand = ""
    @State private var servingText = "100"
    @State private var energyText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var selectedMeal: Meal = .snacks
    @State private var hasPrepared = false
    @State private var feedback = 0

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case name, brand, serving, energy, protein, carbs, fat
    }

    private var servingGrams: Double {
        max(1, number(servingText) ?? 100)
    }

    /// A food needs a name and some energy to be worth logging.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (number(energyText) ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                nameCard
                servingCard
                macrosCard
                mealCard
                note
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("New food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { save() }
                    .font(.system(.subheadline, weight: .bold))
                    .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear {
            guard !hasPrepared else { return }
            hasPrepared = true
            selectedMeal = meal
        }
    }

    // MARK: - Cards

    private var nameCard: some View {
        VStack(spacing: 0) {
            field("Name", text: $name, placeholder: "Porridge with berries", field: .name)
            Divider().overlay(Theme.border).padding(.leading, 14)
            field("Brand", text: $brand, placeholder: "Optional", field: .brand)
        }
        .panel()
    }

    private var servingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            numberField(
                "Serving weight",
                text: $servingText,
                unit: "g",
                field: .serving
            )

            Text("Everything below is for one serving of this size.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
        }
        .panel()
    }

    private var macrosCard: some View {
        VStack(spacing: 0) {
            numberField("Energy", text: $energyText, unit: "kcal", field: .energy)
            Divider().overlay(Theme.border).padding(.leading, 14)
            numberField("Protein", text: $proteinText, unit: "g", field: .protein)
            Divider().overlay(Theme.border).padding(.leading, 14)
            numberField("Carbs", text: $carbsText, unit: "g", field: .carbs)
            Divider().overlay(Theme.border).padding(.leading, 14)
            numberField("Fat", text: $fatText, unit: "g", field: .fat)
        }
        .panel()
    }

    private var mealCard: some View {
        Picker("Meal", selection: $selectedMeal) {
            ForEach(Meal.allCases) { meal in
                Text(meal.title).tag(meal)
            }
        }
        .pickerStyle(.segmented)
    }

    private var note: some View {
        Text("Saved to your recent foods, so you can log it again in one tap.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        field: Field
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .frame(width: 96, alignment: .leading)

            TextField(placeholder, text: text)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused, equals: field)
                .submitLabel(.next)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func numberField(
        _ label: String,
        text: Binding<String>,
        unit: String,
        field: Field
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .frame(width: 96, alignment: .leading)

            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(.metric(16))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused, equals: field)

            Text(unit)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Saving

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard canSave else { return }

        // Typed in per serving, stored per 100 g like every other food, so the
        // portion controls behave identically to a scanned product.
        let factor = 100 / servingGrams
        let facts = NutritionFacts(
            energyKilocalories: (number(energyText) ?? 0) * factor,
            proteinGrams: (number(proteinText) ?? 0) * factor,
            carbohydrateGrams: (number(carbsText) ?? 0) * factor,
            fatGrams: (number(fatText) ?? 0) * factor
        )

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = FoodItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            barcode: nil,
            per100: facts,
            portions: [FoodPortion(name: "Serving (\(Int(servingGrams)) g)", grams: servingGrams)],
            isLiquid: false,
            imageURL: nil,
            source: .custom
        )

        let entry = FoodEntry(
            food: food,
            grams: servingGrams,
            meal: selectedMeal,
            loggedAt: loggedAt
        )
        nutrition.add(entry)
        feedback += 1

        Task {
            let ids = await health.saveFood(entry)
            nutrition.attachHealthSamples(ids, entryID: entry.id)
        }

        onDone()
    }

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
