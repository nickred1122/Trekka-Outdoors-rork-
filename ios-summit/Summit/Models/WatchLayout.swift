import SwiftUI

/// Phone-side mirror of the watch's screen configuration.
///
/// The raw values and the encoded shape match the watch app exactly, so a
/// layout designed here is the same document the watch reads.

nonisolated enum WatchMetricGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case time, distance, pace, heart, elevation, effort, navigation, daylight, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "Time"
        case .distance: "Distance"
        case .pace: "Pace & Speed"
        case .heart: "Heart"
        case .elevation: "Elevation"
        case .effort: "Effort"
        case .navigation: "Navigation"
        case .daylight: "Daylight"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .time: "stopwatch"
        case .distance: "ruler"
        case .pace: "speedometer"
        case .heart: "heart.fill"
        case .elevation: "mountain.2.fill"
        case .effort: "flame.fill"
        case .navigation: "location.north.line.fill"
        case .daylight: "sun.and.horizon.fill"
        case .system: "battery.75percent"
        }
    }
}

nonisolated struct WatchMetricInfo: Sendable {
    var title: String
    var label: String
    var preview: String
    var group: WatchMetricGroup
}

/// Every metric that can be placed on a watch data screen.
nonisolated enum WatchMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case duration, movingTime, lapTime, timeOfDay, pausedTime, averageLapTime, lastLapTime
    case distance, lapDistance, remainingDistance, lastLapDistance
    case pace, averagePace, lapPace, gradeAdjustedPace, bestPace, speed, averageSpeed, maxSpeed, lastLapPace
    case heartRate, averageHeartRate, maxHeartRate, heartRateZone, percentMaxHeartRate
    case lapHeartRate, lastLapHeartRate, timeInZone
    case altitude, ascent, descent, grade, verticalSpeed, remainingAscent
    case lapAscent, lastLapAscent, maxAltitude, minAltitude, remainingDescent, routeAscent
    case calories, trainingEffect, power, cadence, averageCadence, strideLength, steps
    case lapCount, eta, distanceToWaypoint, nextWaypoint, offCourse, timeToWaypoint, routeProgress, routeDistance
    case bearing, latitude, longitude, distanceToStart
    case sunrise, sunset, timeToSunrise, timeToSunset
    case battery, gpsSignal, gpsAccuracy

    var id: String { rawValue }

    var info: WatchMetricInfo {
        WatchMetric.catalog[self] ?? WatchMetricInfo(title: rawValue, label: rawValue.uppercased(), preview: "--", group: .system)
    }

    var title: String { info.title }
    var label: String { info.label }
    var preview: String { info.preview }

    /// Follows the athlete's chosen system, so the designer never previews a
    /// screen in kilometres that the watch will render in miles. Kept in step
    /// with `WatchDataField.unit` on the watch side.
    var unit: String {
        let units = Formatters.units
        switch self {
        case .duration, .movingTime, .lapTime, .timeOfDay, .eta, .nextWaypoint, .timeToWaypoint, .timeToSunrise, .timeToSunset, .sunrise, .sunset: return ""
        case .pausedTime, .averageLapTime, .lastLapTime, .timeInZone, .steps, .latitude, .longitude: return ""
        case .bearing: return "°"
        case .distance, .lapDistance, .remainingDistance, .routeDistance, .lastLapDistance, .distanceToStart: return units.distanceUnit
        case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace, .lastLapPace: return units.paceUnit
        case .speed, .averageSpeed, .maxSpeed: return units.speedUnit
        case .heartRate, .averageHeartRate, .maxHeartRate, .lapHeartRate, .lastLapHeartRate: return "bpm"
        case .heartRateZone, .trainingEffect, .lapCount, .gpsSignal: return ""
        case .percentMaxHeartRate, .grade, .battery, .routeProgress: return "%"
        case .altitude, .ascent, .descent, .remainingAscent, .lapAscent, .lastLapAscent,
             .maxAltitude, .minAltitude, .remainingDescent, .routeAscent: return units.elevationUnit
        case .verticalSpeed: return units.verticalSpeedUnit
        case .calories: return "kcal"
        case .power: return "W"
        case .cadence, .averageCadence: return "spm"
        case .strideLength, .distanceToWaypoint, .offCourse, .gpsAccuracy: return units.shortDistanceUnit
        }
    }
    var group: WatchMetricGroup { info.group }

    var requiresRoute: Bool {
        switch self {
        case .remainingDistance, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse, .timeToWaypoint,
             .routeProgress, .routeDistance, .remainingAscent, .remainingDescent, .routeAscent: true
        default: false
        }
    }

    var tint: Color {
        switch group {
        case .heart: Theme.danger
        case .elevation: Theme.highlight
        case .navigation: Theme.accent
        default: Theme.textPrimary
        }
    }

    static func metrics(in group: WatchMetricGroup) -> [WatchMetric] {
        allCases.filter { $0.group == group }
    }

    /// Metrics used to fill new slots when a layout grows, ordered by how often
    /// an athlete in this sport would actually want them.
    static func suggestions(for sport: WatchSportProfile) -> [WatchMetric] {
        var list: [WatchMetric] = [.duration, .distance]
        list.append(sport.usesPace ? .pace : .speed)
        list += [.heartRate, .calories]
        if sport.usesElevation {
            list += [.ascent, .altitude, .grade]
        }
        list += [.timeOfDay, .averageHeartRate, .lapTime, .lapDistance, .movingTime]
        return list
    }

    static let catalog: [WatchMetric: WatchMetricInfo] = [
        .duration: .init(title: "Timer", label: "TIMER", preview: "48:12", group: .time),
        .movingTime: .init(title: "Moving Time", label: "MOVING", preview: "46:50", group: .time),
        .lapTime: .init(title: "Lap Time", label: "LAP TIME", preview: "6:04", group: .time),
        .timeOfDay: .init(title: "Time of Day", label: "CLOCK", preview: "07:42", group: .time),
        .distance: .init(title: "Distance", label: "DISTANCE", preview: "8.42", group: .distance),
        .lapDistance: .init(title: "Lap Distance", label: "LAP DIST", preview: "0.62", group: .distance),
        .remainingDistance: .init(title: "Distance Left", label: "LEFT", preview: "4.10", group: .distance),
        .pace: .init(title: "Pace", label: "PACE", preview: "5:12", group: .pace),
        .averagePace: .init(title: "Avg Pace", label: "AVG PACE", preview: "5:24", group: .pace),
        .lapPace: .init(title: "Lap Pace", label: "LAP PACE", preview: "5:02", group: .pace),
        .gradeAdjustedPace: .init(title: "Grade Adj Pace", label: "GAP", preview: "4:58", group: .pace),
        .bestPace: .init(title: "Best Pace", label: "BEST PACE", preview: "4:36", group: .pace),
        .speed: .init(title: "Speed", label: "SPEED", preview: "11.6", group: .pace),
        .averageSpeed: .init(title: "Avg Speed", label: "AVG SPEED", preview: "10.9", group: .pace),
        .maxSpeed: .init(title: "Max Speed", label: "MAX SPEED", preview: "18.2", group: .pace),
        .heartRate: .init(title: "Heart Rate", label: "HEART RATE", preview: "154", group: .heart),
        .averageHeartRate: .init(title: "Avg Heart Rate", label: "AVG HR", preview: "147", group: .heart),
        .maxHeartRate: .init(title: "Max Heart Rate", label: "MAX HR", preview: "172", group: .heart),
        .heartRateZone: .init(title: "HR Zone", label: "ZONE", preview: "3", group: .heart),
        .percentMaxHeartRate: .init(title: "% Max HR", label: "% MAX HR", preview: "82", group: .heart),
        .altitude: .init(title: "Elevation", label: "ELEVATION", preview: "1284", group: .elevation),
        .ascent: .init(title: "Total Ascent", label: "ASCENT", preview: "612", group: .elevation),
        .descent: .init(title: "Total Descent", label: "DESCENT", preview: "418", group: .elevation),
        .grade: .init(title: "Grade", label: "GRADE", preview: "+6.4", group: .elevation),
        .verticalSpeed: .init(title: "Vertical Speed", label: "VERT SPEED", preview: "684", group: .elevation),
        .calories: .init(title: "Calories", label: "CALORIES", preview: "612", group: .effort),
        .trainingEffect: .init(title: "Training Effect", label: "EFFECT", preview: "3.4", group: .effort),
        .power: .init(title: "Power", label: "POWER", preview: "268", group: .effort),
        .cadence: .init(title: "Cadence", label: "CADENCE", preview: "172", group: .effort),
        .averageCadence: .init(title: "Avg Cadence", label: "AVG CAD", preview: "168", group: .effort),
        .strideLength: .init(title: "Stride Length", label: "STRIDE", preview: "1.14", group: .effort),
        .lapCount: .init(title: "Laps", label: "LAPS", preview: "8", group: .navigation),
        .eta: .init(title: "ETA", label: "ETA", preview: "08:04", group: .navigation),
        .distanceToWaypoint: .init(title: "To Next", label: "TO NEXT", preview: "480", group: .navigation),
        .nextWaypoint: .init(title: "Next Point", label: "NEXT", preview: "Saddle", group: .navigation),
        .offCourse: .init(title: "Off Course", label: "OFF COURSE", preview: "12", group: .navigation),
        .timeToWaypoint: .init(title: "Time to Next", label: "NEXT ETA", preview: "8:32", group: .navigation),
        .routeProgress: .init(title: "Route Complete", label: "ROUTE %", preview: "62", group: .navigation),
        .routeDistance: .init(title: "Route Length", label: "ROUTE", preview: "12.5", group: .navigation),
        .sunrise: .init(title: "Sunrise", label: "SUNRISE", preview: "06:12", group: .daylight),
        .sunset: .init(title: "Sunset", label: "SUNSET", preview: "20:47", group: .daylight),
        .timeToSunrise: .init(title: "Time to Sunrise", label: "TO SUNRISE", preview: "9:24", group: .daylight),
        .timeToSunset: .init(title: "Daylight Left", label: "DAYLIGHT", preview: "3:26", group: .daylight),
        .remainingAscent: .init(title: "Ascent Left", label: "ASC LEFT", preview: "438", group: .elevation),
        .remainingDescent: .init(title: "Descent Left", label: "DESC LEFT", preview: "512", group: .elevation),
        .routeAscent: .init(title: "Route Ascent", label: "ROUTE ASC", preview: "1080", group: .elevation),
        .lapAscent: .init(title: "Lap Ascent", label: "LAP ASC", preview: "64", group: .elevation),
        .lastLapAscent: .init(title: "Last Lap Ascent", label: "LAST ASC", preview: "58", group: .elevation),
        .maxAltitude: .init(title: "Max Elevation", label: "MAX ELEV", preview: "1402", group: .elevation),
        .minAltitude: .init(title: "Min Elevation", label: "MIN ELEV", preview: "860", group: .elevation),
        .pausedTime: .init(title: "Paused Time", label: "PAUSED", preview: "2:14", group: .time),
        .averageLapTime: .init(title: "Avg Lap Time", label: "AVG LAP", preview: "6:01", group: .time),
        .lastLapTime: .init(title: "Last Lap Time", label: "LAST LAP", preview: "5:58", group: .time),
        .lastLapDistance: .init(title: "Last Lap Distance", label: "LAST DIST", preview: "1.00", group: .distance),
        .lastLapPace: .init(title: "Last Lap Pace", label: "LAST PACE", preview: "5:58", group: .pace),
        .lapHeartRate: .init(title: "Lap Heart Rate", label: "LAP HR", preview: "151", group: .heart),
        .lastLapHeartRate: .init(title: "Last Lap HR", label: "LAST HR", preview: "149", group: .heart),
        .timeInZone: .init(title: "Time in Zone", label: "IN ZONE", preview: "18:40", group: .heart),
        .steps: .init(title: "Steps", label: "STEPS", preview: "8420", group: .effort),
        .bearing: .init(title: "Bearing", label: "BEARING", preview: "142", group: .navigation),
        .latitude: .init(title: "Latitude", label: "LAT", preview: "51.4779", group: .navigation),
        .longitude: .init(title: "Longitude", label: "LON", preview: "-0.0015", group: .navigation),
        .distanceToStart: .init(title: "Distance to Start", label: "TO START", preview: "3.20", group: .navigation),
        .battery: .init(title: "Battery", label: "BATTERY", preview: "78", group: .system),
        .gpsSignal: .init(title: "GPS Signal", label: "GPS", preview: "Good", group: .system),
        .gpsAccuracy: .init(title: "GPS Accuracy", label: "GPS ±", preview: "4", group: .system),
    ]
}

nonisolated enum WatchPageKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case data, map, elevation, climb, upAhead, zones, laps, compass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: "Data Screen"
        case .map: "Map"
        case .elevation: "Elevation Profile"
        case .climb: "Climb"
        case .upAhead: "Up Ahead"
        case .zones: "Heart Rate Zones"
        case .laps: "Laps"
        case .compass: "Compass"
        }
    }

    var symbol: String {
        switch self {
        case .data: "square.grid.2x2.fill"
        case .map: "map.fill"
        case .elevation: "mountain.2.fill"
        case .climb: "arrow.up.right"
        case .upAhead: "list.bullet.below.rectangle"
        case .zones: "chart.bar.fill"
        case .laps: "flag.checkered"
        case .compass: "location.north.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .data: "Your metrics, in a layout you choose"
        case .map: "Route line, breadcrumb and waypoints"
        case .elevation: "Climb profile with your position"
        case .climb: "The climb you are on, and what is left of it"
        case .upAhead: "Every waypoint and summit still to come"
        case .zones: "Time in each heart-rate zone"
        case .laps: "Every split as you record it"
        case .compass: "Bearing and direction of travel"
        }
    }

    /// Pages that only mean anything once a course is loaded.
    var requiresRoute: Bool {
        self == .climb || self == .upAhead
    }
}

/// One page in a sport's watch carousel.
nonisolated struct WatchPage: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: WatchPageKind
    var fields: [WatchMetric] = []
    var isEnabled: Bool = true
    /// A chosen arrangement, or nil to let the page arrange itself around
    /// however many metrics it holds.
    var layout: WatchPageLayout?

    static let maxFields = WatchPageLayout.maxSlots

    static func data(_ fields: [WatchMetric], layout: WatchPageLayout? = nil) -> WatchPage {
        WatchPage(
            kind: .data,
            fields: Array(fields.prefix(layout?.slotCount ?? maxFields)),
            layout: layout
        )
    }

    /// The arrangement actually drawn: the chosen one, or the automatic shape
    /// for however many metrics are on the page.
    var resolvedLayout: WatchPageLayout {
        layout ?? .automatic(forSlots: fields.count)
    }

    /// Grows or trims the metric list to match a layout, keeping what is already
    /// there and topping up from the sport's usual suspects.
    func fitted(to layout: WatchPageLayout?, suggestions: [WatchMetric]) -> WatchPage {
        var copy = self
        copy.layout = layout
        guard let layout else { return copy }
        var filled = Array(fields.prefix(layout.slotCount))
        for candidate in suggestions where filled.count < layout.slotCount {
            guard !filled.contains(candidate) else { continue }
            filled.append(candidate)
        }
        // A short suggestion list must never leave a hole in the grid.
        while filled.count < layout.slotCount {
            filled.append(.duration)
        }
        copy.fields = filled
        return copy
    }

    static func page(_ kind: WatchPageKind) -> WatchPage {
        WatchPage(kind: kind)
    }

    var title: String {
        guard kind == .data else { return kind.title }
        guard let first = fields.first else { return "Empty Screen" }
        if fields.count == 1 { return first.title }
        return "\(first.title) +\(fields.count - 1)"
    }

    var summary: String {
        guard kind == .data else { return kind.detail }
        guard !fields.isEmpty else { return "No metrics yet" }
        return fields.map(\.title).joined(separator: " · ")
    }
}

// Decoding lives in an extension so the memberwise initialiser survives.
extension WatchPage {
    private enum CodingKeys: String, CodingKey {
        case id, kind, fields, isEnabled, layout
    }

    /// Skips metrics this build does not recognise instead of failing.
    ///
    /// The watch and the phone do not always ship the same list of metrics, and
    /// the two sync by exchanging one document. Refusing the whole document over
    /// a single unknown name would silently throw away every other setting the
    /// athlete had changed — which is exactly the bug this replaced.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try container.decode(WatchPageKind.self, forKey: .kind),
            fields: (try container.decodeIfPresent([String].self, forKey: .fields) ?? [])
                .compactMap(WatchMetric.init(rawValue:)),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            // An unrecognised pattern falls back to the automatic arrangement
            // rather than throwing the whole document away.
            layout: (try? container.decodeIfPresent(WatchPageLayout.self, forKey: .layout)) ?? nil
        )
    }
}

nonisolated enum WatchSportFamily: String, CaseIterable, Codable, Sendable, Identifiable {
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
        case .run: Theme.accent
        case .ride: Theme.highlight
        case .hike: Color(red: 0.42, green: 0.78, blue: 0.45)
        case .climb: Color(red: 0.85, green: 0.35, blue: 0.38)
        case .snow: Color(red: 0.46, green: 0.76, blue: 1.0)
        case .water: Color(red: 0.20, green: 0.72, blue: 0.82)
        case .gym: Color(red: 0.86, green: 0.44, blue: 0.92)
        case .sport: Color(red: 0.97, green: 0.78, blue: 0.30)
        case .other: Color(red: 0.62, green: 0.68, blue: 0.78)
        }
    }

    var sports: [WatchSportProfile] { WatchSportProfile.sports(in: self) }
}

/// The activity profiles the watch can record.
nonisolated enum WatchSportProfile: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var family: WatchSportFamily {
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

    var supportsRoutes: Bool { usesGPS && !isSwim }

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

    static func sports(in family: WatchSportFamily) -> [WatchSportProfile] {
        allCases.filter { $0.family == family }
    }

    /// Must stay in step with the watch app's own defaults.
    ///
    /// Identities are seeded from the sport and slot rather than minted fresh, so
    /// a default page keeps the same id between reads. Without that, every edit
    /// would look up a page that no longer exists and quietly do nothing.
    var defaultPages: [WatchPage] {
        seedPages.enumerated().map { index, page in
            var identified = page
            identified.id = StableID.defaultPage(sport: rawValue, index: index)
            return identified
        }
    }

    private var seedPages: [WatchPage] {
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
        case .walk:
            [
                .data([.duration, .distance, .pace, .heartRate]),
                .data([.calories, .ascent, .averagePace, .timeOfDay]),
                .page(.map),
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

    /// Every sport in alphabetical order, for the A–Z browser.
    static var alphabetical: [WatchSportProfile] {
        allCases.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
