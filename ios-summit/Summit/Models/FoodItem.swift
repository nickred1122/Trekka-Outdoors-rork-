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

/// A household way of measuring a food out, for the many things that arrive
/// without a packet to read a serving off.
///
/// Volume measures are exact for liquids, where a millilitre weighs a gram.
/// For solids they are genuinely approximate — a tablespoon of honey and a
/// tablespoon of flour weigh very different amounts — so anything derived from
/// volume is marked as an estimate and says so in the picker rather than
/// pretending to a precision it does not have.
nonisolated enum PortionMeasure: String, Codable, CaseIterable, Sendable, Identifiable {
    case piece, slice, tablespoon, teaspoon, cup, handful, bowl, glass, can, bottle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .piece: "Piece"
        case .slice: "Slice"
        case .tablespoon: "Tablespoon"
        case .teaspoon: "Teaspoon"
        case .cup: "Cup"
        case .handful: "Handful"
        case .bowl: "Bowl"
        case .glass: "Glass"
        case .can: "Can"
        case .bottle: "Bottle"
        }
    }

    var shortTitle: String {
        switch self {
        case .tablespoon: "tbsp"
        case .teaspoon: "tsp"
        default: title.lowercased()
        }
    }

    /// Whether this measure only makes sense for something you pour.
    var isLiquidOnly: Bool {
        switch self {
        case .glass, .bottle: true
        default: false
        }
    }

    /// Whether this measure only makes sense for something you can count.
    var isSolidOnly: Bool {
        switch self {
        case .piece, .slice, .handful: true
        default: false
        }
    }

    /// A starting weight in grams, always editable by the athlete.
    ///
    /// Volumetric measures use the standard metric volume; countable ones have
    /// no honest default at all, so they start at a round number the athlete is
    /// expected to correct.
    var defaultGrams: Double {
        switch self {
        case .tablespoon: 15
        case .teaspoon: 5
        case .cup: 240
        case .glass: 250
        case .bowl: 300
        case .can: 330
        case .bottle: 500
        case .piece: 50
        case .slice: 30
        case .handful: 30
        }
    }

    /// True when the weight is inferred from volume or a rough convention
    /// rather than read off a packet.
    var isEstimate: Bool { true }
}

/// One way of measuring out a food: the packet's own serving, a plain 100 g,
/// or a household measure such as a tablespoon or a piece.
nonisolated struct FoodPortion: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// What one of these weighs, which is what makes portions comparable.
    var grams: Double
    /// Set when this portion came from a household measure rather than the
    /// packet, so the picker can mark it as approximate.
    var measure: PortionMeasure?

    /// Whether the weight is a convention rather than a figure off a label.
    var isEstimate: Bool { measure != nil }

    init(id: UUID = UUID(), name: String, grams: Double, measure: PortionMeasure? = nil) {
        self.id = id
        self.name = name
        self.grams = grams
        self.measure = measure
    }

    /// Decoded tolerantly so diary entries saved before household measures
    /// existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        grams = try container.decode(Double.self, forKey: .grams)
        measure = try container.decodeIfPresent(PortionMeasure.self, forKey: .measure)
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

    /// Household measures that suit this food, offered after the packet's own
    /// servings so a loose apple or a spoon of peanut butter can still be
    /// logged without weighing it.
    var householdPortions: [FoodPortion] {
        PortionMeasure.allCases
            .filter { isLiquid ? !$0.isSolidOnly : !$0.isLiquidOnly }
            .map { measure in
                FoodPortion(
                    // Seeded from the food and the measure so the same portion
                    // keeps its identity between reads, which a fresh UUID
                    // would break for anything selected by id.
                    id: StableID.portion(food: id, measure: measure.rawValue),
                    name: measure.title,
                    grams: measure.defaultGrams,
                    measure: measure
                )
            }
    }

    /// The portions read off the packet, plus a plain measure so a food with no
    /// serving listed can still be logged.
    var packetPortions: [FoodPortion] {
        var all = portions
        if !all.contains(where: { $0.grams == 100 }) {
            all.append(FoodPortion(name: "100 \(measureUnit)", grams: 100))
        }
        return all
    }

    /// Every portion offered in the picker: the packet's own first, because a
    /// figure off a label always beats a household convention.
    var selectablePortions: [FoodPortion] {
        packetPortions + householdPortions
    }

    /// What the picker should open on: the packet's own serving when it has
    /// one, because that is the portion most people actually eat. Never a
    /// household measure, which is only ever an estimate.
    var defaultPortion: FoodPortion {
        let packet = packetPortions
        return packet.first { $0.grams != 100 } ?? packet[0]
    }
}
