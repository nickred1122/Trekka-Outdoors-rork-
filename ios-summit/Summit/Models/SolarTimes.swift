import Foundation

/// Sunrise and sunset, computed on-device from position and date.
///
/// Deliberately no weather service and no network: the sun's schedule is
/// geometry, so it comes from the sunrise equation evaluated on the same GPS
/// fix the workout already has. The horizon is the standard −0.833° that folds
/// in atmospheric refraction. Polar day and polar night produce no event at
/// all, which the data fields render as "--" rather than inventing a time.
nonisolated struct SolarTimes: Sendable, Equatable {
    let sunrise: Date?
    let sunset: Date?

    /// Solar events for the UTC day containing `date`.
    init(date: Date, latitude: Double, longitude: Double) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let midnight = utc.startOfDay(for: date)
        // Nudged 0.0008 of a day so the equation of time is evaluated near the
        // solar noon it corrects, per the standard formulation.
        let julianDay = midnight.timeIntervalSince1970 / 86400.0 + 2440587.5 + 0.0008

        let n = julianDay - 2451545.0
        let meanSolarNoon = n - longitude / 360.0
        let meanAnomaly = Self.normalized(357.5291 + 0.98560028 * meanSolarNoon)
        let centre = 1.9148 * Self.sin(meanAnomaly)
            + 0.0200 * Self.sin(2 * meanAnomaly)
            + 0.0003 * Self.sin(3 * meanAnomaly)
        let eclipticLongitude = Self.normalized(meanAnomaly + centre + 282.9372)
        let jTransit = 2451545.0 + meanSolarNoon
            + 0.0053 * Self.sin(meanAnomaly)
            - 0.0069 * Self.sin(2 * eclipticLongitude)

        let latitudeRadians = latitude * .pi / 180
        let sinDeclination = Self.sin(eclipticLongitude) * Self.sin(23.44)
        let declination = asin(sinDeclination)
        let horizon = Self.sin(-0.833)
        let cosHourAngle = (horizon - Self.sin(latitudeRadians) * sinDeclination)
            / (cos(latitudeRadians) * cos(declination))

        guard cosHourAngle.isFinite, abs(cosHourAngle) <= 1 else {
            // Above the Arctic or Antarctic circle the sun either never sets or
            // never rises today; neither event exists to report.
            self.sunrise = nil
            self.sunset = nil
            return
        }

        // Hour angle in days: 2π radians is one sidereal sweep of the earth.
        let hourAngle = acos(cosHourAngle) / (2 * .pi)
        self.sunrise = Self.date(fromJulian: jTransit - hourAngle)
        self.sunset = Self.date(fromJulian: jTransit + hourAngle)
    }

    /// The next sunrise at or after `date`, checking up to three days ahead.
    static func nextSunrise(after date: Date, latitude: Double, longitude: Double) -> Date? {
        next(\.sunrise, after: date, latitude: latitude, longitude: longitude)
    }

    /// The next sunset at or after `date`, checking up to three days ahead.
    static func nextSunset(after date: Date, latitude: Double, longitude: Double) -> Date? {
        next(\.sunset, after: date, latitude: latitude, longitude: longitude)
    }

    private static func next(
        _ event: KeyPath<SolarTimes, Date?>,
        after date: Date,
        latitude: Double,
        longitude: Double
    ) -> Date? {
        for dayOffset in 0..<3 {
            let candidate = date.addingTimeInterval(Double(dayOffset) * 86400)
            let times = SolarTimes(date: candidate, latitude: latitude, longitude: longitude)
            if let time = times[keyPath: event], time >= date { return time }
        }
        return nil
    }

    private static func date(fromJulian day: Double) -> Date {
        Date(timeIntervalSince1970: (day - 2440587.5) * 86400)
    }

    private static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func sin(_ degrees: Double) -> Double {
        Foundation.sin(degrees * .pi / 180)
    }
}
