import Foundation
import HealthKit
import SwiftUI

/// Every activity Trekka can record, plan or log on the phone.
///
/// The four original cases keep their original raw values — `Trail Run`,
/// `Ride`, `Hike`, `Strength` — because those strings are encoded into every
/// workout and route already saved on the device. Renaming one would orphan
/// that history, so new cases take camelCase raw values instead and the
/// display name lives in `title`.
nonisolated enum RouteActivityType: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    // Run. `run` is the original trail-run case.
    case run = "Trail Run"
    case roadRun, ultraRun, track, treadmill, virtualRun

    // Ride. `ride` is the original road-ride case.
    case ride = "Ride"
    case gravelRide, mountainBike, bikepacking, eBike, commute, indoorRide, handCycling

    // Hike & walk.
    case hike = "Hike"
    case walk, ruck, backpacking, mountaineering

    // Climb.
    case rockClimb, boulder, indoorClimb, viaFerrata

    // Snow.
    case backcountrySki, alpineSki, snowboard, splitboard, nordicSki, snowshoe, iceSkate

    // Water.
    case openWaterSwim, poolSwim, kayak, paddleboard, surf, sail

    // Gym & studio. `strength` is the original case.
    case strength = "Strength"
    case hiit, yoga, pilates, cardio, elliptical, stairStepper, row
    case jumpRope, stretching, barre, taiChi, coreTraining, danceFitness
    case boxing, kickboxing, martialArts, climbStairs

    // Sports.
    case soccer, basketball, tennis, pickleball, golf, discGolf
    case volleyball, badminton, tableTennis, squash, racquetball
    case baseball, softball, americanFootball, hockey, rugby, cricket, lacrosse, bowling

    // Everything else.
    case skateboard, horseback, hunt, fish
    case lawnMowing, yardWork, snowShoveling, other

    var id: String { rawValue }

    // MARK: - Presentation

    var title: String {
        switch self {
        case .run: "Trail Run"
        case .roadRun: "Road Run"
        case .ultraRun: "Ultra Run"
        case .track: "Track Run"
        case .treadmill: "Treadmill"
        case .virtualRun: "Virtual Run"
        case .ride: "Road Ride"
        case .gravelRide: "Gravel Ride"
        case .mountainBike: "Mountain Bike"
        case .bikepacking: "Bikepacking"
        case .eBike: "E-Bike"
        case .commute: "Commute"
        case .indoorRide: "Indoor Ride"
        case .handCycling: "Hand Cycling"
        case .hike: "Hike"
        case .walk: "Walk"
        case .ruck: "Ruck"
        case .backpacking: "Backpacking"
        case .mountaineering: "Mountaineering"
        case .rockClimb: "Rock Climb"
        case .boulder: "Bouldering"
        case .indoorClimb: "Indoor Climb"
        case .viaFerrata: "Via Ferrata"
        case .backcountrySki: "Backcountry Ski"
        case .alpineSki: "Alpine Ski"
        case .snowboard: "Snowboard"
        case .splitboard: "Splitboard"
        case .nordicSki: "Nordic Ski"
        case .snowshoe: "Snowshoe"
        case .iceSkate: "Ice Skate"
        case .openWaterSwim: "Open Water Swim"
        case .poolSwim: "Pool Swim"
        case .kayak: "Kayak"
        case .paddleboard: "Paddleboard"
        case .surf: "Surf"
        case .sail: "Sail"
        case .strength: "Strength"
        case .hiit: "HIIT"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .cardio: "Cardio"
        case .elliptical: "Elliptical"
        case .stairStepper: "Stair Stepper"
        case .row: "Indoor Row"
        case .jumpRope: "Jump Rope"
        case .stretching: "Stretching"
        case .barre: "Barre"
        case .taiChi: "Tai Chi"
        case .coreTraining: "Core Training"
        case .danceFitness: "Dance Fitness"
        case .boxing: "Boxing"
        case .kickboxing: "Kickboxing"
        case .martialArts: "Martial Arts"
        case .climbStairs: "Stair Climbing"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .pickleball: "Pickleball"
        case .golf: "Golf"
        case .discGolf: "Disc Golf"
        case .volleyball: "Volleyball"
        case .badminton: "Badminton"
        case .tableTennis: "Table Tennis"
        case .squash: "Squash"
        case .racquetball: "Racquetball"
        case .baseball: "Baseball"
        case .softball: "Softball"
        case .americanFootball: "Football"
        case .hockey: "Hockey"
        case .rugby: "Rugby"
        case .cricket: "Cricket"
        case .lacrosse: "Lacrosse"
        case .bowling: "Bowling"
        case .skateboard: "Skateboard"
        case .horseback: "Horse Riding"
        case .hunt: "Hunt"
        case .fish: "Fish"
        case .lawnMowing: "Lawn Mowing"
        case .yardWork: "Yard Work"
        case .snowShoveling: "Snow Shoveling"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .roadRun: "figure.run.circle"
        case .ultraRun: "figure.run.square.stack"
        case .track: "figure.track.and.field"
        case .treadmill: "figure.run.treadmill"
        case .virtualRun: "display"
        case .ride, .gravelRide: "bicycle"
        case .mountainBike: "bicycle.circle"
        case .bikepacking: "tent.2.fill"
        case .eBike: "bolt.circle.fill"
        case .commute: "road.lanes"
        case .indoorRide: "figure.indoor.cycle"
        case .handCycling: "figure.hand.cycling"
        case .hike: "figure.hiking"
        case .walk: "figure.walk"
        case .ruck: "backpack.fill"
        case .backpacking: "tent.fill"
        case .mountaineering: "mountain.2.fill"
        case .rockClimb: "figure.climbing"
        case .boulder: "cube.fill"
        case .indoorClimb: "building.2.fill"
        case .viaFerrata: "link"
        case .backcountrySki, .nordicSki: "figure.skiing.crosscountry"
        case .alpineSki: "figure.skiing.downhill"
        case .snowboard: "figure.snowboarding"
        case .splitboard: "square.split.2x1.fill"
        case .snowshoe: "snowflake"
        case .iceSkate: "figure.ice.skating"
        case .openWaterSwim: "figure.open.water.swim"
        case .poolSwim: "figure.pool.swim"
        case .kayak: "figure.outdoor.rowing"
        case .paddleboard: "water.waves"
        case .surf: "figure.surfing"
        case .sail: "figure.sailing"
        case .strength: "dumbbell.fill"
        case .hiit: "bolt.heart.fill"
        case .yoga: "figure.mind.and.body"
        case .pilates: "figure.pilates"
        case .cardio: "figure.mixed.cardio"
        case .elliptical: "figure.elliptical"
        case .stairStepper: "figure.stair.stepper"
        case .row: "figure.indoor.rowing"
        case .jumpRope: "figure.jumprope"
        case .stretching: "figure.flexibility"
        case .barre: "figure.barre"
        case .taiChi: "figure.taichi"
        case .coreTraining: "figure.core.training"
        case .danceFitness: "figure.dance"
        case .boxing: "figure.boxing"
        case .kickboxing: "figure.kickboxing"
        case .martialArts: "figure.martial.arts"
        case .climbStairs: "figure.stairs"
        case .soccer: "figure.outdoor.soccer"
        case .basketball: "figure.basketball"
        case .tennis: "figure.tennis"
        case .pickleball: "figure.pickleball"
        case .golf: "figure.golf"
        case .discGolf: "figure.disc.sports"
        case .volleyball: "figure.volleyball"
        case .badminton: "figure.badminton"
        case .tableTennis: "figure.table.tennis"
        case .squash: "figure.squash"
        case .racquetball: "figure.racquetball"
        case .baseball: "figure.baseball"
        case .softball: "figure.softball"
        case .americanFootball: "figure.american.football"
        case .hockey: "figure.hockey"
        case .rugby: "figure.rugby"
        case .cricket: "figure.cricket"
        case .lacrosse: "figure.lacrosse"
        case .bowling: "figure.bowling"
        case .skateboard: "figure.skateboarding"
        case .horseback: "figure.equestrian.sports"
        case .hunt: "figure.hunting"
        case .fish: "figure.fishing"
        case .lawnMowing: "leaf.fill"
        case .yardWork: "hammer.fill"
        case .snowShoveling: "snowflake.circle.fill"
        case .other: "figure.mixed.cardio"
        }
    }

    /// The group this activity is filed under, shared with the watch's own
    /// browser so both sides organise the list the same way.
    var family: WatchSportFamily {
        switch self {
        case .run, .roadRun, .ultraRun, .track, .treadmill, .virtualRun: .run
        case .ride, .gravelRide, .mountainBike, .bikepacking, .eBike, .commute,
             .indoorRide, .handCycling: .ride
        case .hike, .walk, .ruck, .backpacking, .mountaineering: .hike
        case .rockClimb, .boulder, .indoorClimb, .viaFerrata: .climb
        case .backcountrySki, .alpineSki, .snowboard, .splitboard, .nordicSki,
             .snowshoe, .iceSkate: .snow
        case .openWaterSwim, .poolSwim, .kayak, .paddleboard, .surf, .sail: .water
        case .strength, .hiit, .yoga, .pilates, .cardio, .elliptical, .stairStepper,
             .row, .jumpRope, .stretching, .barre, .taiChi, .coreTraining,
             .danceFitness, .boxing, .kickboxing, .martialArts, .climbStairs: .gym
        case .soccer, .basketball, .tennis, .pickleball, .golf, .discGolf,
             .volleyball, .badminton, .tableTennis, .squash, .racquetball,
             .baseball, .softball, .americanFootball, .hockey, .rugby, .cricket,
             .lacrosse, .bowling: .sport
        case .skateboard, .horseback, .hunt, .fish, .lawnMowing, .yardWork,
             .snowShoveling, .other: .other
        }
    }

    var tint: Color { family.tint }

    // MARK: - Behaviour

    var isIndoor: Bool {
        switch self {
        case .treadmill, .virtualRun, .indoorRide, .handCycling, .boulder, .indoorClimb,
             .poolSwim, .strength, .hiit, .yoga, .pilates, .cardio, .elliptical,
             .stairStepper, .row, .jumpRope, .stretching, .barre, .taiChi,
             .coreTraining, .danceFitness, .boxing, .kickboxing, .martialArts,
             .climbStairs, .basketball, .volleyball, .badminton, .tableTennis,
             .squash, .racquetball, .bowling:
            true
        default:
            false
        }
    }

    var usesGPS: Bool { !isIndoor }

    /// Swimming, where a map and a course line are of no use.
    var isSwim: Bool { self == .openWaterSwim || self == .poolSwim }

    /// A session with no meaningful travel, logged by time rather than ground.
    var isStationary: Bool { estimatedSpeed == 0 }

    /// Whether a planned route can be built for this activity.
    var supportsRoutes: Bool { usesGPS && !isSwim && !isStationary }

    /// Runners, walkers and swimmers think in pace; everyone else in speed.
    var usesPace: Bool {
        switch self {
        case .nordicSki, .snowshoe, .row: true
        default:
            switch family {
            case .run, .hike, .water: true
            case .ride, .climb, .snow, .gym, .sport, .other: false
            }
        }
    }

    var usesElevation: Bool {
        switch family {
        case .run, .ride, .hike, .climb, .snow, .other: !isIndoor
        case .water, .gym, .sport: false
        }
    }

    /// A gym session logged with sets rather than distance.
    var usesStrengthSets: Bool {
        self == .strength || self == .hiit || self == .coreTraining
    }

    /// Rough moving speed in metres per second, used for time estimates.
    /// Zero means the activity covers no meaningful ground.
    var estimatedSpeed: Double {
        switch self {
        case .run: 2.9
        case .roadRun, .treadmill, .virtualRun: 3.3
        case .ultraRun: 2.4
        case .track: 3.6
        case .ride, .indoorRide: 7.5
        case .gravelRide: 6.2
        case .mountainBike: 4.4
        case .bikepacking: 4.2
        case .eBike: 6.5
        case .commute: 5.0
        case .handCycling: 4.0
        case .hike: 1.3
        case .walk: 1.4
        case .ruck: 1.2
        case .backpacking: 1.1
        case .mountaineering: 0.8
        case .rockClimb: 0.2
        case .viaFerrata: 0.4
        case .backcountrySki: 1.8
        case .splitboard: 1.7
        case .alpineSki, .snowboard: 8.0
        case .nordicSki: 3.4
        case .snowshoe: 1.0
        case .iceSkate: 4.5
        case .openWaterSwim, .poolSwim: 0.9
        case .kayak: 1.8
        case .paddleboard: 1.4
        case .surf: 0.6
        case .sail: 3.5
        case .golf, .discGolf: 1.0
        case .skateboard: 3.5
        case .horseback: 2.5
        case .hunt: 0.7
        case .fish: 0.3
        case .lawnMowing, .yardWork: 0.5
        case .snowShoveling: 0.3
        case .boulder, .indoorClimb, .strength, .hiit, .yoga, .pilates, .cardio,
             .elliptical, .stairStepper, .row, .jumpRope, .stretching, .barre,
             .taiChi, .coreTraining, .danceFitness, .boxing, .kickboxing,
             .martialArts, .climbStairs, .soccer, .basketball, .tennis,
             .pickleball, .volleyball, .badminton, .tableTennis, .squash,
             .racquetball, .baseball, .softball, .americanFootball, .hockey,
             .rugby, .cricket, .lacrosse, .bowling, .other: 0
        }
    }

    // MARK: - Grouping

    /// A family and the activities inside it, for a sectioned list.
    nonisolated struct Group: Identifiable, Sendable {
        var family: WatchSportFamily
        var activities: [RouteActivityType]
        var id: String { family.rawValue }
    }

    /// Activities a route can be planned for.
    static var routable: [RouteActivityType] {
        allCases.filter(\.supportsRoutes)
    }

    /// Every activity grouped by family, in the order the families are listed.
    static var grouped: [Group] { groups(of: allCases) }

    /// Only the activities a route can be planned for, grouped by family.
    static var routableGrouped: [Group] { groups(of: routable) }

    /// Buckets a set of activities by family, dropping families with none.
    static func groups(of activities: [RouteActivityType]) -> [Group] {
        WatchSportFamily.allCases.compactMap { family in
            let members = activities.filter { $0.family == family }
            return members.isEmpty ? nil : Group(family: family, activities: members)
        }
    }

    /// Every activity in alphabetical order, for an A–Z browser.
    static var alphabetical: [RouteActivityType] {
        allCases.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The watch profile this activity records as, matched by name.
    ///
    /// The two catalogues share case names wherever both sides know the sport,
    /// so the bridge is a lookup rather than a switch that has to be kept in
    /// step by hand. Anything the watch has no profile for falls back to the
    /// closest sibling in the same family.
    var watchProfile: WatchSportProfile {
        if let exact = WatchSportProfile(rawValue: watchProfileName) { return exact }
        return switch family {
        case .run: .trailRun
        case .ride: .ride
        case .hike: .hike
        case .climb: .rockClimb
        case .snow: .alpineSki
        case .water: .kayak
        case .gym: .strength
        case .sport: .soccer
        case .other: .hike
        }
    }

    /// The watch's name for this activity. The four legacy cases carry display
    /// strings as raw values, so they are translated explicitly.
    private var watchProfileName: String {
        switch self {
        case .run: "trailRun"
        case .ride: "ride"
        case .hike: "hike"
        case .strength: "strength"
        default: rawValue
        }
    }
}

// MARK: - Apple Health

nonisolated extension RouteActivityType {
    /// How Apple Health files this activity.
    var healthKitActivity: HKWorkoutActivityType {
        switch self {
        case .run, .roadRun, .ultraRun, .track, .treadmill, .virtualRun: .running
        case .ride, .gravelRide, .mountainBike, .bikepacking, .eBike, .commute,
             .indoorRide: .cycling
        case .handCycling: .handCycling
        case .hike, .ruck, .backpacking, .mountaineering: .hiking
        case .walk: .walking
        case .rockClimb, .boulder, .indoorClimb, .viaFerrata: .climbing
        case .backcountrySki, .nordicSki: .crossCountrySkiing
        case .alpineSki: .downhillSkiing
        case .snowboard, .splitboard: .snowboarding
        case .snowshoe: .snowSports
        case .iceSkate: .skatingSports
        case .openWaterSwim, .poolSwim: .swimming
        case .kayak, .paddleboard: .paddleSports
        case .surf: .surfingSports
        case .sail: .sailing
        case .strength: .traditionalStrengthTraining
        case .hiit: .highIntensityIntervalTraining
        case .yoga: .yoga
        case .pilates: .pilates
        case .cardio: .mixedCardio
        case .elliptical: .elliptical
        case .stairStepper: .stairClimbing
        case .row: .rowing
        case .jumpRope: .jumpRope
        case .stretching: .flexibility
        case .barre: .barre
        case .taiChi: .taiChi
        case .coreTraining: .coreTraining
        case .danceFitness: .cardioDance
        case .boxing: .boxing
        case .kickboxing: .kickboxing
        case .martialArts: .martialArts
        case .climbStairs: .stairs
        case .soccer: .soccer
        case .basketball: .basketball
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .golf: .golf
        case .discGolf: .discSports
        case .volleyball: .volleyball
        case .badminton: .badminton
        case .tableTennis: .tableTennis
        case .squash: .squash
        case .racquetball: .racquetball
        case .baseball: .baseball
        case .softball: .softball
        case .americanFootball: .americanFootball
        case .hockey: .hockey
        case .rugby: .rugby
        case .cricket: .cricket
        case .lacrosse: .lacrosse
        case .bowling: .bowling
        case .skateboard: .skatingSports
        case .horseback: .equestrianSports
        case .hunt: .hunting
        case .fish: .fishing
        // Health has no yard-work type, so these file as Other rather than
        // borrowing a sport that would misreport the effort.
        case .lawnMowing, .yardWork, .snowShoveling, .other: .other
        }
    }

    /// The distance type Health records this activity against. Activities that
    /// travel nowhere fall back to step count, because writing against a
    /// distance type that is never populated would report zero forever.
    var distanceIdentifier: HKQuantityTypeIdentifier {
        if isStationary { return .stepCount }
        switch self {
        case .ride, .gravelRide, .mountainBike, .bikepacking, .eBike, .commute,
             .indoorRide, .handCycling:
            return .distanceCycling
        case .openWaterSwim, .poolSwim:
            return .distanceSwimming
        case .alpineSki, .snowboard, .backcountrySki, .splitboard, .nordicSki:
            return .distanceDownhillSnowSports
        default:
            return .distanceWalkingRunning
        }
    }

    /// The closest activity for a workout Health recorded elsewhere.
    static func from(healthKit type: HKWorkoutActivityType) -> RouteActivityType {
        switch type {
        case .running: .run
        case .cycling: .ride
        case .handCycling: .handCycling
        case .hiking: .hike
        case .walking: .walk
        case .climbing: .rockClimb
        case .crossCountrySkiing: .nordicSki
        case .downhillSkiing: .alpineSki
        case .snowboarding: .snowboard
        case .snowSports: .snowshoe
        case .skatingSports: .iceSkate
        case .swimming: .openWaterSwim
        case .paddleSports: .kayak
        case .surfingSports: .surf
        case .sailing: .sail
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .coreTraining: .coreTraining
        case .highIntensityIntervalTraining: .hiit
        case .yoga: .yoga
        case .pilates: .pilates
        case .mixedCardio, .crossTraining: .cardio
        case .elliptical: .elliptical
        case .stairClimbing: .stairStepper
        case .stairs: .climbStairs
        case .rowing: .row
        case .jumpRope: .jumpRope
        case .flexibility, .preparationAndRecovery: .stretching
        case .barre: .barre
        case .taiChi: .taiChi
        case .cardioDance, .socialDance, .dance: .danceFitness
        case .boxing: .boxing
        case .kickboxing: .kickboxing
        case .martialArts: .martialArts
        case .soccer: .soccer
        case .basketball: .basketball
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .golf: .golf
        case .discSports: .discGolf
        case .volleyball: .volleyball
        case .badminton: .badminton
        case .tableTennis: .tableTennis
        case .squash: .squash
        case .racquetball: .racquetball
        case .baseball: .baseball
        case .softball: .softball
        case .americanFootball: .americanFootball
        case .hockey: .hockey
        case .rugby: .rugby
        case .cricket: .cricket
        case .lacrosse: .lacrosse
        case .bowling: .bowling
        case .equestrianSports: .horseback
        case .hunting: .hunt
        case .fishing: .fish
        default: .other
        }
    }
}
