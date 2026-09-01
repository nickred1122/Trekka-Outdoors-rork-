import SwiftUI

/// The groups the activity list is organised into.
///
/// Order here is the order they appear on the wrist, so the outdoor families
/// this app is built for come before the gym and the ball courts.
nonisolated enum SportFamily: String, Codable, CaseIterable, Sendable, Identifiable {
    case run, ride, hike, climb, snow, water, gym, sport, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .ride: "Ride"
        case .hike: "Hike & Walk"
        case .climb: "Climb"
        case .snow: "Snow"
        case .water: "Water"
        case .gym: "Gym"
        case .sport: "Sports"
        case .other: "More"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "bicycle"
        case .hike: "figure.hiking"
        case .climb: "figure.climbing"
        case .snow: "snowflake"
        case .water: "water.waves"
        case .gym: "dumbbell.fill"
        case .sport: "figure.play"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// One line describing what is inside, shown under the family name.
    var summary: String {
        switch self {
        case .run: "Trail, road, track, treadmill"
        case .ride: "Road, gravel, mountain, indoor"
        case .hike: "Hike, walk, ruck, backpacking"
        case .climb: "Rock, boulder, indoor, ferrata"
        case .snow: "Ski, board, snowshoe, skate"
        case .water: "Swim, paddle, surf, sail"
        case .gym: "Strength, cardio, studio"
        case .sport: "Ball, racquet, course"
        case .other: "Board, saddle, hunt, fish"
        }
    }

    var tint: Color {
        switch self {
        case .run: WatchTheme.accent
        case .ride: WatchTheme.highlight
        case .hike: Color(red: 0.42, green: 0.78, blue: 0.45)
        case .climb: Color(red: 0.85, green: 0.35, blue: 0.38)
        case .snow: Color(red: 0.46, green: 0.76, blue: 1.0)
        case .water: Color(red: 0.20, green: 0.72, blue: 0.82)
        case .gym: Color(red: 0.86, green: 0.44, blue: 0.92)
        case .sport: Color(red: 0.97, green: 0.78, blue: 0.30)
        case .other: Color(red: 0.62, green: 0.68, blue: 0.78)
        }
    }

    var sports: [WatchSport] { WatchSport.sports(in: self) }
}

/// Every activity the watch can record, each with its own screen defaults.
nonisolated enum WatchSport: String, Codable, CaseIterable, Identifiable, Sendable {
    case trailRun, roadRun, ultraRun, track, treadmill, virtualRun
    case ride, gravelRide, mountainBike, bikepacking, eBike, commute, indoorRide
    case hike, walk, ruck, backpacking, mountaineering
    case rockClimb, boulder, indoorClimb, viaFerrata
    case backcountrySki, alpineSki, snowboard, splitboard, nordicSki, snowshoe, iceSkate
    case openWaterSwim, poolSwim, kayak, paddleboard, surf, sail
    case strength, hiit, yoga, pilates, cardio, elliptical, stairStepper, row
    case soccer, basketball, tennis, pickleball, golf, discGolf
    case skateboard, horseback, hunt, fish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trailRun: "Trail Run"
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
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .pickleball: "Pickleball"
        case .golf: "Golf"
        case .discGolf: "Disc Golf"
        case .skateboard: "Skateboard"
        case .horseback: "Horse Riding"
        case .hunt: "Hunt"
        case .fish: "Fish"
        }
    }

    var symbol: String {
        switch self {
        case .trailRun: "figure.run"
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
        case .soccer: "figure.outdoor.soccer"
        case .basketball: "figure.basketball"
        case .tennis: "figure.tennis"
        case .pickleball: "figure.pickleball"
        case .golf: "figure.golf"
        case .discGolf: "figure.disc.sports"
        case .skateboard: "figure.skateboarding"
        case .horseback: "figure.equestrian.sports"
        case .hunt: "figure.hunting"
        case .fish: "figure.fishing"
        }
    }

    var family: SportFamily {
        switch self {
        case .trailRun, .roadRun, .ultraRun, .track, .treadmill, .virtualRun: .run
        case .ride, .gravelRide, .mountainBike, .bikepacking, .eBike, .commute, .indoorRide: .ride
        case .hike, .walk, .ruck, .backpacking, .mountaineering: .hike
        case .rockClimb, .boulder, .indoorClimb, .viaFerrata: .climb
        case .backcountrySki, .alpineSki, .snowboard, .splitboard, .nordicSki, .snowshoe, .iceSkate: .snow
        case .openWaterSwim, .poolSwim, .kayak, .paddleboard, .surf, .sail: .water
        case .strength, .hiit, .yoga, .pilates, .cardio, .elliptical, .stairStepper, .row: .gym
        case .soccer, .basketball, .tennis, .pickleball, .golf, .discGolf: .sport
        case .skateboard, .horseback, .hunt, .fish: .other
        }
    }

    var tint: Color { family.tint }

    var isIndoor: Bool {
        switch self {
        case .treadmill, .virtualRun, .indoorRide, .boulder, .indoorClimb, .poolSwim,
             .strength, .hiit, .yoga, .pilates, .cardio, .elliptical, .stairStepper, .row,
             .soccer, .basketball, .tennis, .pickleball:
            true
        default:
            false
        }
    }

    var usesGPS: Bool { !isIndoor }

    /// Swimming, where a course line and a map are of no use.
    var isSwim: Bool { self == .openWaterSwim || self == .poolSwim }

    /// Sports where the screen should lock itself against water.
    var isWaterSport: Bool { family == .water }

    var supportsRoutes: Bool { usesGPS && !isSwim }

    /// Runners, walkers, swimmers and ergometers think in pace; everyone else
    /// thinks in speed.
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

    /// Typical moving speed in metres per second, used for course estimates and
    /// the no-GPS fallback. Zero means the sport has no meaningful travel speed.
    var estimatedSpeed: Double {
        switch self {
        case .trailRun: 2.9
        case .roadRun, .treadmill, .virtualRun: 3.3
        case .ultraRun: 2.4
        case .track: 3.6
        case .ride, .indoorRide: 7.5
        case .gravelRide: 6.2
        case .mountainBike: 4.4
        case .bikepacking: 4.2
        case .eBike: 6.5
        case .commute: 5.0
        case .hike: 1.3
        case .walk: 1.4
        case .ruck: 1.2
        case .backpacking: 1.1
        case .mountaineering: 0.8
        case .rockClimb: 0.2
        case .viaFerrata: 0.4
        case .boulder, .indoorClimb: 0
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
        case .strength, .hiit, .yoga, .pilates, .cardio, .elliptical, .stairStepper, .row: 0
        case .soccer, .basketball, .tennis, .pickleball: 0
        case .golf, .discGolf: 1.0
        case .skateboard: 3.5
        case .horseback: 2.5
        case .hunt: 0.7
        case .fish: 0.3
        }
    }

    /// Rough active kilocalorie burn per minute at a moderate effort, used only
    /// until the watch's own energy readings take over.
    var caloriesPerMinute: Double {
        switch family {
        case .run: 13.5
        case .ride: 11.0
        case .hike: 8.5
        case .climb: 9.5
        case .snow: 10.0
        case .water: 11.5
        case .gym: 8.0
        case .sport: 9.0
        case .other: 5.0
        }
    }

    /// The pages a sport starts with before the athlete customizes anything.
    ///
    /// Identities are seeded from the sport and slot rather than minted fresh, so
    /// a default page keeps the same id between reads. Without that, every edit
    /// would look up a page that no longer exists and quietly do nothing.
    var defaultScreens: [WatchScreen] {
        seedScreens.enumerated().map { index, screen in
            var identified = screen
            identified.id = StableID.defaultPage(sport: rawValue, index: index)
            return identified
        }
    }

    private var seedScreens: [WatchScreen] {
        switch self {
        case .trailRun:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.grade, .ascent, .altitude, .gradeAdjustedPace, .verticalSpeed, .heartRate]),
                .page(.climb),
                .page(.map),
                .page(.elevation),
                .page(.upAhead),
                .data([.lapTime, .lapDistance, .lapPace, .averageHeartRate]),
                .page(.zones),
            ]
        case .ultraRun:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.movingTime, .averagePace, .ascent, .calories, .timeOfDay, .heartRate]),
                .page(.climb),
                .page(.map),
                .page(.upAhead),
                .page(.elevation),
                .data([.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint]),
                .page(.zones),
            ]
        case .roadRun, .track:
            [
                .data([.pace, .distance, .duration]),
                .data([.heartRate, .averagePace, .cadence, .calories]),
                .page(.zones),
                .data([.lapTime, .lapDistance, .lapPace, .averageHeartRate]),
                .page(.laps),
            ]
        case .treadmill, .virtualRun:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.calories, .cadence, .averageHeartRate, .trainingEffect]),
                .page(.zones),
            ]
        case .ride, .gravelRide, .mountainBike:
            [
                .data([.speed, .distance, .duration]),
                .data([.heartRate, .averageSpeed, .ascent, .grade, .power, .calories]),
                .page(.climb),
                .page(.map),
                .page(.elevation),
                .page(.upAhead),
                .page(.zones),
            ]
        case .bikepacking:
            [
                .data([.speed, .distance, .duration]),
                .data([.ascent, .altitude, .heartRate, .timeOfDay]),
                .page(.map),
                .page(.upAhead),
                .page(.climb),
                .page(.elevation),
                .data([.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint]),
                .page(.compass),
            ]
        case .eBike, .commute:
            [
                .data([.speed, .distance, .duration]),
                .data([.averageSpeed, .heartRate, .calories, .timeOfDay]),
                .page(.map),
                .page(.upAhead),
            ]
        case .indoorRide:
            [
                .data([.duration, .speed, .heartRate, .power]),
                .data([.calories, .averageSpeed, .distance, .trainingEffect]),
                .page(.zones),
            ]
        case .hike, .ruck:
            [
                .data([.duration, .distance, .ascent]),
                .data([.altitude, .grade, .heartRate, .calories]),
                .page(.upAhead),
                .page(.climb),
                .page(.map),
                .page(.elevation),
                .data([.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint]),
                .page(.compass),
            ]
        case .backpacking:
            [
                .data([.duration, .distance, .ascent]),
                .data([.altitude, .grade, .timeOfDay, .heartRate]),
                .page(.upAhead),
                .page(.map),
                .page(.climb),
                .page(.elevation),
                .data([.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint]),
                .page(.compass),
            ]
        case .mountaineering:
            [
                .data([.altitude, .ascent, .duration]),
                .data([.verticalSpeed, .grade, .heartRate, .timeOfDay]),
                .page(.climb),
                .page(.elevation),
                .page(.map),
                .page(.upAhead),
                .page(.compass),
            ]
        case .walk:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.calories, .ascent, .averagePace, .timeOfDay]),
                .page(.map),
            ]
        case .rockClimb, .viaFerrata:
            [
                .data([.duration, .ascent, .heartRate]),
                .data([.altitude, .calories, .averageHeartRate, .timeOfDay]),
                .page(.laps),
                .page(.map),
                .page(.zones),
            ]
        case .boulder, .indoorClimb:
            [
                .data([.duration, .lapCount, .heartRate]),
                .data([.lapTime, .calories, .averageHeartRate, .maxHeartRate]),
                .page(.laps),
                .page(.zones),
            ]
        case .backcountrySki, .splitboard:
            [
                .data([.duration, .ascent, .altitude]),
                .data([.verticalSpeed, .grade, .heartRate, .distance]),
                .page(.climb),
                .page(.map),
                .page(.elevation),
                .page(.upAhead),
            ]
        case .alpineSki, .snowboard:
            [
                .data([.descent, .maxSpeed, .duration]),
                .data([.speed, .altitude, .lapCount, .heartRate]),
                .page(.laps),
                .page(.map),
            ]
        case .nordicSki:
            [
                .data([.speed, .distance, .duration]),
                .data([.heartRate, .averageSpeed, .ascent, .calories]),
                .page(.map),
                .page(.elevation),
                .page(.zones),
            ]
        case .snowshoe:
            [
                .data([.duration, .distance, .ascent]),
                .data([.altitude, .grade, .heartRate, .calories]),
                .page(.map),
                .page(.elevation),
                .page(.compass),
            ]
        case .iceSkate:
            [
                .data([.duration, .distance, .speed, .heartRate]),
                .data([.averageSpeed, .lapCount, .calories, .averageHeartRate]),
                .page(.laps),
            ]
        case .openWaterSwim:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .page(.map),
            ]
        case .poolSwim:
            [
                .data([.duration, .distance, .lapCount, .heartRate]),
                .page(.laps),
            ]
        case .kayak, .paddleboard:
            [
                .data([.duration, .distance, .speed, .heartRate]),
                .data([.averageSpeed, .calories, .timeOfDay, .averageHeartRate]),
                .page(.map),
                .page(.upAhead),
            ]
        case .surf:
            [
                .data([.duration, .lapCount, .maxSpeed]),
                .data([.heartRate, .calories, .timeOfDay, .averageHeartRate]),
                .page(.laps),
            ]
        case .sail:
            [
                .data([.speed, .distance, .duration]),
                .data([.maxSpeed, .averageSpeed, .timeOfDay, .heartRate]),
                .page(.map),
                .page(.compass),
                .page(.upAhead),
            ]
        case .row:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.cadence, .power, .calories, .averagePace]),
                .page(.zones),
            ]
        case .strength, .hiit:
            [
                .data([.duration, .heartRate, .calories, .heartRateZone]),
                .page(.zones),
                .data([.lapTime, .lapCount, .averageHeartRate, .maxHeartRate]),
            ]
        case .yoga, .pilates:
            [
                .data([.duration, .heartRate]),
                .data([.calories, .averageHeartRate, .timeOfDay, .heartRateZone]),
            ]
        case .cardio, .elliptical, .stairStepper:
            [
                .data([.duration, .heartRate, .calories]),
                .data([.averageHeartRate, .maxHeartRate, .heartRateZone, .trainingEffect]),
                .page(.zones),
            ]
        case .soccer, .basketball, .tennis, .pickleball:
            [
                .data([.duration, .heartRate, .calories]),
                .data([.averageHeartRate, .maxHeartRate, .heartRateZone, .timeOfDay]),
                .page(.zones),
            ]
        case .golf, .discGolf:
            [
                .data([.duration, .distance, .timeOfDay]),
                .data([.heartRate, .calories, .ascent, .averageHeartRate]),
                .page(.map),
            ]
        case .skateboard:
            [
                .data([.duration, .distance, .speed]),
                .data([.maxSpeed, .heartRate, .calories, .timeOfDay]),
                .page(.map),
            ]
        case .horseback:
            [
                .data([.duration, .distance, .speed]),
                .data([.averageSpeed, .ascent, .heartRate, .timeOfDay]),
                .page(.map),
                .page(.upAhead),
            ]
        case .hunt, .fish:
            [
                .data([.duration, .distance, .timeOfDay]),
                .data([.altitude, .ascent, .heartRate, .calories]),
                .page(.map),
                .page(.compass),
                .data([.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint]),
            ]
        }
    }

    static func sports(in family: SportFamily) -> [WatchSport] {
        allCases.filter { $0.family == family }
    }

    /// Every sport in alphabetical order, for the A–Z browser.
    static var alphabetical: [WatchSport] {
        allCases.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
