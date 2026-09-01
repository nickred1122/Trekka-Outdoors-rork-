import SwiftUI

/// Groups used to organise the field picker into browsable sections.
nonisolated enum WatchFieldGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case time, distance, pace, heart, elevation, effort, navigation, daylight, swim, system

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
        case .swim: "Swim"
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
        case .swim: "figure.pool.swim"
        case .system: "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

/// Every metric that can be placed on a customizable data screen.
nonisolated enum WatchDataField: String, CaseIterable, Codable, Identifiable, Sendable {
    // Time
    case duration, movingTime, lapTime, timeOfDay, pausedTime, averageLapTime, lastLapTime
    // Distance
    case distance, lapDistance, remainingDistance, lastLapDistance
    // Pace & speed
    case pace, averagePace, lapPace, gradeAdjustedPace, bestPace, speed, averageSpeed, maxSpeed, lastLapPace
    // Heart
    case heartRate, averageHeartRate, maxHeartRate, heartRateZone, percentMaxHeartRate
    case lapHeartRate, lastLapHeartRate, timeInZone, percentHeartRateReserve
    // Elevation
    case altitude, ascent, descent, grade, verticalSpeed, remainingAscent
    case lapAscent, lastLapAscent, maxAltitude, minAltitude, remainingDescent, routeAscent, pressure
    // Effort
    case calories, trainingEffect, power, cadence, averageCadence, strideLength, steps
    // Navigation
    case lapCount, eta, distanceToWaypoint, nextWaypoint, offCourse, timeToWaypoint, routeProgress, routeDistance
    case bearing, latitude, longitude, distanceToStart
    // Daylight
    case sunrise, sunset, timeToSunrise, timeToSunset
    // Swim
    case strokes, strokeRate, poolLengths, swolf, lastLengthTime
    // System
    case battery, gpsSignal, gpsAccuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duration: "Timer"
        case .movingTime: "Moving Time"
        case .lapTime: "Lap Time"
        case .timeOfDay: "Time of Day"
        case .distance: "Distance"
        case .lapDistance: "Lap Distance"
        case .remainingDistance: "Distance Left"
        case .pace: "Pace"
        case .averagePace: "Avg Pace"
        case .lapPace: "Lap Pace"
        case .gradeAdjustedPace: "Grade Adj Pace"
        case .bestPace: "Best Pace"
        case .speed: "Speed"
        case .averageSpeed: "Avg Speed"
        case .maxSpeed: "Max Speed"
        case .heartRate: "Heart Rate"
        case .averageHeartRate: "Avg Heart Rate"
        case .maxHeartRate: "Max Heart Rate"
        case .heartRateZone: "HR Zone"
        case .percentMaxHeartRate: "% Max HR"
        case .altitude: "Elevation"
        case .ascent: "Total Ascent"
        case .descent: "Total Descent"
        case .remainingAscent: "Ascent Left"
        case .grade: "Grade"
        case .verticalSpeed: "Vertical Speed"
        case .calories: "Calories"
        case .trainingEffect: "Training Effect"
        case .power: "Power"
        case .cadence: "Cadence"
        case .averageCadence: "Avg Cadence"
        case .strideLength: "Stride Length"
        case .lapCount: "Laps"
        case .eta: "ETA"
        case .distanceToWaypoint: "To Next"
        case .nextWaypoint: "Next Point"
        case .offCourse: "Off Course"
        case .timeToWaypoint: "Time to Next"
        case .routeProgress: "Route Complete"
        case .routeDistance: "Route Length"
        case .sunrise: "Sunrise"
        case .sunset: "Sunset"
        case .timeToSunrise: "Time to Sunrise"
        case .timeToSunset: "Daylight Left"
        case .pausedTime: "Paused Time"
        case .averageLapTime: "Avg Lap Time"
        case .lastLapTime: "Last Lap Time"
        case .lastLapDistance: "Last Lap Distance"
        case .lastLapPace: "Last Lap Pace"
        case .lapHeartRate: "Lap Heart Rate"
        case .lastLapHeartRate: "Last Lap HR"
        case .timeInZone: "Time in Zone"
        case .percentHeartRateReserve: "% HR Reserve"
        case .lapAscent: "Lap Ascent"
        case .lastLapAscent: "Last Lap Ascent"
        case .maxAltitude: "Max Elevation"
        case .minAltitude: "Min Elevation"
        case .remainingDescent: "Descent Left"
        case .routeAscent: "Route Ascent"
        case .pressure: "Air Pressure"
        case .steps: "Steps"
        case .bearing: "Bearing"
        case .latitude: "Latitude"
        case .longitude: "Longitude"
        case .distanceToStart: "Distance to Start"
        case .strokes: "Strokes"
        case .strokeRate: "Stroke Rate"
        case .poolLengths: "Lengths"
        case .swolf: "SWOLF"
        case .lastLengthTime: "Last Length"
        case .battery: "Battery"
        case .gpsSignal: "GPS Signal"
        case .gpsAccuracy: "GPS Accuracy"
        }
    }

    /// Short label that fits a two-column cell.
    var label: String {
        switch self {
        case .duration: "TIMER"
        case .movingTime: "MOVING"
        case .lapTime: "LAP TIME"
        case .timeOfDay: "CLOCK"
        case .distance: "DISTANCE"
        case .lapDistance: "LAP DIST"
        case .remainingDistance: "LEFT"
        case .pace: "PACE"
        case .averagePace: "AVG PACE"
        case .lapPace: "LAP PACE"
        case .gradeAdjustedPace: "GAP"
        case .bestPace: "BEST PACE"
        case .speed: "SPEED"
        case .averageSpeed: "AVG SPEED"
        case .maxSpeed: "MAX SPEED"
        case .heartRate: "HEART RATE"
        case .averageHeartRate: "AVG HR"
        case .maxHeartRate: "MAX HR"
        case .heartRateZone: "ZONE"
        case .percentMaxHeartRate: "% MAX HR"
        case .altitude: "ELEVATION"
        case .ascent: "ASCENT"
        case .descent: "DESCENT"
        case .grade: "GRADE"
        case .verticalSpeed: "VERT SPEED"
        case .calories: "CALORIES"
        case .trainingEffect: "EFFECT"
        case .power: "POWER"
        case .cadence: "CADENCE"
        case .averageCadence: "AVG CAD"
        case .strideLength: "STRIDE"
        case .lapCount: "LAPS"
        case .eta: "ETA"
        case .distanceToWaypoint: "TO NEXT"
        case .nextWaypoint: "NEXT"
        case .offCourse: "OFF COURSE"
        case .timeToWaypoint: "NEXT ETA"
        case .routeProgress: "ROUTE %"
        case .routeDistance: "ROUTE"
        case .sunrise: "SUNRISE"
        case .sunset: "SUNSET"
        case .timeToSunrise: "TO SUNRISE"
        case .timeToSunset: "DAYLIGHT"
        case .remainingAscent: "ASC LEFT"
        case .pausedTime: "PAUSED"
        case .averageLapTime: "AVG LAP"
        case .lastLapTime: "LAST LAP"
        case .lastLapDistance: "LAST DIST"
        case .lastLapPace: "LAST PACE"
        case .lapHeartRate: "LAP HR"
        case .lastLapHeartRate: "LAST HR"
        case .timeInZone: "IN ZONE"
        case .percentHeartRateReserve: "% HRR"
        case .lapAscent: "LAP ASC"
        case .lastLapAscent: "LAST ASC"
        case .maxAltitude: "MAX ELEV"
        case .minAltitude: "MIN ELEV"
        case .remainingDescent: "DESC LEFT"
        case .routeAscent: "ROUTE ASC"
        case .pressure: "PRESSURE"
        case .steps: "STEPS"
        case .bearing: "BEARING"
        case .latitude: "LAT"
        case .longitude: "LON"
        case .distanceToStart: "TO START"
        case .strokes: "STROKES"
        case .strokeRate: "STROKE RATE"
        case .poolLengths: "LENGTHS"
        case .swolf: "SWOLF"
        case .lastLengthTime: "LAST LENGTH"
        case .battery: "BATTERY"
        case .gpsSignal: "GPS"
        case .gpsAccuracy: "GPS ±"
        }
    }

    /// Follows the athlete's chosen unit system, so a cell never labels a value
    /// in metres that was printed in feet.
    var unit: String {
        let units = WatchFormat.units
        switch self {
        case .duration, .movingTime, .lapTime, .timeOfDay, .eta, .nextWaypoint, .timeToWaypoint, .timeToSunrise, .timeToSunset, .sunrise, .sunset: return ""
        case .pausedTime, .averageLapTime, .lastLapTime, .timeInZone, .steps, .latitude, .longitude: return ""
        case .strokes, .poolLengths, .swolf, .lastLengthTime: return ""
        case .strokeRate: return "spm"
        case .pressure: return "hPa"
        case .bearing: return "°"
        case .distance, .lapDistance, .remainingDistance, .routeDistance, .lastLapDistance, .distanceToStart: return units.distanceUnit
        case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace, .lastLapPace: return units.paceUnit
        case .speed, .averageSpeed, .maxSpeed: return units.speedUnit
        case .heartRate, .averageHeartRate, .maxHeartRate, .lapHeartRate, .lastLapHeartRate: return "bpm"
        case .heartRateZone: return ""
        case .percentMaxHeartRate, .grade, .routeProgress, .percentHeartRateReserve: return "%"
        case .altitude, .ascent, .descent, .remainingAscent, .lapAscent, .lastLapAscent,
             .maxAltitude, .minAltitude, .remainingDescent, .routeAscent: return units.elevationUnit
        case .distanceToWaypoint, .offCourse: return units.shortDistanceUnit
        case .verticalSpeed: return units.verticalSpeedUnit
        case .calories: return "kcal"
        case .trainingEffect: return ""
        case .power: return "W"
        case .cadence, .averageCadence: return "spm"
        case .strideLength: return units.shortDistanceUnit
        case .lapCount: return ""
        case .battery: return "%"
        case .gpsSignal: return ""
        case .gpsAccuracy: return units.shortDistanceUnit
        }
    }

    var group: WatchFieldGroup {
        switch self {
        case .duration, .movingTime, .lapTime, .timeOfDay, .pausedTime, .averageLapTime, .lastLapTime: .time
        case .distance, .lapDistance, .remainingDistance, .lastLapDistance: .distance
        case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace, .speed, .averageSpeed, .maxSpeed, .lastLapPace: .pace
        case .heartRate, .averageHeartRate, .maxHeartRate, .heartRateZone, .percentMaxHeartRate,
             .lapHeartRate, .lastLapHeartRate, .timeInZone, .percentHeartRateReserve: .heart
        case .altitude, .ascent, .descent, .grade, .verticalSpeed, .remainingAscent,
             .lapAscent, .lastLapAscent, .maxAltitude, .minAltitude, .remainingDescent, .routeAscent, .pressure: .elevation
        case .calories, .trainingEffect, .power, .cadence, .averageCadence, .strideLength, .steps: .effort
        case .lapCount, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse, .timeToWaypoint, .routeProgress, .routeDistance,
             .bearing, .latitude, .longitude, .distanceToStart: .navigation
        case .sunrise, .sunset, .timeToSunrise, .timeToSunset: .daylight
        case .strokes, .strokeRate, .poolLengths, .swolf, .lastLengthTime: .swim
        case .battery, .gpsSignal, .gpsAccuracy: .system
        }
    }

    /// Fields that only make sense when a route is loaded.
    var requiresRoute: Bool {
        switch self {
        case .remainingDistance, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse, .timeToWaypoint,
             .routeProgress, .routeDistance, .remainingAscent, .remainingDescent, .routeAscent: true
        default: false
        }
    }

    var tint: Color {
        switch group {
        case .heart: WatchTheme.danger
        case .elevation: WatchTheme.highlight
        case .navigation: WatchTheme.accent
        default: WatchTheme.textPrimary
        }
    }

    /// Renders the field's current value from a metrics snapshot.
    func value(from metrics: LiveMetrics) -> String {
        switch self {
        case .duration: WatchFormat.duration(metrics.elapsed)
        case .movingTime: WatchFormat.duration(metrics.movingTime)
        case .lapTime: WatchFormat.duration(metrics.lapElapsed)
        case .timeOfDay: WatchFormat.clock(.now)
        case .distance: WatchFormat.distance(metrics.distance)
        case .lapDistance: WatchFormat.distance(metrics.lapDistance)
        case .remainingDistance: WatchFormat.distance(metrics.remainingDistance)
        case .pace: WatchFormat.pace(metrics.pace)
        case .averagePace: WatchFormat.pace(metrics.averagePace)
        case .lapPace: WatchFormat.pace(metrics.lapPace)
        case .gradeAdjustedPace: WatchFormat.pace(metrics.gradeAdjustedPace)
        case .bestPace: WatchFormat.pace(metrics.bestPace)
        case .speed: WatchFormat.speed(metrics.currentSpeed)
        case .averageSpeed: WatchFormat.speed(metrics.averageSpeed)
        case .maxSpeed: WatchFormat.speed(metrics.maxSpeed)
        case .heartRate: metrics.heartRate > 0 ? WatchFormat.integer(metrics.heartRate) : "--"
        case .averageHeartRate: metrics.averageHeartRate > 0 ? WatchFormat.integer(metrics.averageHeartRate) : "--"
        case .maxHeartRate: metrics.maxHeartRate > 0 ? WatchFormat.integer(metrics.maxHeartRate) : "--"
        case .heartRateZone: metrics.heartRate > 0 ? "\(metrics.heartRateZone)" : "--"
        case .percentMaxHeartRate: metrics.heartRate > 0 ? WatchFormat.percent(metrics.percentMaxHeartRate) : "--"
        case .altitude: WatchFormat.elevation(metrics.altitude)
        case .ascent: WatchFormat.elevation(metrics.ascent)
        case .descent: WatchFormat.elevation(metrics.descent)
        case .grade: WatchFormat.signedDecimal(metrics.grade, places: 1)
        case .verticalSpeed: WatchFormat.elevation(metrics.verticalSpeed)
        case .calories: WatchFormat.integer(metrics.calories)
        case .trainingEffect: WatchFormat.decimal(metrics.trainingEffect, places: 1)
        case .power: metrics.power > 0 ? WatchFormat.integer(metrics.power) : "--"
        case .cadence: metrics.cadence > 0 ? WatchFormat.integer(metrics.cadence) : "--"
        case .averageCadence: metrics.averageCadence > 0 ? WatchFormat.integer(metrics.averageCadence) : "--"
        case .strideLength: metrics.strideLength > 0
            ? WatchFormat.decimal(WatchFormat.units.shortDistance(fromMetres: metrics.strideLength), places: 2)
            : "--"
        case .lapCount: "\(metrics.lapCount)"
        case .eta: metrics.etaSeconds > 0 ? WatchFormat.clock(Date().addingTimeInterval(metrics.etaSeconds)) : "--:--"
        case .distanceToWaypoint: metrics.distanceToWaypoint > 0 ? WatchFormat.shortDistance(metrics.distanceToWaypoint) : "--"
        case .nextWaypoint: metrics.nextWaypointName
        case .offCourse: WatchFormat.shortDistance(metrics.offCourseMetres)
        case .timeToWaypoint: metrics.timeToWaypointSeconds > 0
            ? WatchFormat.duration(metrics.timeToWaypointSeconds)
            : "--:--"
        case .routeProgress: metrics.routeProgressFraction > 0
            ? WatchFormat.percent(metrics.routeProgressFraction)
            : "--"
        case .routeDistance: metrics.courseDistance + metrics.remainingDistance > 0
            ? WatchFormat.distance(metrics.courseDistance + metrics.remainingDistance)
            : "--"
        case .sunrise: metrics.sunrise.map { WatchFormat.clock($0) } ?? "--:--"
        case .sunset: metrics.sunset.map { WatchFormat.clock($0) } ?? "--:--"
        case .timeToSunrise: metrics.sunrise.map { WatchFormat.duration(max(0, $0.timeIntervalSinceNow)) } ?? "--:--"
        case .timeToSunset: metrics.sunset.map { WatchFormat.duration(max(0, $0.timeIntervalSinceNow)) } ?? "--:--"
        case .remainingAscent: metrics.remainingAscent > 0 ? WatchFormat.elevation(metrics.remainingAscent) : "--"
        case .remainingDescent: metrics.remainingDescent > 0 ? WatchFormat.elevation(metrics.remainingDescent) : "--"
        case .routeAscent: metrics.routeAscent > 0 ? WatchFormat.elevation(metrics.routeAscent) : "--"
        case .pausedTime: WatchFormat.duration(metrics.pausedTime)
        case .averageLapTime: metrics.averageLapTime > 0 ? WatchFormat.duration(metrics.averageLapTime) : "--:--"
        case .lastLapTime: metrics.lastLapDuration > 0 ? WatchFormat.duration(metrics.lastLapDuration) : "--:--"
        case .lastLapDistance: metrics.lastLapDuration > 0 ? WatchFormat.distance(metrics.lastLapDistance) : "--"
        case .lastLapPace: metrics.lastLapPace > 0 ? WatchFormat.pace(metrics.lastLapPace) : "--:--"
        case .lapHeartRate: metrics.lapHeartRate > 0 ? WatchFormat.integer(metrics.lapHeartRate) : "--"
        case .lastLapHeartRate: metrics.lastLapHeartRate > 0 ? WatchFormat.integer(metrics.lastLapHeartRate) : "--"
        case .timeInZone: metrics.heartRate > 0 ? WatchFormat.duration(metrics.timeInCurrentZone) : "--:--"
        case .percentHeartRateReserve: metrics.percentHeartRateReserve.map { WatchFormat.percent($0) } ?? "--"
        case .lapAscent: WatchFormat.elevation(metrics.lapAscent)
        case .lastLapAscent: metrics.lastLapDuration > 0 ? WatchFormat.elevation(metrics.lastLapAscent) : "--"
        case .maxAltitude: metrics.maxAltitude.map { WatchFormat.elevation($0) } ?? "--"
        case .minAltitude: metrics.minAltitude.map { WatchFormat.elevation($0) } ?? "--"
        case .pressure: metrics.pressure > 0 ? WatchFormat.integer(metrics.pressure) : "--"
        case .steps: WatchFormat.integer(metrics.steps)
        case .bearing: metrics.hasPosition ? WatchFormat.integer(metrics.bearing) : "--"
        case .latitude: metrics.hasPosition ? WatchFormat.decimal(metrics.latitude, places: 4) : "--"
        case .longitude: metrics.hasPosition ? WatchFormat.decimal(metrics.longitude, places: 4) : "--"
        case .distanceToStart: metrics.hasPosition ? WatchFormat.distance(metrics.distanceToStart) : "--"
        case .strokes: metrics.strokes > 0 ? WatchFormat.integer(metrics.strokes) : "--"
        case .strokeRate: metrics.strokeRate > 0 ? WatchFormat.integer(metrics.strokeRate) : "--"
        case .poolLengths: metrics.poolLengths > 0 ? "\(metrics.poolLengths)" : "--"
        case .swolf: metrics.swolf > 0 ? WatchFormat.integer(metrics.swolf) : "--"
        case .lastLengthTime: metrics.lastLengthSeconds > 0 ? WatchFormat.duration(metrics.lastLengthSeconds) : "--:--"
        case .battery: WatchFormat.percent(metrics.batteryFraction)
        // Three bars of signal, or plain words when there is none to report.
        case .gpsSignal: metrics.isGPSLive ? "\(max(0, min(3, metrics.gpsBars)))/3" : "--"
        case .gpsAccuracy: metrics.isGPSLive && metrics.horizontalAccuracy > 0
            ? WatchFormat.shortDistance(metrics.horizontalAccuracy)
            : "--"
        }
    }

    /// Sample value used by editor previews before a workout has started.
    var previewValue: String {
        switch self {
        case .duration, .movingTime: "48:12"
        case .lapTime: "6:04"
        case .timeOfDay, .eta: "07:42"
        case .distance: "8.42"
        case .lapDistance: "0.62"
        case .remainingDistance: "4.10"
        case .pace, .lapPace: "5:12"
        case .averagePace: "5:24"
        case .gradeAdjustedPace: "4:58"
        case .bestPace: "4:36"
        case .speed: "11.6"
        case .averageSpeed: "10.9"
        case .maxSpeed: "18.2"
        case .heartRate: "154"
        case .averageHeartRate: "147"
        case .maxHeartRate: "172"
        case .heartRateZone: "3"
        case .percentMaxHeartRate: "82"
        case .altitude: "1284"
        case .ascent: "612"
        case .descent: "418"
        case .grade: "+6.4"
        case .verticalSpeed: "684"
        case .calories: "612"
        case .trainingEffect: "3.4"
        case .power: "268"
        case .cadence, .averageCadence: "172"
        case .strideLength: "1.14"
        case .lapCount: "8"
        case .distanceToWaypoint: "480"
        case .nextWaypoint: "Saddle"
        case .offCourse: "12"
        case .timeToWaypoint: "8:32"
        case .routeProgress: "62"
        case .routeDistance: "12.5"
        case .sunrise: "06:12"
        case .sunset: "20:47"
        case .timeToSunrise: "9:24"
        case .timeToSunset: "3:26"
        case .remainingAscent: "438"
        case .remainingDescent: "512"
        case .routeAscent: "1080"
        case .pausedTime: "2:14"
        case .averageLapTime: "6:01"
        case .lastLapTime: "5:58"
        case .lastLapDistance: "1.00"
        case .lastLapPace: "5:58"
        case .lapHeartRate: "151"
        case .lastLapHeartRate: "149"
        case .timeInZone: "18:40"
        case .percentHeartRateReserve: "74"
        case .lapAscent: "64"
        case .lastLapAscent: "58"
        case .maxAltitude: "1402"
        case .minAltitude: "860"
        case .pressure: "1013"
        case .steps: "8420"
        case .bearing: "142"
        case .latitude: "51.4779"
        case .longitude: "-0.0015"
        case .distanceToStart: "3.20"
        case .strokes: "412"
        case .strokeRate: "32"
        case .poolLengths: "24"
        case .swolf: "38"
        case .lastLengthTime: "0:22"
        case .battery: "78"
        case .gpsSignal: "3/3"
        case .gpsAccuracy: "6"
        }
    }

    static func fields(in group: WatchFieldGroup) -> [WatchDataField] {
        allCases.filter { $0.group == group }
    }

    /// Metrics used to fill new slots when a layout grows, ordered by how often
    /// an athlete in this sport would actually want them.
    static func suggestions(for sport: WatchSport) -> [WatchDataField] {
        var list: [WatchDataField] = [.duration, .distance]
        if sport.estimatedSpeed > 0 {
            list.append(sport.usesPace ? .pace : .speed)
        }
        list += [.heartRate, .calories]
        if sport.usesElevation {
            list += [.ascent, .altitude, .grade]
        }
        list += [.timeOfDay, .averageHeartRate, .lapTime, .lapDistance, .movingTime]
        return list
    }
}
