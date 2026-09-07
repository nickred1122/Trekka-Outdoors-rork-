import Foundation

/// One set, as it was actually lifted.
///
/// Weight is always stored in kilograms whatever the athlete dials in, so a
/// session logged in pounds and one logged in kilos can still be added together
/// into a single volume figure.
///
/// Duplicated verbatim from `SummitWatch/Models/StrengthSet.swift`; the watch is
/// a separate binary, so the two copies must stay identical.
nonisolated struct StrengthSet: Identifiable, Sendable, Equatable, Hashable, Codable {
    var id: UUID = UUID()
    var exercise: String
    var reps: Int
    var weightKilograms: Double
    var loggedAt: Date = .now

    /// Reps times load — the number that actually tracks progress from week to
    /// week, since more reps at a lighter weight can beat fewer at a heavier one.
    var volume: Double { Double(reps) * weightKilograms }

    var isBodyweight: Bool { weightKilograms <= 0 }
}

/// The part of the body an exercise trains, used to group the picker.
nonisolated enum GymMuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .legs: "Legs"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .legs: "figure.squat"
        case .shoulders: "figure.arms.open"
        case .arms: "dumbbell.fill"
        case .core: "figure.core.training"
        }
    }
}

/// A movement that can be logged.
nonisolated struct GymExercise: Identifiable, Hashable, Sendable {
    let name: String
    let group: GymMuscleGroup
    /// Bodyweight movements start at zero load rather than at a bar weight, so
    /// the dial does not have to be wound back down every time.
    let isBodyweightByDefault: Bool

    var id: String { name }

    init(_ name: String, _ group: GymMuscleGroup, bodyweight: Bool = false) {
        self.name = name
        self.group = group
        self.isBodyweightByDefault = bodyweight
    }
}

/// The movements offered for logging.
///
/// The same curated list as on the wrist, so a set logged on the watch reads
/// back here under a name the phone recognises.
nonisolated enum GymExerciseLibrary {
    static let all: [GymExercise] = [
        // Chest
        GymExercise("Bench Press", .chest),
        GymExercise("Incline Bench Press", .chest),
        GymExercise("Dumbbell Press", .chest),
        GymExercise("Incline Dumbbell Press", .chest),
        GymExercise("Chest Fly", .chest),
        GymExercise("Cable Crossover", .chest),
        GymExercise("Press-Up", .chest, bodyweight: true),
        GymExercise("Dip", .chest, bodyweight: true),

        // Back
        GymExercise("Deadlift", .back),
        GymExercise("Romanian Deadlift", .back),
        GymExercise("Barbell Row", .back),
        GymExercise("Dumbbell Row", .back),
        GymExercise("Lat Pulldown", .back),
        GymExercise("Seated Cable Row", .back),
        GymExercise("Pull-Up", .back, bodyweight: true),
        GymExercise("Chin-Up", .back, bodyweight: true),
        GymExercise("Face Pull", .back),
        GymExercise("Shrug", .back),

        // Legs
        GymExercise("Back Squat", .legs),
        GymExercise("Front Squat", .legs),
        GymExercise("Leg Press", .legs),
        GymExercise("Lunge", .legs),
        GymExercise("Bulgarian Split Squat", .legs),
        GymExercise("Leg Extension", .legs),
        GymExercise("Leg Curl", .legs),
        GymExercise("Hip Thrust", .legs),
        GymExercise("Calf Raise", .legs),
        GymExercise("Step-Up", .legs),
        GymExercise("Goblet Squat", .legs),

        // Shoulders
        GymExercise("Overhead Press", .shoulders),
        GymExercise("Dumbbell Shoulder Press", .shoulders),
        GymExercise("Lateral Raise", .shoulders),
        GymExercise("Front Raise", .shoulders),
        GymExercise("Rear Delt Fly", .shoulders),
        GymExercise("Upright Row", .shoulders),
        GymExercise("Arnold Press", .shoulders),

        // Arms
        GymExercise("Barbell Curl", .arms),
        GymExercise("Dumbbell Curl", .arms),
        GymExercise("Hammer Curl", .arms),
        GymExercise("Preacher Curl", .arms),
        GymExercise("Triceps Pushdown", .arms),
        GymExercise("Skull Crusher", .arms),
        GymExercise("Overhead Triceps Extension", .arms),
        GymExercise("Close-Grip Bench Press", .arms),

        // Core
        GymExercise("Plank", .core, bodyweight: true),
        GymExercise("Hanging Leg Raise", .core, bodyweight: true),
        GymExercise("Cable Crunch", .core),
        GymExercise("Russian Twist", .core),
        GymExercise("Ab Wheel", .core, bodyweight: true),
        GymExercise("Back Extension", .core, bodyweight: true),
    ]

    static func exercises(in group: GymMuscleGroup) -> [GymExercise] {
        all.filter { $0.group == group }
    }

    static func exercise(named name: String) -> GymExercise? {
        all.first { $0.name == name }
    }
}

/// Everything logged in one gym session, grouped for display.
nonisolated struct StrengthSession: Sendable, Equatable {
    var sets: [StrengthSet] = []

    var isEmpty: Bool { sets.isEmpty }

    var totalVolume: Double { sets.reduce(0) { $0 + $1.volume } }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }

    /// Exercises in the order they were first performed, each with its sets.
    var byExercise: [(exercise: String, sets: [StrengthSet])] {
        var order: [String] = []
        var grouped: [String: [StrengthSet]] = [:]
        for set in sets {
            if grouped[set.exercise] == nil { order.append(set.exercise) }
            grouped[set.exercise, default: []].append(set)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    func sets(for exercise: String) -> [StrengthSet] {
        sets.filter { $0.exercise == exercise }
    }

    /// The last set recorded for a movement, which is what the dial should open
    /// on next time rather than making the athlete wind up from zero.
    func lastSet(for exercise: String) -> StrengthSet? {
        sets.last { $0.exercise == exercise }
    }

    /// Heaviest set of a movement this session, for the working-weight readout.
    func topSet(for exercise: String) -> StrengthSet? {
        sets.filter { $0.exercise == exercise }.max { $0.weightKilograms < $1.weightKilograms }
    }
}
