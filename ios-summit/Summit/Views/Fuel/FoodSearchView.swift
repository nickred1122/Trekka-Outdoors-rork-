import SwiftUI

/// Finding something to log: by barcode, by name, or from what you eat often.
struct FoodSearchView: View {
    let meal: Meal
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(NutritionStore.self) private var nutrition

    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var isScanning = false
    @State private var isLookingUpBarcode = false
    @State private var path = NavigationPath()

    private var recents: [FoodItem] { nutrition.recentFoods }
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    scanButton

                    if let message {
                        notice(message)
                    }

                    if isSearching || isLookingUpBarcode {
                        ProgressView()
                            .tint(Theme.accent)
                            .padding(.vertical, 24)
                    } else if !results.isEmpty {
                        section(title: "Results", foods: results)
                    } else if trimmedQuery.count >= 2, message == nil {
                        emptyResults
                    } else if !recents.isEmpty {
                        section(title: "Recent", foods: recents, isRecent: true)
                    } else {
                        hint
                    }

                    manualButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Add to \(meal.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .navigationDestination(for: FoodItem.self) { food in
                FoodPortionView(food: food, meal: meal, date: date) { dismiss() }
            }
            .navigationDestination(for: CustomFoodDestination.self) { _ in
                CustomFoodView(meal: meal, date: date) { dismiss() }
            }
            .sheet(isPresented: $isScanning) {
                BarcodeScannerView { code in
                    lookUp(barcode: code)
                } onManualEntry: {
                    path.append(CustomFoodDestination())
                }
            }
            // Debounced so a search does not fire on every keystroke — the food
            // database is a shared free service and deserves to be used politely.
            .task(id: trimmedQuery) {
                await runSearch()
            }
        }
    }

    // MARK: - Pieces

    private var scanButton: some View {
        Button {
            message = nil
            isScanning = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan a barcode")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Fastest way to log something packaged")
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

    private var manualButton: some View {
        Button {
            path.append(CustomFoodDestination())
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enter food by hand")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .panel(radius: 14)
    }

    private func section(title: String, foods: [FoodItem], isRecent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                    Button {
                        path.append(food)
                    } label: {
                        foodRow(food)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isRecent {
                            Button(role: .destructive) {
                                nutrition.forgetRecent(food)
                            } label: {
                                Label("Remove from recents", systemImage: "trash")
                            }
                        }
                    }

                    if index < foods.count - 1 {
                        Divider().overlay(Theme.border).padding(.leading, 12)
                    }
                }
            }
            .panel(radius: 14)
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(rowSubtitle(food))
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func rowSubtitle(_ food: FoodItem) -> String {
        var parts: [String] = ["\(Int(food.per100.energyKilocalories.rounded())) kcal / 100 \(food.measureUnit)"]
        if let brand = food.subtitle { parts.append(brand) }
        return parts.joined(separator: " · ")
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel(radius: 12)
    }

    private var emptyResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text("Nothing found")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Try a different name, or enter the food by hand.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
    }

    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text("Search for a food")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Nutrition comes from Open Food Facts, an open database of packaged food.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 28)
    }

    // MARK: - Lookups

    private func runSearch() async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            message = nil
            isSearching = false
            return
        }

        // Wait out the rest of the typing before spending a request.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let found = try await FoodDatabase.shared.search(text)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            message = (error as? FoodLookupError)?.errorDescription ?? "Couldn't search right now."
        }
    }

    private func lookUp(barcode: String) {
        Task {
            isLookingUpBarcode = true
            message = nil
            defer { isLookingUpBarcode = false }
            do {
                let food = try await FoodDatabase.shared.product(barcode: barcode)
                path.append(food)
            } catch {
                message = (error as? FoodLookupError)?.errorDescription
                    ?? "Couldn't look that barcode up."
            }
        }
    }
}

/// Routes to the hand-entry screen.
nonisolated struct CustomFoodDestination: Hashable, Sendable {}
