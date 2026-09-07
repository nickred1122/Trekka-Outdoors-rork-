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

                ForEach(Meal.allCases) { meal in
                    mealCard(meal)
                }

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
        }
        .panel(radius: 14)
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
