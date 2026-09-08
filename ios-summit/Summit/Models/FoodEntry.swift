import Foundation

/// Which sitting a food was logged against.
nonisolated enum Meal: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snacks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "carrot.fill"
        }
    }

    /// The meal the clock suggests, so adding food opens on the likely one
    /// instead of making the athlete pick every time.
    static func suggested(at date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snacks
        }
    }
}

/// One food, at one portion, eaten at one sitting.
nonisolated struct FoodEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var food: FoodItem
    /// The portion actually eaten, in grams or millilitres.
    var grams: Double
    var meal: Meal
    var loggedAt: Date = .now
    /// The samples this entry wrote into Apple Health, so deleting it here can
    /// take them back out rather than leaving Health permanently overstated.
    var healthSampleIDs: [UUID] = []

    init(
        id: UUID = UUID(),
        food: FoodItem,
        grams: Double,
        meal: Meal,
        loggedAt: Date = .now,
        healthSampleIDs: [UUID] = []
    ) {
        self.id = id
        self.food = food
        self.grams = grams
        self.meal = meal
        self.loggedAt = loggedAt
        self.healthSampleIDs = healthSampleIDs
    }

    /// What this portion actually contributes.
    var facts: NutritionFacts { food.per100.scaled(toGrams: grams) }

    /// The portion as it reads in the diary, e.g. `45 g` or `330 ml`.
    var portionLabel: String {
        "\(Int(grams.rounded())) \(food.measureUnit)"
    }

    /// Entries written before Health write-back existed have no sample list,
    /// so it decodes as empty rather than failing the whole diary.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        food = try container.decode(FoodItem.self, forKey: .food)
        grams = try container.decode(Double.self, forKey: .grams)
        meal = try container.decodeIfPresent(Meal.self, forKey: .meal) ?? .snacks
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        healthSampleIDs = try container.decodeIfPresent([UUID].self, forKey: .healthSampleIDs) ?? []
    }
}

/// One day's eating, totalled and grouped for the diary.
nonisolated struct DayNutrition: Sendable, Equatable {
    var entries: [FoodEntry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Everything eaten that day added together.
    var total: NutritionFacts {
        entries.reduce(NutritionFacts.zero) { $0 + $1.facts }
    }

    func entries(for meal: Meal) -> [FoodEntry] {
        entries.filter { $0.meal == meal }.sorted { $0.loggedAt < $1.loggedAt }
    }

    func total(for meal: Meal) -> NutritionFacts {
        entries(for: meal).reduce(NutritionFacts.zero) { $0 + $1.facts }
    }
}

/// A week of eating, for a report rather than a single day.
///
/// Only days with something logged are included. Averaging in the days somebody
/// forgot to open the app would report a starvation diet and then offer advice
/// based on it.
nonisolated struct NutritionWeek: Sendable, Equatable {
    var days: [DayNutrition] = []

    var loggedDayCount: Int { days.count }
    var isEmpty: Bool { days.isEmpty }

    var averageEnergy: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.total.energyKilocalories } / Double(days.count)
    }

    var averageProtein: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.total.proteinGrams } / Double(days.count)
    }

    /// Days inside a tenth either side of the target — close enough that nobody
    /// sensible would call it a miss.
    func daysOnTarget(_ target: Double) -> Int {
        guard target > 0 else { return 0 }
        return days.filter { abs($0.total.energyKilocalories - target) <= target * 0.1 }.count
    }

    func daysOver(_ target: Double) -> Int {
        guard target > 0 else { return 0 }
        return days.filter { $0.total.energyKilocalories > target * 1.1 }.count
    }

    func daysUnder(_ target: Double) -> Int {
        guard target > 0 else { return 0 }
        return days.filter { $0.total.energyKilocalories < target * 0.9 }.count
    }
}
