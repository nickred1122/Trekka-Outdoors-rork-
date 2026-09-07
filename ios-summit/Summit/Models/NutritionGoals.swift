import Foundation

/// A macro split, held as percentages of the day's energy.
///
/// Percentages rather than grams because they always add up: change the calorie
/// target and the grams follow, instead of leaving three numbers that quietly
/// no longer match the total they are supposed to make.
nonisolated enum MacroSplit: String, CaseIterable, Codable, Sendable, Identifiable {
    case balanced
    case endurance
    case highProtein
    case lowCarb
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .endurance: "Endurance"
        case .highProtein: "High protein"
        case .lowCarb: "Low carb"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "An even split for general training"
        case .endurance: "Carb-led, for long days on the hill"
        case .highProtein: "Protein-led, for strength blocks"
        case .lowCarb: "Fat-led, fewer carbohydrates"
        case .custom: "Your own split"
        }
    }

    /// Protein, carbohydrate and fat as percentages of energy.
    var percentages: (protein: Double, carbohydrate: Double, fat: Double)? {
        switch self {
        case .balanced: (25, 45, 30)
        case .endurance: (20, 55, 25)
        case .highProtein: (35, 35, 30)
        case .lowCarb: (30, 20, 50)
        case .custom: nil
        }
    }
}

/// The athlete's daily targets.
///
/// Energy is chosen, not computed: this app does not know a person's job, their
/// build or their week, and a confidently wrong basal estimate is worse than
/// asking. What it does know is what they burned today, which is why training
/// can optionally be added on top.
nonisolated struct NutritionGoals: Codable, Hashable, Sendable {
    /// The base daily energy target, before any training is added.
    var energyKilocalories: Double = 2_200
    var proteinPercent: Double = 25
    var carbohydratePercent: Double = 45
    var fatPercent: Double = 30
    /// When set, the energy actually burned today is added to the target, so a
    /// long day on the hill raises what there is to eat. Off by default: eating
    /// back training energy is a real choice, not a default anyone should be
    /// opted into.
    var addsActiveEnergy: Bool = false

    static let `default` = NutritionGoals()

    /// Protein carries 4 kcal per gram, carbohydrate 4, fat 9 — the Atwater
    /// factors every food label in the world is built on.
    static let energyPerProteinGram: Double = 4
    static let energyPerCarbohydrateGram: Double = 4
    static let energyPerFatGram: Double = 9

    /// The day's energy target, including training when that is switched on.
    func energyTarget(activeEnergy: Double) -> Double {
        guard addsActiveEnergy, activeEnergy > 0 else { return energyKilocalories }
        return energyKilocalories + activeEnergy
    }

    func proteinTarget(activeEnergy: Double) -> Double {
        energyTarget(activeEnergy: activeEnergy) * proteinPercent / 100 / Self.energyPerProteinGram
    }

    func carbohydrateTarget(activeEnergy: Double) -> Double {
        energyTarget(activeEnergy: activeEnergy) * carbohydratePercent / 100 / Self.energyPerCarbohydrateGram
    }

    func fatTarget(activeEnergy: Double) -> Double {
        energyTarget(activeEnergy: activeEnergy) * fatPercent / 100 / Self.energyPerFatGram
    }

    /// Which preset these percentages match, so the goals screen can show the
    /// chosen one rather than always reading as custom.
    var split: MacroSplit {
        for split in MacroSplit.allCases {
            guard let percentages = split.percentages else { continue }
            if abs(percentages.protein - proteinPercent) < 0.5,
               abs(percentages.carbohydrate - carbohydratePercent) < 0.5,
               abs(percentages.fat - fatPercent) < 0.5 {
                return split
            }
        }
        return .custom
    }

    /// Applies a preset split, leaving the energy target alone.
    mutating func apply(_ split: MacroSplit) {
        guard let percentages = split.percentages else { return }
        proteinPercent = percentages.protein
        carbohydratePercent = percentages.carbohydrate
        fatPercent = percentages.fat
    }

    /// Moves one macro and takes the difference off the other two in proportion,
    /// so the three always still describe a whole day.
    mutating func setProteinPercent(_ value: Double) {
        rebalance(protein: value, carbohydrate: nil, fat: nil)
    }

    mutating func setCarbohydratePercent(_ value: Double) {
        rebalance(protein: nil, carbohydrate: value, fat: nil)
    }

    mutating func setFatPercent(_ value: Double) {
        rebalance(protein: nil, carbohydrate: nil, fat: value)
    }

    private mutating func rebalance(protein: Double?, carbohydrate: Double?, fat: Double?) {
        let clamped = min(max(protein ?? carbohydrate ?? fat ?? 0, 5), 90)
        let remainder = 100 - clamped

        /// Splits what is left between the two macros that did not move, keeping
        /// their existing ratio. If both were at zero they simply halve it.
        func share(_ first: Double, _ second: Double) -> (Double, Double) {
            let total = first + second
            guard total > 0 else { return (remainder / 2, remainder / 2) }
            return (remainder * first / total, remainder * second / total)
        }

        if protein != nil {
            proteinPercent = clamped
            (carbohydratePercent, fatPercent) = share(carbohydratePercent, fatPercent)
        } else if carbohydrate != nil {
            carbohydratePercent = clamped
            (proteinPercent, fatPercent) = share(proteinPercent, fatPercent)
        } else {
            fatPercent = clamped
            (proteinPercent, carbohydratePercent) = share(proteinPercent, carbohydratePercent)
        }
    }
}
