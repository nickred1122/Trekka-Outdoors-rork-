import SwiftUI

/// The food diary: what has been eaten today, against what the day asks for.
///
/// Energy sits alongside the energy actually burned, because fuelling a long day
/// on the hill is a different problem from fuelling a rest day, and the app
/// already knows which kind of day it has been.
struct FuelView: View {
    @Environment(NutritionStore.self) private var nutrition
    @Environment(HealthService.self) private var health

    @State private var date: Date = .now
    @State private var addingMeal: Meal?
    @State private var isEditingGoals = false
    /// The meal a bare calorie figure is being typed against.
    @State private var quickAddMeal: Meal?
    @State private var quickAddText = ""
    @State private var feedback = 0
    @State private var notice: String?

    private var day: DayNutrition { nutrition.day(date) }
    private var goals: NutritionGoals { nutrition.goals }

    /// What was burned on the day being shown.
    ///
    /// Today comes from the live snapshot; earlier days come from the daily
    /// history, which is ordered oldest first and ends on today.
    private var activeEnergy: Double {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return health.snapshot.activeCalories }
        let daily = health.history.dailyValues(.calories)
        guard let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: .now)
        ).day, offset > 0 else { return 0 }
        let index = daily.count - 1 - offset
        return daily.indices.contains(index) ? daily[index] : 0
    }

    private var target: Double { goals.energyTarget(activeEnergy: activeEnergy) }
    private var consumed: Double { day.total.energyKilocalories }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                dateBar
                summaryCard

                if let notice {
                    noticeCard(notice)
                }

                if day.isEmpty, let source = nutrition.lastLoggedDay(before: date) {
                    copyDayCard(from: source)
                }

                ForEach(Meal.allCases) { meal in
                    mealCard(meal)
                }

                waterCard

                weekCard

                footnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditingGoals = true
                } label: {
                    Image(systemName: "target")
                }
                .accessibilityLabel("Daily targets")
            }
        }
        .sheet(item: $addingMeal) { meal in
            FoodSearchView(meal: meal, date: date)
        }
        .sheet(isPresented: $isEditingGoals) {
            NutritionGoalsView()
        }
        .sensoryFeedback(.success, trigger: feedback)
        .animation(.snappy(duration: 0.28), value: notice)
        .alert("Quick add", isPresented: quickAddBinding) {
            TextField("Calories", text: $quickAddText)
                .keyboardType(.numberPad)
            Button("Add") { commitQuickAdd() }
            Button("Cancel", role: .cancel) { quickAddMeal = nil }
        } message: {
            Text("For a meal you know the calories of but not the ingredients. Logged as energy only \u{2014} no invented macros.")
        }
    }

    private var quickAddBinding: Binding<Bool> {
        Binding(
            get: { quickAddMeal != nil },
            set: { if !$0 { quickAddMeal = nil } }
        )
    }

    private func commitQuickAdd() {
        defer {
            quickAddMeal = nil
            quickAddText = ""
        }
        guard let meal = quickAddMeal,
              let value = Double(quickAddText.trimmingCharacters(in: .whitespaces)),
              value > 0 else { return }
        nutrition.quickAdd(kilocalories: value, meal: meal, date: date)
        feedback += 1
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.positive)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
            Spacer(minLength: 0)
            Button {
                notice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .panel()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Copying a day forward, offered only when today is still empty.
    ///
    /// Anybody who eats roughly the same thing daily was re-logging every item
    /// every morning. The source is the last day actually logged rather than
    /// literally yesterday, so a skipped day does not offer to copy nothing.
    private func copyDayCard(from source: Date) -> some View {
        Button {
            let copied = nutrition.copyDay(from: source, to: date)
            guard copied > 0 else { return }
            notice = "Copied \(copied) \(copied == 1 ? "item" : "items") from \(sourceLabel(source))."
            feedback += 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Copy \(sourceLabel(source))")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Brings that day's food across, ready to edit")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .panel()
        }
        .buttonStyle(TilePressStyle())
    }

    private func sourceLabel(_ source: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInYesterday(source) { return "yesterday" }
        return source.formatted(.dateTime.weekday(.wide)).lowercased()
    }

    // MARK: - Date

    private var dateBar: some View {
        HStack(spacing: 10) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Spacer(minLength: 0)

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(isToday)
            .opacity(isToday ? 0.3 : 1)
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    /// Moves a day at a time, never past today — there is nothing to log forward.
    private func step(_ days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        guard moved <= Date() || Calendar.current.isDateInToday(moved) else { return }
        withAnimation(.snappy(duration: 0.25)) { date = moved }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                EnergyRing(consumed: consumed, target: target, diameter: 150, lineWidth: 14)

                VStack(alignment: .leading, spacing: 12) {
                    energyLine(
                        symbol: "fork.knife",
                        label: "Eaten",
                        value: consumed,
                        tint: Theme.accent
                    )
                    energyLine(
                        symbol: "flame.fill",
                        label: "Burned",
                        value: activeEnergy,
                        tint: Theme.highlight
                    )
                    energyLine(
                        symbol: "target",
                        label: "Target",
                        value: target,
                        tint: Theme.textPrimary.opacity(0.6)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if goals.addsActiveEnergy, activeEnergy > 0 {
                Text("Today's target includes the \(Int(activeEnergy.rounded())) kcal you burned.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Theme.border)

            HStack(alignment: .top, spacing: 14) {
                ForEach(Macro.allCases) { macro in
                    MacroBar(
                        macro: macro,
                        grams: macro.grams(in: day.total),
                        target: macro.target(in: goals, activeEnergy: activeEnergy)
                    )
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func energyLine(symbol: String, label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text("\(Int(value.rounded())) kcal")
                    .font(.metric(15))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    // MARK: - Meals

    private func mealCard(_ meal: Meal) -> some View {
        let entries = day.entries(for: meal)
        let total = day.total(for: meal)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: meal.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 8))

                Text(meal.title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                if !entries.isEmpty {
                    Text("\(Int(total.energyKilocalories.rounded())) kcal")
                        .font(.metric(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, entries.isEmpty ? 8 : 10)

            ForEach(entries) { entry in
                entryRow(entry)
            }

            HStack(spacing: 0) {
                Button {
                    addingMeal = meal
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add food")
                            .font(.system(.subheadline, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        quickAddText = ""
                        quickAddMeal = meal
                    } label: {
                        Label("Quick add calories", systemImage: "number")
                    }
                    if let source = nutrition.lastLoggedDay(before: date),
                       !nutrition.day(source).entries(for: meal).isEmpty {
                        Button {
                            let copied = nutrition.copy(meal: meal, from: source, to: date)
                            guard copied > 0 else { return }
                            notice = "Copied \(meal.title.lowercased()) from \(sourceLabel(source))."
                            feedback += 1
                        } label: {
                            Label("Copy from \(sourceLabel(source))", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More ways to log \(meal.title.lowercased())")
            }
        }
        .panel(radius: 14)
    }

    // MARK: - Water

    /// Drinking, in one tap.
    ///
    /// Kept out of the food diary because water carries no energy and no macros:
    /// filing it as food would put rows against meals that contribute nothing to
    /// any total.
    private var waterCard: some View {
        let logged = nutrition.water(date).millilitres
        let target: Double = 2_000

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.zoneColors[3])
                    .frame(width: 26, height: 26)
                    .background(Theme.zoneColors[3].opacity(0.14), in: .rect(cornerRadius: 8))
                Text("Water")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(waterLabel(logged))
                    .font(.metric(14))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(Theme.zoneColors[3])
                        .frame(width: max(logged > 0 ? 6 : 0, geometry.size.width * min(1, logged / target)))
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                ForEach(WaterMeasure.allCases) { measure in
                    Button {
                        nutrition.addWater(millilitres: measure.millilitres, date: date)
                        feedback += 1
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: measure.symbol)
                                .font(.system(size: 13, weight: .semibold))
                            Text(measure.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.zoneColors[3])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a \(measure.title.lowercased()) of water")
                }

                Button {
                    nutrition.removeLastWater(on: date)
                    feedback += 1
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(logged > 0 ? 0.6 : 0.25))
                        .frame(width: 40)
                        .padding(.vertical, 13)
                        .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(logged <= 0)
                .accessibilityLabel("Undo the last drink")
            }
        }
        .padding(14)
        .panel()
    }

    /// Litres once there is a litre to speak of, millilitres below that.
    private func waterLabel(_ millilitres: Double) -> String {
        guard millilitres >= 1_000 else { return "\(Int(millilitres.rounded())) ml" }
        return String(format: "%.1f L", millilitres / 1_000)
    }

    // MARK: - Week

    /// The week, which is the scale eating actually happens on.
    ///
    /// A single day over target means nothing; four of them in a row is the
    /// thing worth knowing. Only days with something logged count — averaging in
    /// the days somebody forgot to open the app would report a starvation diet.
    @ViewBuilder
    private var weekCard: some View {
        let week = nutrition.weekSummary(endingOn: date)
        if week.loggedDayCount >= 2 {
            let onTarget = week.daysOnTarget(target)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 8))
                    Text("This week")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(week.loggedDayCount) \(week.loggedDayCount == 1 ? "day" : "days") logged")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }

                HStack(spacing: 10) {
                    weekStat("Average", "\(Int(week.averageEnergy.rounded()))", "kcal")
                    weekStat("Protein", "\(Int(week.averageProtein.rounded()))", "g avg")
                    weekStat("On target", "\(onTarget)", "of \(week.loggedDayCount)")
                }

                Text(weekVerdict(week, onTarget: onTarget))
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .panel()
        }
    }

    private func weekStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text(value)
                .font(.metric(18))
                .foregroundStyle(Theme.textPrimary)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))
    }

    private func weekVerdict(_ week: NutritionWeek, onTarget: Int) -> String {
        guard target > 0 else { return "Set a daily target to see how the week compares." }
        let over = week.daysOver(target)
        let under = week.daysUnder(target)
        if onTarget == week.loggedDayCount {
            return "Every logged day inside a tenth of your target. That is the hard part done."
        }
        if over > under {
            return "\(over) \(over == 1 ? "day" : "days") over target, averaging \(Int((week.averageEnergy - target).rounded())) kcal above it."
        }
        if under > over {
            return "\(under) \(under == 1 ? "day" : "days") under target. Worth checking on a heavy training week."
        }
        return "An even split of days above and below your target."
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.food.name)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(subtitle(for: entry))
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("\(Int(entry.facts.energyKilocalories.rounded()))")
                    .font(.metric(14))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    remove(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    remove(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            Divider()
                .overlay(Theme.border)
                .padding(.leading, 12)
        }
    }

    private func subtitle(for entry: FoodEntry) -> String {
        var parts: [String] = [entry.portionLabel]
        if let brand = entry.food.subtitle { parts.append(brand) }
        return parts.joined(separator: " · ")
    }

    /// Removing an entry also takes its samples back out of Apple Health, so the
    /// two never disagree about what was eaten.
    private func remove(_ entry: FoodEntry) {
        let sampleIDs = nutrition.remove(entryID: entry.id)
        guard !sampleIDs.isEmpty else { return }
        Task { await health.deleteFoodSamples(sampleIDs) }
    }

    @ViewBuilder
    private var footnote: some View {
        if health.authorization == .authorized {
            Text("Food you log is saved to Apple Health.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }
}
