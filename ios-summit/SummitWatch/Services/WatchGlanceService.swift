import Foundation
import Observation
import HealthKit

/// Reads the overnight recovery numbers the glance screen shows.
///
/// Everything starts empty and only fills in from Apple Health, so the wrist
/// never shows a number the athlete did not earn.
@Observable
final class WatchGlanceService {
    private(set) var readiness: Int = 0
    private(set) var sleepSeconds: TimeInterval = 0
    private(set) var hrv: Double = 0
    private(set) var hrvBaseline: Double = 0
    private(set) var restingHeartRate: Double = 0
    private(set) var trainingLoad: Int = 0
    /// True once Health has returned at least one real reading.
    private(set) var hasHealthData = false

    private let store = HKHealthStore()

    var sleepText: String {
        let hours = Int(sleepSeconds) / 3600
        let minutes = (Int(sleepSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var caption: String {
        switch readiness {
        case 85...100: "Peaking — chase a personal best"
        case 70..<85: "Primed — go hard today"
        case 50..<70: "Steady — moderate effort suits you"
        case 30..<50: "Strained — keep it aerobic"
        case 1..<30: "Depleted — prioritise recovery"
        default: "No Health data yet"
        }
    }

    var suggestion: String {
        switch readiness {
        case 85...100: "Threshold intervals or a hard climb. Your body can absorb it."
        case 70..<85: "A solid tempo effort — 40 to 60 minutes in zone 3."
        case 50..<70: "Easy aerobic hour. Keep your heart rate under zone 3."
        case 30..<50: "Zone 2 only, or walk it. Skip the intervals today."
        case 1..<30: "Rest, mobility or a gentle walk. Nothing structured."
        default: "Grant Health access on iPhone to get a readiness score."
        }
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: Set<HKObjectType> = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
        ]
        guard (try? await store.requestAuthorization(toShare: [], read: types)) != nil else { return }

        async let hrvValue = latestQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli))
        async let restingValue = latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let baselineValue = averageQuantity(
            .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            days: 30
        )
        async let sleepValue = lastNightSleep()

        let (measuredHRV, measuredResting) = await (hrvValue, restingValue)
        var didRead = false

        if let measuredHRV, measuredHRV > 0 {
            hrv = measuredHRV
            didRead = true
        }
        if let measuredResting, measuredResting > 0 {
            restingHeartRate = measuredResting
            // Heart rate reserve needs the heart's real floor, and this is the
            // one place that reads it. Published so a workout can score effort
            // against the measured range rather than an assumed one.
            LiveMetrics.restingHeartRateFloor = measuredResting
            didRead = true
        }
        if let baseline = await baselineValue, baseline > 0 {
            hrvBaseline = baseline
        }
        let sleep = await sleepValue
        if sleep > 0 {
            sleepSeconds = sleep
            didRead = true
        }

        if didRead {
            hasHealthData = true
            recomputeReadiness()
        }
    }

    private func recomputeReadiness() {
        let sleepHours = sleepSeconds / 3600
        let sleepComponent = min(1.0, sleepHours / 8.0) * 40
        let ratio = hrvBaseline > 0 ? min(1.4, hrv / hrvBaseline) : 1.0
        let hrvComponent = min(1.0, ratio / 1.1) * 35
        let loadPenalty = max(0, Double(trainingLoad) - 500) / 500 * 20
        let raw = sleepComponent + hrvComponent + 15 + 10 - loadPenalty
        readiness = max(1, min(100, Int(raw.rounded())))
    }

    /// Total time asleep in the last 20 hours — last night, in practice.
    private func lastNightSleep() async -> TimeInterval {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Date().addingTimeInterval(-20 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let total = (samples as? [HKCategorySample])?
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        let type = HKQuantityType(identifier)
        let start = Date().addingTimeInterval(-Double(days) * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(identifier)
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
}
