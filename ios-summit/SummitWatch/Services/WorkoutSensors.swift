import Foundation
import CoreLocation
import HealthKit

/// A location reading reduced to plain values so it can cross isolation
/// boundaries without any Sendable gymnastics.
nonisolated struct GeoFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var course: Double
    var horizontalAccuracy: Double
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension WatchSport {
    /// The Health activity each sport is filed under.
    ///
    /// Health has no type for some of these (there is no bikepacking), so the
    /// closest true parent is used — the session is still a real ride.
    var healthKitActivity: HKWorkoutActivityType {
        switch self {
        case .trailRun, .roadRun, .ultraRun, .track, .treadmill, .virtualRun: .running
        case .ride, .gravelRide, .mountainBike, .bikepacking, .eBike, .commute, .indoorRide: .cycling
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
        case .soccer: .soccer
        case .basketball: .basketball
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .golf: .golf
        case .discGolf: .discSports
        case .skateboard: .skatingSports
        case .horseback: .equestrianSports
        case .hunt: .hunting
        case .fish: .fishing
        }
    }
}

/// Bridges CoreLocation and the HealthKit workout session into simple callbacks.
///
/// The engine owns the maths; this type only delivers raw readings and reports
/// whether each sensor is actually live so the UI can be honest about it.
final class WorkoutSensors: NSObject, CLLocationManagerDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var onFix: ((GeoFix) -> Void)?
    var onHeartRate: ((Double) -> Void)?
    var onEnergy: ((Double) -> Void)?
    var onDistance: ((Double) -> Void)?
    /// Steps or crank revolutions per minute, straight from the sensor.
    var onCadence: ((Double) -> Void)?
    /// Running or cycling power in watts, straight from the sensor.
    var onPower: ((Double) -> Void)?
    /// Cumulative step count, from which running cadence is derived.
    var onStepTotal: ((Double) -> Void)?

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var dataSource: HKLiveWorkoutDataSource?
    private var isPowerSaving = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5
    }

    var isLocationAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Asks for the workout and recovery types the watch records and reads.
    /// Failure is non-fatal — the session still records locally.
    func requestHealthAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        var share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        for identifier in Self.workoutQuantities {
            share.insert(HKQuantityType(identifier))
        }

        var read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKCategoryType(.sleepAnalysis),
        ]
        for identifier in Self.workoutQuantities + Self.recoveryQuantities {
            read.insert(HKQuantityType(identifier))
        }

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// Recorded during a session, so they are both written and read back.
    private static let workoutQuantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .activeEnergyBurned, .basalEnergyBurned,
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        .distanceDownhillSnowSports, .stepCount, .flightsClimbed,
        .runningSpeed, .runningPower, .cyclingSpeed, .cyclingPower, .cyclingCadence,
    ]

    /// Recovery types the watch only reads.
    private static let recoveryQuantities: [HKQuantityTypeIdentifier] = [
        .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
        .respiratoryRate, .oxygenSaturation, .appleExerciseTime,
    ]

    // MARK: - Lifecycle

    func start(sport: WatchSport, isPowerSaving: Bool) async {
        self.isPowerSaving = isPowerSaving
        if sport.usesGPS {
            locationManager.requestWhenInUseAuthorization()
            applyLocationPowerMode()
            locationManager.startUpdatingLocation()
        }
        await startWorkoutSession(sport: sport)
    }

    /// Turns the two heaviest sensors up or down mid-workout.
    ///
    /// GPS drops to a coarser duty cycle and heart rate collection genuinely
    /// stops, which is what actually buys the extra hours.
    func setPowerSaving(_ enabled: Bool) {
        guard isPowerSaving != enabled else { return }
        isPowerSaving = enabled
        applyLocationPowerMode()

        let heartRate = HKQuantityType(.heartRate)
        if enabled {
            dataSource?.disableCollection(for: heartRate)
        } else {
            dataSource?.enableCollection(for: heartRate, predicate: nil)
        }
    }

    private func applyLocationPowerMode() {
        locationManager.desiredAccuracy = isPowerSaving
            ? kCLLocationAccuracyHundredMeters
            : kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = isPowerSaving ? 25 : 5
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func stop() async {
        locationManager.stopUpdatingLocation()
        dataSource = nil
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        _ = try? await builder.finishWorkout()
        self.session = nil
        self.builder = nil
    }

    /// Discards the in-flight workout without writing it to Health.
    func discard() async {
        locationManager.stopUpdatingLocation()
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        dataSource = nil
    }

    private func startWorkoutSession(sport: WatchSport) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sport.healthKitActivity
        configuration.locationType = sport.isIndoor ? .indoor : .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            if isPowerSaving {
                source.disableCollection(for: HKQuantityType(.heartRate))
            }
            builder.dataSource = source
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.dataSource = source

            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
        } catch {
            session = nil
            builder = nil
            dataSource = nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes: [GeoFix] = locations.map { location in
            GeoFix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                // Kept raw: CoreLocation reports a negative speed when it has
                // none to give, and flattening that to zero would look like a
                // genuine standstill.
                speed: location.speed,
                course: location.course,
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The engine owns the quality thresholds, so that judgement lives
            // in exactly one place.
            for fix in fixes where fix.horizontalAccuracy > 0 {
                onFix?(fix)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected in canyons and forest; the engine
        // keeps running on its last known fix.
    }

    // MARK: - HKWorkoutSessionDelegate

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    // MARK: - HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var heartRate: Double?
        var energy: Double?
        var distance: Double?
        var cadence: Double?
        var power: Double?

        let perMinute = HKUnit.count().unitDivided(by: .minute())

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

            switch quantityType {
            case HKQuantityType(.heartRate):
                heartRate = statistics.mostRecentQuantity()?.doubleValue(for: perMinute)
            case HKQuantityType(.activeEnergyBurned):
                energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityType(.distanceWalkingRunning),
                HKQuantityType(.distanceCycling),
                HKQuantityType(.distanceSwimming),
                HKQuantityType(.distanceDownhillSnowSports):
                distance = statistics.sumQuantity()?.doubleValue(for: .meter())
            case HKQuantityType(.cyclingCadence):
                // Crank revolutions per minute, measured by a paired sensor.
                cadence = statistics.mostRecentQuantity()?.doubleValue(for: perMinute)
            case HKQuantityType(.stepCount):
                // Steps are cumulative, so cadence is the rate of change. The
                // engine turns the running total into steps per minute.
                if let steps = statistics.sumQuantity()?.doubleValue(for: .count()) {
                    Task { @MainActor [weak self] in self?.onStepTotal?(steps) }
                }
            case HKQuantityType(.runningPower), HKQuantityType(.cyclingPower):
                power = statistics.mostRecentQuantity()?.doubleValue(for: .watt())
            default:
                continue
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let heartRate { onHeartRate?(heartRate) }
            if let energy { onEnergy?(energy) }
            if let distance { onDistance?(distance) }
            if let cadence { onCadence?(cadence) }
            if let power { onPower?(power) }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
