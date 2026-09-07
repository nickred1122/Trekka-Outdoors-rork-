import Foundation

/// What a food is made of, always held per 100 g (or per 100 ml for drinks).
///
/// One canonical basis means a portion typed in grams, a serving off the packet
/// and a barcode scan all reduce to the same arithmetic. Nothing is stored
/// per-portion, so changing how much you ate never needs the facts re-fetched.
///
/// Energy is kilocalories because that is what every food label in both
/// measurement systems is read in — unlike distance or mass, there is no
/// imperial variant of a calorie to convert to.
nonisolated struct NutritionFacts: Codable, Hashable, Sendable {
    var energyKilocalories: Double = 0
    var proteinGrams: Double = 0
    var carbohydrateGrams: Double = 0
    var fatGrams: Double = 0
    /// The detail panel shows these when the source has them and stays quiet
    /// when it does not, rather than printing a zero it cannot stand behind.
    var saturatedFatGrams: Double?
    var sugarGrams: Double?
    var fibreGrams: Double?
    var sodiumMilligrams: Double?

    static let zero = NutritionFacts()

    /// The same food at an actual portion size.
    func scaled(toGrams grams: Double) -> NutritionFacts {
        let factor = grams / 100
        return NutritionFacts(
            energyKilocalories: energyKilocalories * factor,
            proteinGrams: proteinGrams * factor,
            carbohydrateGrams: carbohydrateGrams * factor,
            fatGrams: fatGrams * factor,
            saturatedFatGrams: saturatedFatGrams.map { $0 * factor },
            sugarGrams: sugarGrams.map { $0 * factor },
            fibreGrams: fibreGrams.map { $0 * factor },
            sodiumMilligrams: sodiumMilligrams.map { $0 * factor }
        )
    }

    /// Running totals for a meal or a day. Optional details only survive while
    /// every contributor has them, so a day's fibre is never a partial sum
    /// dressed up as a complete one.
    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return nil }
            return a + b
        }
        return NutritionFacts(
            energyKilocalories: lhs.energyKilocalories + rhs.energyKilocalories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            saturatedFatGrams: add(lhs.saturatedFatGrams, rhs.saturatedFatGrams),
            sugarGrams: add(lhs.sugarGrams, rhs.sugarGrams),
            fibreGrams: add(lhs.fibreGrams, rhs.fibreGrams),
            sodiumMilligrams: add(lhs.sodiumMilligrams, rhs.sodiumMilligrams)
        )
    }

    /// A product with no energy and no macros carries no usable information —
    /// the food database has plenty of these part-filled entries, and they are
    /// worth hiding rather than logging as a zero-calorie food.
    var isEmpty: Bool {
        energyKilocalories <= 0 && proteinGrams <= 0 && carbohydrateGrams <= 0 && fatGrams <= 0
    }

    /// Energy implied by the macros, used to sanity-check a label.
    var energyFromMacros: Double {
        proteinGrams * 4 + carbohydrateGrams * 4 + fatGrams * 9
    }
}

/// One way of measuring out a food: the packet's own serving, or a plain 100 g.
nonisolated struct FoodPortion: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// What one of these weighs, which is what makes portions comparable.
    var grams: Double

    init(id: UUID = UUID(), name: String, grams: Double) {
        self.id = id
        self.name = name
        self.grams = grams
    }
}

/// Where a food's numbers came from, so the app can be honest about it.
nonisolated enum FoodSource: String, Codable, Sendable {
    /// The Open Food Facts database — crowd-sourced, so worth attributing.
    case openFoodFacts
    /// Typed in by the athlete for something with no barcode.
    case custom
}

/// A food, with its facts and the ways it can be portioned.
///
/// Held whole inside each diary entry rather than referenced, so correcting a
/// food later never silently rewrites what a past day recorded.
nonisolated struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var brand: String?
    var barcode: String?
    /// Facts per 100 g, or per 100 ml when `isLiquid`.
    var per100: NutritionFacts
    var portions: [FoodPortion] = []
    /// Drinks are measured in millilitres; the food database publishes their
    /// facts per 100 ml, so the arithmetic is identical and only the label differs.
    var isLiquid: Bool = false
    var imageURL: URL?
    var source: FoodSource = .custom

    /// `g` or `ml`, whichever this food is sensibly measured in.
    var measureUnit: String { isLiquid ? "ml" : "g" }

    /// Brand first when there is one, since that is how a packet is recognised.
    var subtitle: String? {
        let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let brand, !brand.isEmpty else { return nil }
        return brand
    }

    /// Every portion offered in the picker, always including a plain measure so
    /// a food with no serving on the packet can still be logged.
    var selectablePortions: [FoodPortion] {
        var all = portions
        if !all.contains(where: { $0.grams == 100 }) {
            all.append(FoodPortion(name: "100 \(measureUnit)", grams: 100))
        }
        return all
    }

    /// What the picker should open on: the packet's own serving when it has
    /// one, because that is the portion most people actually eat.
    var defaultPortion: FoodPortion {
        selectablePortions.first { $0.grams != 100 } ?? selectablePortions[0]
    }
}
