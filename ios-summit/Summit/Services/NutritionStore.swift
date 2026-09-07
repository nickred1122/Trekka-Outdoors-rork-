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
    var lastError: String?

    private let entriesFile = "nutrition-entries.json"
    private let goalsFile = "nutrition-goals.json"
    private let recentsFile = "nutrition-recents.json"

    /// How many foods to remember. Enough to cover a normal repertoire without
    /// the list becoming its own search problem.
    private static let recentLimit = 40

    init() {
        entries = decode([FoodEntry].self, from: entriesFile) ?? []
        goals = decode(NutritionGoals.self, from: goalsFile) ?? .default
        recentFoods = decode([FoodItem].self, from: recentsFile) ?? []
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
