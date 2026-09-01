import SwiftUI

/// Groups used to organise the field picker into browsable sections.
nonisolated enum WatchFieldGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case time, distance, pace, heart, elevation, effort, navigation, system

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
        case .system: "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

/// Every metric that can be placed on a customizable data screen.
nonisolated enum WatchDataField: String, CaseIterable, Codable, Identifiable, Sendable {
    // Time
    case duration, movingTime, lapTime, timeOfDay
    // Distance
    case distance, lapDistance, remainingDistance
    // Pace & speed
    case pace, averagePace, lapPace, gradeAdjustedPace, bestPace, speed, averageSpeed, maxSpeed
    // Heart
    case heartRate, averageHeartRate, maxHeartRate, heartRateZone, percentMaxHeartRate
    // Elevation
    case altitude, ascent, descent, grade, verticalSpeed
    // Effort
    case calories, trainingEffect, power, cadence, averageCadence, strideLength
    // Navigation
    case lapCount, eta, distanceToWaypoint, nextWaypoint, offCourse
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
        case .duration, .movingTime, .lapTime, .timeOfDay, .eta, .nextWaypoint: return ""
        case .distance, .lapDistance, .remainingDistance: return units.distanceUnit
        case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace: return units.paceUnit
        case .speed, .averageSpeed, .maxSpeed: return units.speedUnit
        case .heartRate, .averageHeartRate, .maxHeartRate: return "bpm"
        case .heartRateZone: return ""
        case .percentMaxHeartRate, .grade: return "%"
        case .altitude, .ascent, .descent: return units.elevationUnit
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
        case .duration, .movingTime, .lapTime, .timeOfDay: .time
        case .distance, .lapDistance, .remainingDistance: .distance
        case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace, .speed, .averageSpeed, .maxSpeed: .pace
        case .heartRate, .averageHeartRate, .maxHeartRate, .heartRateZone, .percentMaxHeartRate: .heart
        case .altitude, .ascent, .descent, .grade, .verticalSpeed: .elevation
        case .calories, .trainingEffect, .power, .cadence, .averageCadence, .strideLength: .effort
        case .lapCount, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse: .navigation
        case .battery, .gpsSignal, .gpsAccuracy: .system
        }
    }

    /// Fields that only make sense when a route is loaded.
    var requiresRoute: Bool {
        switch self {
        case .remainingDistance, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse: true
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
