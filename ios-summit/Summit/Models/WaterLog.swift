import Foundation

/// A drink logged against a day.
///
/// Water is kept apart from the food diary rather than logged as a zero-calorie
/// food. It carries no energy and no macros, so putting it through the diary
/// would file rows against meals that contribute nothing to any total — and it
/// is the one thing people want to log in one tap, repeatedly, all day.
nonisolated struct WaterEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var millilitres: Double
    var loggedAt: Date = .now

    init(id: UUID = UUID(), millilitres: Double, loggedAt: Date = .now) {
        self.id = id
        self.millilitres = millilitres
        self.loggedAt = loggedAt
    }
}

/// The sizes offered for one tap.
///
/// Round metric volumes, shown in the athlete's own units at the point of
/// display. Nothing here is a guess about a vessel: a glass and a bottle are
/// conventions, and the athlete can correct the target rather than the drink.
nonisolated enum WaterMeasure: String, CaseIterable, Codable, Sendable, Identifiable {
    case glass
    case bottle
    case litre

    var id: String { rawValue }

    var millilitres: Double {
        switch self {
        case .glass: 250
        case .bottle: 500
        case .litre: 1_000
        }
    }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .bottle: "Bottle"
        case .litre: "Litre"
        }
    }

    var symbol: String {
        switch self {
        case .glass: "cup.and.saucer.fill"
        case .bottle: "waterbottle.fill"
        case .litre: "drop.fill"
        }
    }
}

/// One day's drinking.
nonisolated struct DayWater: Sendable, Equatable {
    var entries: [WaterEntry] = []

    var millilitres: Double {
        entries.reduce(0) { $0 + $1.millilitres }
    }

    var isEmpty: Bool { entries.isEmpty }
}
