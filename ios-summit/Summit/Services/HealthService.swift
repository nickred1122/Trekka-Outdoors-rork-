import Foundation
import CoreLocation
import HealthKit
import Observation

nonisolated enum HealthAuthorizationState: Equatable, Sendable {
    case unknown
    case unavailable
    case requesting
    case authorized
    case denied
}

/// Reads training and recovery data from Apple Health, and writes the workouts
/// this app records back into it.
///
/// Everything shown in the app comes from Health or from a session recorded on
/// this device. When Health has nothing for a metric the app shows an empty
/// state rather than inventing a number.
@Observable
final class HealthService {
    private(set) var snapshot: HealthSnapshot = .empty
    private(set) var authorization: HealthAuthorizationState = .unknown
    /// True once Apple Health has returned at least one real value.
    private(set) var hasHealthData = false
    private(set) var isLoading = false
    private(set) var healthActivities: [ActivityRecord] = []
    /// A year of daily values plus today by hour, backing the month/quarter/year charts.
    private(set) var history: MetricHistory = .empty
    /// Last error shown to the user after a failed write.
    private(set) var lastWriteError: String?

    /// Hourly breakdowns for past days the user has scrubbed back to, keyed by
    /// the start of that day. Today's hours live in `history`.
    private var hourlyByDay: [Date: [DashboardMetric: [Double]]] = [:]
    private var loadingDays: Set<Date> = []

    private let store = HealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Picks up where the last session left off without ever showing a
    /// permission sheet.
    ///
    /// HealthKit never reveals whether read access was granted, so the only
    /// honest question at launch is whether the sheet would still have anything
    /// left to ask. If it would not, access has already been answered and the
    /// app loads data instead of asking the user to connect all over again.
    func resume() async {
        guard isHealthDataAvailable else {
            authorization = .unavailable
            return
        }
        guard authorization != .requesting else { return }
        guard await store.hasBeenAsked() else { return }
        authorization = .authorized
        await refresh()
    }

    func requestAuthorization() async {
        guard isHealthDataAvailable else {
            authorization = .unavailable
            return
        }
        authorization = .requesting
        let granted = await store.requestAuthorization()
        authorization = granted ? .authorized : .denied
        if granted {
            await refresh()
        }
    }

    func refresh() async {
        guard isHealthDataAvailable, authorization == .authorized else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await store.loadSnapshot()
        if let loaded = result.snapshot {
            snapshot = loaded
            hasHealthData = true
        }
        healthActivities = result.activities

        let loadedHistory = await store.loadHistory()
        if loadedHistory.hasData {
            history = loadedHistory
            hasHealthData = true
        }
        // Yesterday's hours may already be cached from a previous day's session.
        hourlyByDay.removeAll()
    }

    // MARK: - Scrubbing to another day

    /// History scoped to one day: that day's hourly breakdown, plus the shared
    /// daily series every longer range is built from.
    func history(for date: Date) -> MetricHistory {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(date) else { return history }
        let key = calendar.startOfDay(for: date)
        return MetricHistory(hourly: hourlyByDay[key] ?? [:], daily: history.daily)
    }

    /// Pulls one past day's hourly breakdown on demand and caches it, so
    /// stepping back through the calendar stays instant after the first visit.
    func loadDay(_ date: Date) async {
        let calendar = Calendar.current
        guard isHealthDataAvailable, authorization == .authorized else { return }
        guard !calendar.isDateInToday(date) else { return }

        let key = calendar.startOfDay(for: date)
        guard hourlyByDay[key] == nil, !loadingDays.contains(key) else { return }

        loadingDays.insert(key)
        defer { loadingDays.remove(key) }
        hourlyByDay[key] = await store.loadHourly(for: key)
    }

    // MARK: - Writing back

    /// Saves a recorded session to Apple Health, including its GPS route, so it
    /// shows up alongside every other workout on the device.
    func save(_ activity: ActivityRecord) async {
        guard isHealthDataAvailable, authorization == .authorized else { return }
        do {
            try await store.save(activity)
            lastWriteError = nil
            await refresh()
        } catch {
            lastWriteError = "This workout was saved in Trekka but could not be written to Apple Health."
        }
    }
}

/// Isolated off the main actor so HealthKit queries never block the UI.
private actor HealthStore {
    private let store = HKHealthStore()

    // MARK: - Types

    /// Everything the app reads. Scoped to training, recovery and body metrics —
    /// Apple rejects apps that ask for health data they do not actually use.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.activitySummaryType(),
        ]
        for identifier in Self.readQuantities {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in Self.readCategories {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in Self.characteristics {
            if let type = HKCharacteristicType.characteristicType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Everything the app can write back.
    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        for identifier in Self.writeQuantities {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in Self.writeCategories {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    private static let readQuantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .walkingHeartRateAverage,
        .heartRateVariabilitySDNN, .heartRateRecoveryOneMinute,
        .vo2Max, .respiratoryRate, .oxygenSaturation,
        .activeEnergyBurned, .basalEnergyBurned,
        .appleExerciseTime, .appleStandTime, .appleMoveTime,
        .stepCount, .flightsClimbed,
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        .distanceDownhillSnowSports,
        .runningSpeed, .runningPower, .runningStrideLength,
        .runningVerticalOscillation, .runningGroundContactTime,
        .cyclingSpeed, .cyclingPower, .cyclingCadence,
        .walkingSpeed, .walkingStepLength, .appleWalkingSteadiness,
        .sixMinuteWalkTestDistance,
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .height,
        .dietaryWater,
    ]

    private static let writeQuantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
        .activeEnergyBurned, .basalEnergyBurned,
        .stepCount, .flightsClimbed,
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        .distanceDownhillSnowSports,
        .runningSpeed, .runningPower, .cyclingSpeed, .cyclingPower, .cyclingCadence,
        .bodyMass, .dietaryWater,
    ]

    private static let readCategories: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis, .mindfulSession, .appleStandHour,
    ]

    private static let writeCategories: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis, .mindfulSession,
    ]

    private static let characteristics: [HKCharacteristicTypeIdentifier] = [
        .dateOfBirth, .biologicalSex,
    ]

    func requestAuthorization() async -> Bool {
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// True when every type this app asks about has already been answered, so
    /// requesting again would show the user nothing new.
    func hasBeenAsked() async -> Bool {
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: shareTypes,
                read: readTypes
            )
            return status == .unnecessary
        } catch {
            return false
        }
    }

    // MARK: - Writing

    /// Writes a recorded session as a real `HKWorkout`, with its energy,
    /// distance and GPS route attached.
    func save(_ activity: ActivityRecord) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.activity.healthKitActivity
        configuration.locationType = .outdoor

        let start = activity.startDate
        let end = start.addingTimeInterval(max(1, activity.duration))
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if activity.calories > 0, let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: activity.calories),
                    start: start,
                    end: end
                )
            )
        }
        if activity.distance > 0,
           let type = HKQuantityType.quantityType(forIdentifier: activity.activity.distanceIdentifier) {
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .meter(), doubleValue: activity.distance),
                    start: start,
                    end: end
                )
            )
        }
        if activity.averageHeartRate > 0, let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(
                        unit: HKUnit.count().unitDivided(by: .minute()),
                        doubleValue: activity.averageHeartRate
                    ),
                    start: start,
                    end: end
                )
            )
        }
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        if activity.elevationGain > 0 {
            try await builder.addMetadata([
                HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: activity.elevationGain)
            ])
        }

        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()

        guard let workout else { return }
        try await attachRoute(from: activity, to: workout)
    }

    /// Attaches the recorded track so the workout shows a real map in Health.
    private func attachRoute(from activity: ActivityRecord, to workout: HKWorkout) async throws {
        let locations = activity.track.compactMap { point -> CLLocation? in
            // Only points captured live carry a timestamp; anything else would
            // put a guessed time on the map, so it is left out.
            guard let timestamp = point.timestamp else { return nil }
            return CLLocation(
                coordinate: point.coordinate,
                altitude: point.elevation,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: timestamp
            )
        }
        guard locations.count > 1 else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await routeBuilder.insertRouteData(locations)
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    // MARK: - Reading

    struct LoadResult: Sendable {
        var snapshot: HealthSnapshot?
        var activities: [ActivityRecord]
    }

    func loadSnapshot() async -> LoadResult {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        async let hrvValue = average(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), start: weekAgo, end: now)
        async let hrvBaselineValue = average(
            .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            start: calendar.date(byAdding: .day, value: -30, to: now) ?? weekAgo,
            end: now
        )
        async let vo2Value = mostRecent(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let caloriesValue = sum(.activeEnergyBurned, unit: .kilocalorie(), start: startOfToday, end: now)
        async let stepsValue = sum(.stepCount, unit: .count(), start: startOfToday, end: now)
        async let restingValue = average(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: weekAgo, end: now)
        async let sleepValue = lastNightSleep()
        async let workoutList = workouts(since: calendar.date(byAdding: .day, value: -365, to: now) ?? weekAgo)

        async let caloriesSeries = dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: 7)
        async let stepsSeries = dailySeries(.stepCount, unit: .count(), days: 7)
        async let hrvSeries = dailyAverageSeries(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), days: 7)
        async let restingSeries = dailyAverageSeries(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 7)
        async let vo2Series = dailyAverageSeries(.vo2Max, unit: HKUnit(from: "ml/kg*min"), days: 7)
        async let sleepSeries = dailySleepSeries(days: 7)

        let breathsPerMinute = HKUnit.count().unitDivided(by: .minute())
        async let exerciseValue = sum(.appleExerciseTime, unit: .minute(), start: startOfToday, end: now)
        async let flightsValue = sum(.flightsClimbed, unit: .count(), start: startOfToday, end: now)
        async let respiratoryValue = average(.respiratoryRate, unit: breathsPerMinute, start: weekAgo, end: now)
        async let bodyMassValue = mostRecent(.bodyMass, unit: .gramUnit(with: .kilo))
        async let exerciseSeries = dailySeries(.appleExerciseTime, unit: .minute(), days: 7)
        async let flightsSeries = dailySeries(.flightsClimbed, unit: .count(), days: 7)
        async let respiratorySeries = dailyAverageSeries(.respiratoryRate, unit: breathsPerMinute, days: 7)
        async let bodyMassSeries = dailyAverageSeries(.bodyMass, unit: .gramUnit(with: .kilo), days: 7)

        let hrv = await hrvValue ?? 0
        let hrvBaseline = await hrvBaselineValue ?? hrv
        let vo2 = await vo2Value ?? 0
        let calories = await caloriesValue ?? 0
        let steps = await stepsValue ?? 0
        let resting = await restingValue ?? 0
        let sleep = await sleepValue
        let activities = await workoutList

        let hasAnyData = hrv > 0 || vo2 > 0 || calories > 0 || steps > 0 || sleep > 0 || !activities.isEmpty
        guard hasAnyData else { return LoadResult(snapshot: nil, activities: activities) }

        let load = trainingLoad(from: activities)
        let sleepScore = sleepScore(for: sleep)
        let readiness = ReadinessCalculator.score(
            sleepSeconds: sleep,
            sleepScore: sleepScore,
            hrv: hrv,
            hrvBaseline: hrvBaseline,
            load: load
        )

        var zoneTotals: [Double] = [0, 0, 0, 0, 0]
        let weekCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? weekAgo
        for activity in activities where activity.startDate >= weekCutoff {
            for index in 0..<5 where activity.zoneMinutes.indices.contains(index) {
                zoneTotals[index] += activity.zoneMinutes[index]
            }
        }

        let loadSeries = weeklyLoadSeries(from: activities)
        let snapshot = HealthSnapshot(
            readiness: readiness,
            readinessCaption: ReadinessCalculator.caption(for: readiness),
            sleepSeconds: sleep,
            sleepScore: sleepScore,
            hrv: hrv,
            hrvBaseline: hrvBaseline,
            vo2Max: vo2,
            trainingLoad: load,
            activeCalories: calories,
            steps: Int(steps),
            restingHeartRate: resting,
            exerciseMinutes: await exerciseValue ?? 0,
            flightsClimbed: await flightsValue ?? 0,
            respiratoryRate: await respiratoryValue ?? 0,
            bodyMass: await bodyMassValue ?? 0,
            sleepTrend: await sleepSeries,
            hrvTrend: await hrvSeries,
            vo2Trend: Self.forwardFilled(await vo2Series, seed: vo2),
            loadTrend: loadSeries,
            caloriesTrend: await caloriesSeries,
            stepsTrend: await stepsSeries,
            restingTrend: Self.forwardFilled(await restingSeries, seed: resting),
            exerciseTrend: await exerciseSeries,
            flightsTrend: await flightsSeries,
            respiratoryTrend: await respiratorySeries,
            // Weight is only recorded now and then, so the gaps carry the last
            // known reading forward rather than plotting a drop to zero.
            bodyMassTrend: Self.forwardFilled(await bodyMassSeries),
            zoneMinutes: zoneTotals
        )
        return LoadResult(snapshot: snapshot, activities: activities)
    }

    // MARK: - Long-window history

    /// Reads a year of daily values and today's hourly breakdown in one pass.
    ///
    /// Uses statistics collections rather than a query per day so a year of
    /// history costs one round trip per metric.
    func loadHistory() async -> MetricHistory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = MetricSeries.historyDayCount
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return .empty }

        let daily = DateComponents(day: 1)
        let millisecond = HKUnit.secondUnit(with: .milli)
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        async let stepsDaily = collection(.stepCount, unit: .count(), options: .cumulativeSum, start: start, end: end, interval: daily)
        async let caloriesDaily = collection(.activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: end, interval: daily)
        async let hrvDaily = collection(.heartRateVariabilitySDNN, unit: millisecond, options: .discreteAverage, start: start, end: end, interval: daily)
        async let restingDaily = collection(.restingHeartRate, unit: beatsPerMinute, options: .discreteAverage, start: start, end: end, interval: daily)
        async let vo2Daily = collection(.vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage, start: start, end: end, interval: daily)
        async let sleepSamples = sleepIntervals(start: start, end: end)
        async let todayHours = loadHourly(for: today)

        let breathsPerMinute = HKUnit.count().unitDivided(by: .minute())
        async let exerciseDaily = collection(.appleExerciseTime, unit: .minute(), options: .cumulativeSum, start: start, end: end, interval: daily)
        async let flightsDaily = collection(.flightsClimbed, unit: .count(), options: .cumulativeSum, start: start, end: end, interval: daily)
        async let respiratoryDaily = collection(.respiratoryRate, unit: breathsPerMinute, options: .discreteAverage, start: start, end: end, interval: daily)
        async let bodyMassDaily = collection(.bodyMass, unit: .gramUnit(with: .kilo), options: .discreteAverage, start: start, end: end, interval: daily)

        let sleep = await sleepSamples
        var dailyValues: [DashboardMetric: [Double]] = [
            .steps: daySeries(await stepsDaily, days: days, today: today, calendar: calendar),
            .calories: daySeries(await caloriesDaily, days: days, today: today, calendar: calendar),
            .hrv: daySeries(await hrvDaily, days: days, today: today, calendar: calendar),
            .restingHeartRate: Self.forwardFilled(daySeries(await restingDaily, days: days, today: today, calendar: calendar)),
            .vo2Max: Self.forwardFilled(daySeries(await vo2Daily, days: days, today: today, calendar: calendar)),
            .sleep: sleepDaySeries(sleep, days: days, today: today, calendar: calendar),
            .exercise: daySeries(await exerciseDaily, days: days, today: today, calendar: calendar),
            .flights: daySeries(await flightsDaily, days: days, today: today, calendar: calendar),
            .respiratoryRate: daySeries(await respiratoryDaily, days: days, today: today, calendar: calendar),
            .bodyMass: Self.forwardFilled(daySeries(await bodyMassDaily, days: days, today: today, calendar: calendar)),
        ]
        dailyValues = dailyValues.filter { _, values in values.contains { $0 > 0 } }

        return MetricHistory(hourly: await todayHours, daily: dailyValues)
    }

    /// One day broken into hours, for the Day range on any date.
    func loadHourly(for day: Date) async -> [DashboardMetric: [Double]] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }

        let hour = DateComponents(hour: 1)
        let millisecond = HKUnit.secondUnit(with: .milli)

        async let steps = collection(.stepCount, unit: .count(), options: .cumulativeSum, start: start, end: end, interval: hour)
        async let calories = collection(.activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: end, interval: hour)
        async let hrv = collection(.heartRateVariabilitySDNN, unit: millisecond, options: .discreteAverage, start: start, end: end, interval: hour)
        // Flights and exercise minutes are read by the hour as well, not just by
        // the day. The Day range builds its number purely from these hourly
        // buckets, and both metrics are cumulative, so leaving them out here did
        // not merely coarsen the chart — it totalled their hours to zero and the
        // tile read "--" all day. The flat-line fallback below only covers
        // averaged metrics (resting HR, weight), so it never caught these two.
        async let flights = collection(.flightsClimbed, unit: .count(), options: .cumulativeSum, start: start, end: end, interval: hour)
        async let exercise = collection(.appleExerciseTime, unit: .minute(), options: .cumulativeSum, start: start, end: end, interval: hour)

        // Sleep does not live inside a calendar day. A night that starts at 23:30
        // and ends at 07:00 only has seven of its hours after midnight, so a
        // midnight-to-now window silently threw away the time actually spent in
        // bed the evening before. The night window opens at 18:00 the previous
        // evening and closes at 18:00 on the day itself — the same 18:00 split
        // the Health app files nights under, so the totals agree.
        let nightStart = calendar.date(byAdding: .hour, value: -6, to: start) ?? start
        let nightEnd = calendar.date(byAdding: .hour, value: 18, to: start) ?? end
        async let sleep = sleepIntervals(start: nightStart, end: nightEnd)

        var values: [DashboardMetric: [Double]] = [
            .steps: hourSeries(await steps, today: start, calendar: calendar),
            .calories: hourSeries(await calories, today: start, calendar: calendar),
            .hrv: hourSeries(await hrv, today: start, calendar: calendar),
            .flights: hourSeries(await flights, today: start, calendar: calendar),
            .exercise: hourSeries(await exercise, today: start, calendar: calendar),
            .sleep: sleepHourSeries(await sleep, axisStart: nightStart, calendar: calendar),
        ]
        values = values.filter { _, series in series.contains { $0 > 0 } }
        return values
    }

    private func collection(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date,
        interval: DateComponents
    ) async -> [(Date, Double)] {
        guard let type = quantityType(identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }
                var output: [(Date, Double)] = []
                results.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    if let value = quantity?.doubleValue(for: unit), value > 0 {
                        output.append((statistics.startDate, value))
                    }
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }

    private func daySeries(_ pairs: [(Date, Double)], days: Int, today: Date, calendar: Calendar) -> [Double] {
        var series = [Double](repeating: 0, count: days)
        for (date, value) in pairs {
            guard let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day,
                  offset >= 0, offset < days else { continue }
            series[days - 1 - offset] += value
        }
        return series
    }

    private func hourSeries(_ pairs: [(Date, Double)], today: Date, calendar: Calendar) -> [Double] {
        var series = [Double](repeating: 0, count: 24)
        for (date, value) in pairs {
            guard calendar.isDate(date, inSameDayAs: today) else { continue }
            let hour = calendar.component(.hour, from: date)
            guard series.indices.contains(hour) else { continue }
            series[hour] += value
        }
        return series
    }

    /// Sparse metrics only sample every few days; carry the last value forward.
    private static func forwardFilled(_ series: [Double]) -> [Double] {
        guard series.contains(where: { $0 > 0 }) else { return series }
        var last: Double = 0
        var filled: [Double] = []
        for value in series {
            if value > 0 { last = value }
            filled.append(last)
        }
        return filled
    }

    /// Every asleep interval overlapping the window, clipped to it and merged.
    ///
    /// Three things here decide whether the total matches the Health app:
    ///
    /// - No `strictStartDate`. That option drops a sample that began before the
    ///   window opened, so a night starting at 23:00 vanished entirely from a
    ///   window that opened at 01:00 — hours of real sleep, silently gone.
    /// - Intervals are clipped to the window rather than counted whole, so the
    ///   part that falls outside is not credited to it.
    /// - Overlapping intervals are merged. Apple Watch, iPhone and any
    ///   third-party sleep app all write their own samples for the same night;
    ///   adding them up counts the same minutes two or three times over.
    private func sleepIntervals(start: Date, end: Date) async -> [(Date, Date)] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let raw: [(Date, Date)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let intervals = (samples as? [HKCategorySample])?
                    .filter { asleepValues.contains($0.value) }
                    .map { (max($0.startDate, start), min($0.endDate, end)) }
                    .filter { $0.1 > $0.0 } ?? []
                continuation.resume(returning: intervals)
            }
            store.execute(query)
        }
        return Self.merged(raw)
    }

    /// Collapses overlapping intervals into their union.
    private static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var result: [(Date, Date)] = [sorted[0]]
        for interval in sorted.dropFirst() {
            let last = result[result.count - 1]
            if interval.0 <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The morning a sleep interval belongs to.
    ///
    /// Health files a night under the day you woke up on, splitting at 18:00.
    /// Using the same rule keeps this app's nightly totals lined up with the
    /// Health app instead of drifting by hours depending on the clock.
    private static func nightKey(for end: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: end)
        let hour = calendar.component(.hour, from: end)
        guard hour >= 18 else { return dayStart }
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    /// Time asleep for the night that most recently ended.
    private func lastNightSleep() async -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        // Reach back far enough to catch a night that began the previous
        // evening, plus a full day in case the last sleep was not last night.
        guard let windowStart = calendar.date(byAdding: .hour, value: -60, to: now) else { return 0 }
        let intervals = await sleepIntervals(start: windowStart, end: now)
        guard let latest = intervals.last else { return 0 }

        let night = Self.nightKey(for: latest.1, calendar: calendar)
        return intervals
            .filter { Self.nightKey(for: $0.1, calendar: calendar) == night }
            .reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
    }

    /// Nightly totals in hours, attributed to the morning the night ended on.
    private func sleepDaySeries(_ intervals: [(Date, Date)], days: Int, today: Date, calendar: Calendar) -> [Double] {
        var series = [Double](repeating: 0, count: days)
        for (start, end) in intervals {
            let night = Self.nightKey(for: end, calendar: calendar)
            guard let offset = calendar.dateComponents([.day], from: night, to: today).day,
                  offset >= 0, offset < days else { continue }
            series[days - 1 - offset] += end.timeIntervalSince(start) / 3600
        }
        return series
    }

    /// Hours asleep inside each hour of the night — reads as a hypnogram-style
    /// bar chart. Index 0 is `axisStart`, which for a night is 18:00 the evening
    /// before, not midnight.
    private func sleepHourSeries(_ intervals: [(Date, Date)], axisStart: Date, calendar: Calendar) -> [Double] {
        var series = [Double](repeating: 0, count: 24)
        for hour in 0..<24 {
            guard let bucketStart = calendar.date(byAdding: .hour, value: hour, to: axisStart),
                  let bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart) else { continue }
            for (start, end) in intervals {
                let overlap = min(end, bucketEnd).timeIntervalSince(max(start, bucketStart))
                if overlap > 0 { series[hour] += overlap / 3600 }
            }
        }
        return series
    }

    // MARK: - Derived values

    /// Sparse metrics (VO₂ max, resting HR) are only sampled every few days;
    /// carry the last known value forward so charts stay readable.
    private static func forwardFilled(_ series: [Double], seed: Double) -> [Double] {
        guard series.contains(where: { $0 > 0 }) || seed > 0 else { return [] }
        var last = seed
        var filled: [Double] = []
        for value in series {
            if value > 0 { last = value }
            filled.append(last)
        }
        return filled
    }

    private func sleepScore(for seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        let hours = seconds / 3600
        return max(20, min(100, Int((hours / 8.0 * 92).rounded())))
    }

    private func trainingLoad(from activities: [ActivityRecord]) -> Int {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recent = activities.filter { $0.startDate >= cutoff }
        let load = recent.reduce(0.0) { partial, activity in
            let intensity = max(1.0, activity.averageHeartRate / 100)
            return partial + (activity.duration / 60) * intensity
        }
        return Int(load.rounded())
    }

    private func weeklyLoadSeries(from activities: [ActivityRecord]) -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return activities
                .filter { $0.startDate >= day && $0.startDate < next }
                .reduce(0.0) { $0 + ($1.duration / 60) * max(1.0, $1.averageHeartRate / 100) }
        }
    }

    // MARK: - Queries

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: identifier)
    }

    private func statistic(
        _ identifier: HKQuantityTypeIdentifier,
        options: HKStatisticsOptions,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let type = quantityType(identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, _ in
                let quantity = options.contains(.cumulativeSum)
                    ? statistics?.sumQuantity()
                    : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        await statistic(identifier, options: .cumulativeSum, unit: unit, start: start, end: end)
    }

    private func average(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        await statistic(identifier, options: .discreteAverage, unit: unit, start: start, end: end)
    }

    private func mostRecent(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = quantityType(identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func dailySeries(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var series: [Double] = []
        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            series.append(await sum(identifier, unit: unit, start: day, end: next) ?? 0)
        }
        return series
    }

    private func dailyAverageSeries(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var series: [Double] = []
        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            series.append(await average(identifier, unit: unit, start: day, end: next) ?? 0)
        }
        return series
    }

    /// Nightly sleep totals in hours, oldest first.
    ///
    /// Read in one pass and bucketed by the night each interval ends on. The
    /// per-night windows this used to query overlapped each other, so a long
    /// night was counted against two days at once.
    private func dailySleepSeries(days: Int) async -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days + 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let intervals = await sleepIntervals(start: start, end: end)
        return sleepDaySeries(intervals, days: days, today: today, calendar: calendar)
    }

    private func workouts(since date: Date) async -> [ActivityRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: Date(), options: .strictStartDate)
        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 200,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        return samples.map { workout in
            let type: RouteActivityType = switch workout.workoutActivityType {
            case .cycling: .ride
            case .hiking, .walking: .hike
            default: .run
            }
            let distance = workout.statistics(for: HKQuantityType(type.distanceIdentifier))?
                .sumQuantity()?
                .doubleValue(for: .meter()) ?? 0
            let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0
            let heartRate = workout.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            let ascent = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
                .doubleValue(for: .meter()) ?? 0

            var zoneMinutes: [Double] = [0, 0, 0, 0, 0]
            if heartRate > 0 {
                zoneMinutes[Formatters.zone(forHeartRate: heartRate) - 1] = workout.duration / 60
            }
            return ActivityRecord(
                name: title(for: workout.workoutActivityType, date: workout.startDate),
                activity: type,
                startDate: workout.startDate,
                duration: workout.duration,
                distance: distance,
                elevationGain: ascent,
                averageHeartRate: heartRate,
                calories: calories,
                trainingEffect: min(5, workout.duration / 1_800),
                track: [],
                zoneMinutes: zoneMinutes
            )
        }
    }

    private func title(for type: HKWorkoutActivityType, date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let period = switch hour {
        case 4..<11: "Morning"
        case 11..<15: "Midday"
        case 15..<19: "Afternoon"
        default: "Evening"
        }
        let noun = switch type {
        case .cycling: "Ride"
        case .hiking: "Hike"
        case .walking: "Walk"
        case .running: "Run"
        default: "Workout"
        }
        return "\(period) \(noun)"
    }
}

nonisolated extension RouteActivityType {
    var healthKitActivity: HKWorkoutActivityType {
        switch self {
        case .run: .running
        case .ride: .cycling
        case .hike: .hiking
        }
    }

    /// The distance type Health records this activity against.
    var distanceIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .ride: .distanceCycling
        case .run, .hike: .distanceWalkingRunning
        }
    }
}
