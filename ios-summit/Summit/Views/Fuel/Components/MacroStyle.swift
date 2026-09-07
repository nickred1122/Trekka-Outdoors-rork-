import SwiftUI

/// The three macronutrients, given a colour and a name each so the ring, the
/// bars and the food detail all describe them the same way.
nonisolated enum Macro: String, CaseIterable, Identifiable, Sendable {
    case protein
    case carbohydrate
    case fat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: "Protein"
        case .carbohydrate: "Carbs"
        case .fat: "Fat"
        }
    }

    /// Kept clear of Trekka's orange, which belongs to energy alone — so a
    /// glance at the card never confuses a macro with the calorie total.
    var color: Color {
        switch self {
        case .protein: Color(red: 0.11, green: 0.78, blue: 0.71)
        case .carbohydrate: Theme.highlight
        case .fat: Color(red: 0.42, green: 0.58, blue: 0.99)
        }
    }

    func grams(in facts: NutritionFacts) -> Double {
        switch self {
        case .protein: facts.proteinGrams
        case .carbohydrate: facts.carbohydrateGrams
        case .fat: facts.fatGrams
        }
    }

    func target(in goals: NutritionGoals, activeEnergy: Double) -> Double {
        switch self {
        case .protein: goals.proteinTarget(activeEnergy: activeEnergy)
        case .carbohydrate: goals.carbohydrateTarget(activeEnergy: activeEnergy)
        case .fat: goals.fatTarget(activeEnergy: activeEnergy)
        }
    }
}

/// One macro's progress towards its target for the day.
struct MacroBar: View {
    let macro: Macro
    let grams: Double
    let target: Double

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, grams / target)
    }

    private var isOver: Bool { target > 0 && grams > target }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(macro.title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))

                Spacer(minLength: 0)

                Text("\(Int(grams.rounded()))")
                    .font(.metric(13))
                    .foregroundStyle(Theme.textPrimary)
                if target > 0 {
                    Text("/ \(Int(target.rounded())) g")
                        .font(.system(.caption2, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                } else {
                    Text("g")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.08))

                    Capsule()
                        .fill(isOver ? Theme.danger : macro.color)
                        .frame(width: max(fraction > 0 ? 4 : 0, geometry.size.width * fraction))
                }
            }
            .frame(height: 6)
            .animation(.snappy(duration: 0.35), value: fraction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(macro.title) \(Int(grams.rounded())) of \(Int(target.rounded())) grams")
    }
}
