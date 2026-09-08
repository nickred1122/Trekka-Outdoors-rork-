import Foundation
import Observation

/// Owns the food diary and the athlete's targets, persisting both to disk.
///
/// Entries are kept whole — each one carries its own copy of the food it logged
/// — so a day in the past always reads back exactly as it was recorded, even if
/// the same product is corrected in the database afterwards.
@Observable
final class NutritionStore {
    private(set) var entries: [FoodEntry] = []
    private(set) var goals: NutritionGoals = .default
    /// Foods logged before, most recent first, so the things someone eats every
    /// day take one tap instead of a search.
    private(set) var recentFoods: [FoodItem] = []
    /// Foods the athlete pinned, which stay put however long ago they were last
    /// eaten. Recents fall off the end of the list; a favourite should not.
    private(set) var favouriteFoods: [FoodItem] = []
    /// Drinks, kept apart from the diary because water carries no energy and no
    /// macros — filing it as food would put rows against meals that contribute
    /// nothing to any total.
    private(set) var waterEntries: [WaterEntry] = []
    var lastError: String?

    private let entriesFile = "nutrition-entries.json"
    private let goalsFile = "nutrition-goals.json"
    private let recentsFile = "nutrition-recents.json"
    private let favouritesFile = "nutrition-favourites.json"
    private let waterFile = "nutrition-water.json"

    /// How many foods to remember. Enough to cover a normal repertoire without
    /// the list becoming its own search problem.
    private static let recentLimit = 40

    init() {
        entries = decode([FoodEntry].self, from: entriesFile) ?? []
        goals = decode(NutritionGoals.self, from: goalsFile) ?? .default
        recentFoods = decode([FoodItem].self, from: recentsFile) ?? []
        favouriteFoods = decode([FoodItem].self, from: favouritesFile) ?? []
        waterEntries = decode([WaterEntry].self, from: waterFile) ?? []
    }

    // MARK: - Queries

    /// Everything logged on one calendar day.
    func day(_ date: Date) -> DayNutrition {
        let calendar = Calendar.current
        return DayNutrition(entries: entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) })
    }

    /// Days that have at least one entry, newest first — the diary's history.
    var loggedDays: [Date] {
        let calendar = Calendar.current
        let days = Set(entries.map { calendar.startOfDay(for: $0.loggedAt) })
        return days.sorted(by: >)
    }

    func entry(id: UUID) -> FoodEntry? {
        entries.first { $0.id == id }
    }

    /// One day's drinking.
    func water(_ date: Date) -> DayWater {
        let calendar = Calendar.current
        return DayWater(entries: waterEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) })
    }

    /// The foods eaten most often, most frequent first.
    ///
    /// Different from recents, and more useful: the thing somebody eats every
    /// single morning can easily be pushed down a recency list by a week of
    /// one-off meals, which is exactly when they most want it in one tap.
    var frequentFoods: [FoodItem] {
        var counts: [String: (food: FoodItem, count: Int)] = [:]
        for entry in entries {
            let key = Self.key(for: entry.food)
            if let existing = counts[key] {
                counts[key] = (existing.food, existing.count + 1)
            } else {
                counts[key] = (entry.food, 1)
            }
        }
        return counts.values
            // Twice is a coincidence; three times is a habit worth surfacing.
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
            .prefix(20)
            .map(\.food)
    }

    func isFavourite(_ food: FoodItem) -> Bool {
        let key = Self.key(for: food)
        return favouriteFoods.contains { Self.key(for: $0) == key }
    }

    /// What the whole week says, for a report rather than a single day.
    ///
    /// Only days with something logged count. Averaging in the days somebody
    /// forgot to open the app would report a starvation diet.
    func weekSummary(endingOn date: Date = .now) -> NutritionWeek {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: date)
        var days: [DayNutrition] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let logged = self.day(day)
            guard !logged.isEmpty else { continue }
            days.append(logged)
        }
        return NutritionWeek(days: days)
    }

    // MARK: - Mutations

    // MARK: - Mutations

    func add(_ entry: FoodEntry) {
        entries.append(entry)
        remember(entry.food)
        persistEntries()
    }

    func update(_ entry: FoodEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        persistEntries()
    }

    /// Removes an entry and hands back the Health samples it wrote, so the
    /// caller can take those out of Health too.
    @discardableResult
    func remove(entryID: UUID) -> [UUID] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return [] }
        let removed = entries.remove(at: index)
        persistEntries()
        return removed.healthSampleIDs
    }

    /// Records which Health samples an entry produced, once the write comes back.
    func attachHealthSamples(_ ids: [UUID], entryID: UUID) {
        guard !ids.isEmpty, let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].healthSampleIDs = ids
        persistEntries()
    }

    func setGoals(_ newGoals: NutritionGoals) {
        goals = newGoals
        encode(goals, to: goalsFile)
    }

    // MARK: - Quick add

    /// Logs a bare number of calories against a meal.
    ///
    /// The honest answer to a restaurant meal or somebody else's cooking: the
    /// calories are known roughly, the ingredients are not, and inventing macros
    /// to fill the gap would corrupt every macro total that day.
    @discardableResult
    func quickAdd(kilocalories: Double, meal: Meal, date: Date, name: String = "Quick add") -> FoodEntry? {
        guard kilocalories > 0 else { return nil }
        let entry = FoodEntry(
            food: .quickAdd(kilocalories: kilocalories, name: name),
            grams: 100,
            meal: meal,
            loggedAt: Self.timestamp(on: date)
        )
        entries.append(entry)
        // Deliberately not remembered as a recent food: a one-off number is not
        // something anybody wants offered back to them tomorrow.
        persistEntries()
        return entry
    }

    // MARK: - Water

    func addWater(millilitres: Double, date: Date) {
        guard millilitres > 0 else { return }
        waterEntries.append(
            WaterEntry(millilitres: millilitres, loggedAt: Self.timestamp(on: date))
        )
        encode(waterEntries, to: waterFile)
    }

    /// Takes the most recent drink of that day back off, which is what somebody
    /// tapping one too many times actually wants.
    func removeLastWater(on date: Date) {
        let calendar = Calendar.current
        guard let index = waterEntries.lastIndex(where: {
            calendar.isDate($0.loggedAt, inSameDayAs: date)
        }) else { return }
        waterEntries.remove(at: index)
        encode(waterEntries, to: waterFile)
    }

    // MARK: - Favourites

    func toggleFavourite(_ food: FoodItem) {
        let key = Self.key(for: food)
        if favouriteFoods.contains(where: { Self.key(for: $0) == key }) {
            favouriteFoods.removeAll { Self.key(for: $0) == key }
        } else {
            favouriteFoods.insert(food, at: 0)
        }
        encode(favouriteFoods, to: favouritesFile)
    }

    // MARK: - Copying

    /// Copies one meal from another day onto this one.
    ///
    /// Anybody who eats the same breakfast every day was re-logging it every
    /// morning, item by item.
    @discardableResult
    func copy(meal: Meal, from source: Date, to destination: Date) -> Int {
        let items = day(source).entries(for: meal)
        guard !items.isEmpty else { return 0 }
        for item in items {
            entries.append(
                FoodEntry(
                    food: item.food,
                    grams: item.grams,
                    meal: meal,
                    loggedAt: Self.timestamp(on: destination)
                )
            )
        }
        persistEntries()
        return items.count
    }

    /// Copies a whole day's eating onto another day, meal by meal.
    @discardableResult
    func copyDay(from source: Date, to destination: Date) -> Int {
        var copied = 0
        for meal in Meal.allCases {
            copied += copy(meal: meal, from: source, to: destination)
        }
        return copied
    }

    /// The most recent earlier day with anything logged, which is what "copy
    /// yesterday" should actually mean when yesterday was skipped.
    func lastLoggedDay(before date: Date) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return loggedDays.first { $0 < start }
    }

    /// Puts a food at the top of the recents, keeping one entry per product.
    private func remember(_ food: FoodItem) {
        // Matched on barcode where there is one, so the same product scanned
        // twice does not fill the list with near-duplicates.
        recentFoods.removeAll { existing in
            if let barcode = food.barcode, !barcode.isEmpty {
                return existing.barcode == barcode
            }
            return existing.name == food.name && existing.brand == food.brand
        }
        recentFoods.insert(food, at: 0)
        if recentFoods.count > Self.recentLimit {
            recentFoods.removeLast(recentFoods.count - Self.recentLimit)
        }
        encode(recentFoods, to: recentsFile)
    }

    func forgetRecent(_ food: FoodItem) {
        recentFoods.removeAll { $0.id == food.id }
        encode(recentFoods, to: recentsFile)
    }

    /// Identity for “the same product”: the barcode when there is one, else the
    /// name and brand together.
    private static func key(for food: FoodItem) -> String {
        if let barcode = food.barcode, !barcode.isEmpty { return "bar:\(barcode)" }
        return "name:\(food.name.lowercased())|\(food.brand?.lowercased() ?? "")"
    }

    /// Keeps the time of day when logging onto today, and puts a backdated entry
    /// at midday rather than at midnight — midnight lands on the day boundary,
    /// where a timezone shift can move it onto the wrong day entirely.
    private static func timestamp(on date: Date) -> Date {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(date) else { return Date() }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    // MARK: - Persistence

    private func persistEntries() {
        encode(entries, to: entriesFile)
    }

    private func url(for file: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(file)
    }

    private func encode<T: Encodable>(_ value: T, to file: String) {
        guard let url = url(for: file) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            lastError = "Could not save your food diary locally."
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let url = url(for: file), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
