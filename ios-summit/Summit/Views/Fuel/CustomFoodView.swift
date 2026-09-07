import SwiftUI

/// Entering a food by hand, for anything the database has never heard of —
/// a home-cooked meal, a bakery item, the café down the road.
struct CustomFoodView: View {
    let meal: Meal
    let date: Date
    /// What a nutrition-label scan read, when the athlete arrived that way.
    /// Every value lands in an editable field rather than being saved directly:
    /// recognised text is a good starting point, never a fact.
    var prefill: NutritionLabelReading?
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
    @State private var saturatedText = ""
    @State private var sugarText = ""
    @State private var fibreText = ""
    @State private var sodiumText = ""
    @State private var selectedMeal: Meal = .snacks
    @State private var hasPrepared = false
    @State private var showsDetail = false
    @State private var feedback = 0

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case name, brand, serving, energy, protein, carbs, fat
        case saturated, sugar, fibre, sodium
    }

    /// True when a scan could not work out what one serving weighs, so the
    /// numbers on screen describe a serving of unknown size. Saving in that
    /// state would scale everything by a guess, so the field is asked for.
    private var needsServingWeight: Bool {
        guard let prefill else { return false }
        return prefill.basis == .perServing && prefill.servingGrams == nil
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
                if prefill != nil { scanBanner }
                nameCard
                servingCard
                macrosCard
                detailCard
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
        .animation(.snappy(duration: 0.25), value: showsDetail)
        .onAppear {
            guard !hasPrepared else { return }
            hasPrepared = true
            selectedMeal = meal
            applyPrefill()
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

    /// Says where these numbers came from and what still needs a human.
    private var scanBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: needsServingWeight ? "exclamationmark.triangle.fill" : "doc.text.viewfinder")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(needsServingWeight ? Theme.highlight : Theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(needsServingWeight ? "Add the serving weight" : "Read from the label")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(scanDetail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (needsServingWeight ? Theme.highlight : Theme.accent).opacity(0.1),
            in: .rect(cornerRadius: Theme.cardRadius)
        )
    }

    private var scanDetail: String {
        guard let prefill else { return "" }
        if needsServingWeight {
            return "The panel gave its values per serving but didn't say what a serving weighs. Enter it above, then check the rest."
        }
        if prefill.energyAgreesWithMacros == false {
            return "Check these against the packet — the energy and the macros don't quite add up, so something may have been misread."
        }
        return "Check these against the packet before saving. Anything the label didn't print has been left blank."
    }

    /// The lines a label prints that the main card has no room for. Collapsed
    /// by default, and left blank when the packet did not state them — a food
    /// with no fibre figure must not be recorded as having none.
    private var detailCard: some View {
        VStack(spacing: 0) {
            Button {
                showsDetail.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text("More detail")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                        .rotationEffect(.degrees(showsDetail ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showsDetail {
                Divider().overlay(Theme.border).padding(.leading, 14)
                numberField("Saturates", text: $saturatedText, unit: "g", field: .saturated)
                Divider().overlay(Theme.border).padding(.leading, 14)
                numberField("Sugars", text: $sugarText, unit: "g", field: .sugar)
                Divider().overlay(Theme.border).padding(.leading, 14)
                numberField("Fibre", text: $fibreText, unit: "g", field: .fibre)
                Divider().overlay(Theme.border).padding(.leading, 14)
                numberField("Sodium", text: $sodiumText, unit: "mg", field: .sodium)
            }
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

    /// Fills the form from a label scan, in the units the form works in.
    ///
    /// The form is per serving, so a European panel's per-100 values are laid in
    /// with a 100 g serving — which is exactly what that panel describes.
    private func applyPrefill() {
        guard let prefill else { return }

        switch prefill.basis {
        case .per100:
            servingText = "100"
        case .perServing:
            servingText = prefill.servingGrams.map { format($0) } ?? ""
        }

        energyText = prefill.energyKilocalories.map { format($0) } ?? ""
        proteinText = prefill.proteinGrams.map { format($0) } ?? ""
        carbsText = prefill.carbohydrateGrams.map { format($0) } ?? ""
        fatText = prefill.fatGrams.map { format($0) } ?? ""
        saturatedText = prefill.saturatedFatGrams.map { format($0) } ?? ""
        sugarText = prefill.sugarGrams.map { format($0) } ?? ""
        fibreText = prefill.fibreGrams.map { format($0) } ?? ""
        sodiumText = prefill.sodiumMilligrams.map { format($0) } ?? ""

        // Opened when the scan actually found something to show, so the extra
        // lines are not hidden behind a tap the athlete has no reason to make.
        showsDetail = !saturatedText.isEmpty || !sugarText.isEmpty
            || !fibreText.isEmpty || !sodiumText.isEmpty

        if needsServingWeight {
            focused = .serving
        }
    }

    /// Trims a scanned value to something a person would have typed.
    private func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
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
            fatGrams: (number(fatText) ?? 0) * factor,
            // Left nil when the field is blank, so an unstated line stays
            // unstated rather than being recorded as a zero.
            saturatedFatGrams: number(saturatedText).map { $0 * factor },
            sugarGrams: number(sugarText).map { $0 * factor },
            fibreGrams: number(fibreText).map { $0 * factor },
            sodiumMilligrams: number(sodiumText).map { $0 * factor }
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
