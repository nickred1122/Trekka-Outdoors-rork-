import Foundation
import Observation
import CoreLocation
import WatchKit

/// The live workout state machine: sensors in, metrics out.
///
/// Every number here comes from a sensor. GPS drives distance, speed, altitude
/// and the breadcrumb trail; HealthKit drives heart rate, energy, cadence and
/// power. Nothing is modelled, inferred or filled in: when a sensor has not
/// reported, its metric stays at zero and the page prints `--`. A workout is a
/// record of what happened, and a plausible guess is indistinguishable from a
/// lie once it has been saved.
@Observable
final class WorkoutEngine {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        /// Precise start: sensors are running but the clock has not, because the
        /// receiver has yet to produce a fix worth recording against.
        case acquiring
        case active
        case paused
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var sport: WatchSport = .trailRun
    private(set) var route: WatchRoute?
    private(set) var metrics = LiveMetrics()
    private(set) var laps: [WatchLap] = []
    private(set) var track: [WatchTrackPoint] = []
    private(set) var isGPSLive = false
    private(set) var gpsBars = 0
    private(set) var isAutoPaused = false
    private(set) var lastLapBanner: String?
    /// How the workout began, shown for a few seconds once it has. Precise start
    /// otherwise takes the screen and hands it back with nothing said.
    private(set) var startBanner: String?
    /// Whether recording began on a fix worth trusting, so the banner can be
    /// honest about which of the two happened.
    private(set) var startedWithPreciseFix = false

    /// The way back to the course, recalculated while off route.
    private(set) var reroute: RerouteAdvice?
    /// Transient navigation callout: off course, waypoint reached, back on route.
    private(set) var navigationBanner: String?

    /// Power saver: the sensors are genuinely turned down, not just the UI.
    private(set) var isPowerSaving = false
    private(set) var didAutoArmPowerSaver = false
    private(set) var powerBanner: String?
    private(set) var isWaterLocked = false

    /// Set by the app root so a finished workout joins the watch's own history.
    var onFinishedWorkout: ((ActivityTransfer) -> Void)?

    /// Every position the workout actually reached, for the breadcrumb trail.
    var onLocation: ((CLLocationCoordinate2D, Double) -> Void)?
    /// Breadcrumb recording lifecycle, wired to the trail store by the app root.
    var onRecordingBegan: ((WatchSport) -> Void)?
    var onRecordingEnded: ((WatchSport, String) -> Void)?
    var onRecordingDiscarded: (() -> Void)?

    var currentCoordinate: CLLocationCoordinate2D?
    var heading: Double = 0

    private let sensors = WorkoutSensors()
    private var ticker: Task<Void, Never>?
    private var lastFix: GeoFix?
    private var lastHeartRateAt: Date?
    private var heartRateSamples: Int = 0
    private var heartRateSum: Double = 0
    private var cadenceSum: Double = 0
    private var cadenceSamples: Int = 0
    private var lapHeartRateSum: Double = 0
    private var lapHeartRateSamples: Int = 0
    private var lapStartAscent: Double = 0
    private var stillSeconds: Int = 0
    /// Elevation the ascent counter is currently measured against. Only moves
    /// once a climb or descent clears the noise threshold.
    private var ascentAnchor: Double = 0
    /// When the last usable fix arrived, so a receiver that goes quiet is
    /// treated as silence rather than as a held speed.
    private var lastFixAt: Date?
    /// Consecutive fixes that landed inside the noise floor.
    private var stationaryFixes: Int = 0
    /// True once a fix has arrived that is accurate enough to record distance
    /// against, which is what precise start waits for.
    private var hasTrustedFix = false
    /// Seconds the clock was stopped, whether by hand or by auto-pause.
    private var pausedSeconds: TimeInterval = 0
    private var pauseBeganAt: Date?
    /// Timestamp of the fix the altitude filter last accepted.
    private var lastAltitudeAt: Date?
    /// Previous cumulative step reading, for deriving running cadence.
    private var lastStepTotal: Double?
    private var lastStepTotalAt: Date?
    /// Previous cumulative stroke reading, for deriving swim stroke rate.
    private var lastStrokeTotal: Double?
    private var lastStrokeTotalAt: Date?
    /// When the length in progress began, and the stroke count it started from.
    private var lastLengthAt: Date?
    private var strokesAtLastLength: Double = 0
    /// Battery readings taken in each mode, kept apart so the benefit of power
    /// saver can be measured rather than assumed.
    private var normalSamples: [PowerBudget.Sample] = []
    private var savingSamples: [PowerBudget.Sample] = []
    private var settings: WatchScreenSettings?
    private var tickCount: Int = 0
    /// Set when the athlete switches power saver off by hand, so the battery
    /// threshold does not immediately switch it back on behind their back.
    private var didOverridePowerSaver = false
    /// Stamp of the last power-saver request honoured from the watch face.
    private var lastFaceRequestAt: Date?

    // Navigation alerting state.
    private var offCourseSince: Date?
    private var lastOffCourseAlertAt: Date?
    private var lastRerouteAt: Date?
    /// Where sun times were last computed, so they refresh on travel rather
    /// than on every fix — the answer moves a second of arc per kilometre.
    private var solarAnchor: CLLocationCoordinate2D?
    /// Where recording actually began, for the straight line home.
    private var startCoordinate: CLLocationCoordinate2D?
    private var announcedApproachIDs: Set<UUID> = []
    private var announcedArrivalIDs: Set<UUID> = []

    /// Quality gates every GPS reading has to clear before it is allowed to
    /// move a number the athlete will later trust.
    ///
    /// Consumer GPS wanders by several metres even when the watch is sitting
    /// still on a table. Without these thresholds a lunch break quietly adds a
    /// kilometre, and a workout under tree cover reads as a personal best.
    private enum Fix {
        /// Looser than this and the reading cannot tell a path from a field.
        static let worstAccuracy: Double = 50
        /// Good enough to move the odometer, not just the map pin.
        static let trustedAccuracy: Double = 25
        /// A step has to clear this fraction of its own error estimate before
        /// it counts as travel rather than drift.
        static let jitterFactor: Double = 0.6
        /// Fixes the receiver has been sitting on say nothing about now.
        static let staleness: TimeInterval = 5
        /// Faster than this, in metres per second, and the fix jumped rather
        /// than travelled — roughly 160 km/h.
        static let maxSpeed: Double = 45
        /// Sustained vertical change, in metres, before ascent is credited.
        static let ascentThreshold: Double = 3
        /// No fix for this long and the speed reading has gone stale.
        static let speedTimeout: TimeInterval = 6
        /// No fix for this long and GPS is no longer live.
        static let signalTimeout: TimeInterval = 20
        /// How long precise start waits before it takes over the screen.
        ///
        /// A receiver that is already warm reports within a second, and putting
        /// a "waiting for a fix" screen up for that flicker reads as a glitch
        /// rather than as care. Past this, the wait is real and worth showing.
        static let acquiringGrace: TimeInterval = 1.5
    }

    /// Thresholds for course alerts, in metres and seconds.
    private enum Navigation {
        /// How far off the line counts as off course.
        static let offCourse: Double = 45
        /// Tighter bound for coming back, so a wobble at the edge cannot chatter.
        static let backOnCourse: Double = 25
        /// Ignore brief excursions — canyon drift, a detour round a fallen tree.
        static let grace: TimeInterval = 8
        /// Re-buzz cadence while still off course.
        static let repeatAlert: TimeInterval = 45
        /// Recompute the way back at most this often.
        static let rerouteInterval: TimeInterval = 4
        static let waypointApproach: Double = 200
        static let waypointArrival: Double = 30
        /// A retrace up to this much longer than the direct line still wins,
        /// because it is over ground already proven passable.
        static let backtrackTolerance: Double = 1.6
    }

    /// True while an outdoor workout has yet to receive a usable fix. Distance
    /// and pace stay at zero until it clears — they are not guessed.
    var isAwaitingGPS: Bool { sport.usesGPS && !isGPSLive }

    var isEstimating: Bool { isAwaitingGPS }

    var isWorkoutRunning: Bool { phase == .active || phase == .paused }

    /// True from the moment Start is pressed until the summary is dismissed, so
    /// the app root can put the workout in front of everything else.
    var isWorkoutInProgress: Bool { phase != .idle }

    /// Plain words on how the search for a usable fix is going, for the precise
    /// start screen. Never invents a number the receiver has not reported.
    var acquiringText: String {
        guard metrics.horizontalAccuracy > 0 else { return "Searching for satellites" }
        return "Accurate to \(WatchFormat.shortDistance(metrics.horizontalAccuracy)) \(WatchFormat.units.shortDistanceUnit)"
    }

    /// Charge lost per hour in whichever mode is running, measured on this
    /// watch. `nil` until there is enough evidence to say.
    var batteryDrainPerHour: Double? {
        PowerBudget.drainPerHour(from: isPowerSaving ? savingSamples : normalSamples)
    }

    /// Recording time left, extrapolated from the measured drain.
    var batteryLabel: String {
        PowerBudget.label(
            hours: PowerBudget.remainingHours(
                batteryFraction: metrics.batteryFraction,
                drainPerHour: batteryDrainPerHour
            )
        )
    }

    /// What power saver has actually bought on this watch, once both modes have
    /// been observed for long enough to compare honestly.
    var batteryGainLabel: String {
        PowerBudget.gainLabel(
            batteryFraction: metrics.batteryFraction,
            normal: PowerBudget.drainPerHour(from: normalSamples),
            saving: PowerBudget.drainPerHour(from: savingSamples)
        )
    }

    /// Measured recording time left at full power, or `--` if this watch has
    /// not yet been observed running that way for long enough.
    var batteryNormalLabel: String {
        PowerBudget.label(
            hours: PowerBudget.remainingHours(
                batteryFraction: metrics.batteryFraction,
                drainPerHour: PowerBudget.drainPerHour(from: normalSamples)
            )
        )
    }

    /// The same figure measured while power saver was running.
    var batterySaverLabel: String {
        PowerBudget.label(
            hours: PowerBudget.remainingHours(
                batteryFraction: metrics.batteryFraction,
                drainPerHour: PowerBudget.drainPerHour(from: savingSamples)
            )
        )
    }

    /// Plain words for how far the measurement has got, so the screen never
    /// looks broken while it is still watching.
    var batteryMeasurementText: String {
        if batteryDrainPerHour != nil {
            return "Measured on this watch · \(PowerBudget.drainLabel(batteryDrainPerHour))"
        }
        return isWorkoutRunning
            ? "Measuring how fast this watch drains…"
            : "Measured during your workouts"
    }

    var batteryPercent: Int {
        Int((min(max(metrics.batteryFraction, 0), 1) * 100).rounded())
    }

    var elapsedSinceLap: TimeInterval { metrics.lapElapsed }

    // MARK: - Control

    func prepare(settings: WatchScreenSettings) {
        self.settings = settings
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        readBattery()
        sensors.requestLocationAccess()
        Task { _ = await sensors.requestHealthAccess() }
        publishFaceState()
    }

    // MARK: - Watch face

    /// Mirrors the current power picture into the shared container the
    /// complication reads.
    func publishFaceState() {
        var snapshot = PowerFace.load()
        snapshot.isPowerSaving = isWorkoutRunning ? isPowerSaving : (settings?.isPowerSaverEnabled ?? false)
        snapshot.isWorkoutActive = isWorkoutRunning
        snapshot.batteryFraction = metrics.batteryFraction
        snapshot.usesGPS = sport.usesGPS
        snapshot.keepsScreenOn = settings?.keepsScreenOn ?? true
        snapshot.sportTitle = isWorkoutRunning ? sport.title : "Ready"
        // The complication cannot measure anything itself, so the watch hands it
        // the finished figure rather than a set of constants to guess from.
        snapshot.projectedHours = PowerBudget.remainingHours(
            batteryFraction: metrics.batteryFraction,
            drainPerHour: batteryDrainPerHour
        )
        snapshot.updatedAt = .now
        PowerFace.save(snapshot)
    }

    /// Honours a power-saver change armed from the watch face. Mid-workout it
    /// hits the sensors; otherwise it becomes the default for the next start.
    func applyFaceRequestIfNeeded() {
        let snapshot = PowerFace.load()
        guard let requestedAt = snapshot.requestedAt,
              let requested = snapshot.requestedPowerSaving,
              lastFaceRequestAt != requestedAt else {
            publishFaceState()
            return
        }

        lastFaceRequestAt = requestedAt
        if isWorkoutRunning {
            setPowerSaving(requested)
        } else {
            settings?.isPowerSaverEnabled = requested
        }
        publishFaceState()
    }

    // MARK: - Power

    /// Switches power saver on or off, in a workout or before one starts.
    func setPowerSaving(_ enabled: Bool, automatic: Bool = false) {
        guard isPowerSaving != enabled else { return }
        isPowerSaving = enabled
        if !automatic {
            didOverridePowerSaver = !enabled
            didAutoArmPowerSaver = false
        }
        sensors.setPowerSaving(enabled)

        if enabled {
            // The optical sensor stops here, so say so rather than showing a
            // stale number as if it were live.
            metrics.isHeartRateEstimated = true
            lastHeartRateAt = nil
        }

        if settings?.usesHapticAlerts ?? true {
            WKInterfaceDevice.current().play(enabled ? .notification : .click)
        }
        showPowerBanner(
            enabled
                ? (automatic ? "POWER SAVER ON · \(batteryPercent)%" : "POWER SAVER ON")
                : "FULL POWER"
        )
        publishFaceState()
    }

    func togglePowerSaving() {
        setPowerSaving(!isPowerSaving)
    }

    /// The single path for the athlete changing power saver from settings or the
    /// watch face.
    ///
    /// A workout already running has its sensors turned down immediately; with no
    /// workout running there is nothing to turn down, so the choice is stored and
    /// applied the moment the next one starts. Either way it confirms with a
    /// haptic and a banner, because a switch that appears to do nothing reads as
    /// broken.
    func applyPowerSaverPreference(_ enabled: Bool) {
        settings?.isPowerSaverEnabled = enabled

        if isWorkoutRunning {
            setPowerSaving(enabled)
        } else {
            isPowerSaving = enabled
            didOverridePowerSaver = false
            didAutoArmPowerSaver = false
            if settings?.usesHapticAlerts ?? true {
                WKInterfaceDevice.current().play(enabled ? .notification : .click)
            }
            showPowerBanner(enabled ? "POWER SAVER ARMED" : "FULL POWER")
        }
        publishFaceState()
    }

    /// What power saver will do the next time a workout starts, in plain words.
    var powerSaverStatusText: String {
        if isWorkoutRunning {
            return isPowerSaving ? "On now · sensors turned down" : "Off · full sensor rate"
        }
        return (settings?.isPowerSaverEnabled ?? false)
            ? "Armed · starts with your next workout"
            : "Off · workouts start at full power"
    }

    /// Locks the screen against water. The Digital Crown clears it.
    func lockForWater() {
        isWaterLocked = true
        WKInterfaceDevice.current().enableWaterLock()
    }

    private func showPowerBanner(_ text: String) {
        powerBanner = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.powerBanner = nil
        }
    }

    private func readBattery() {
        let level = WKInterfaceDevice.current().batteryLevel
        guard level >= 0 else { return }
        let fraction = Double(level)
        metrics.batteryFraction = fraction

        // Only log while recording: the drain of a workout is the only rate
        // worth quoting to somebody about to start one.
        guard isWorkoutRunning else { return }
        let sample = PowerBudget.Sample(fraction: fraction, at: .now)
        if isPowerSaving {
            savingSamples.append(sample)
            if savingSamples.count > 240 { savingSamples.removeFirst() }
        } else {
            normalSamples.append(sample)
            if normalSamples.count > 240 { normalSamples.removeFirst() }
        }
    }

    /// Arms power saver on its own once the battery drops past the threshold.
    private func checkBatteryThreshold() {
        guard let settings, settings.powerSaverThreshold > 0 else { return }
        guard !isPowerSaving, !didOverridePowerSaver else { return }
        guard metrics.batteryFraction > 0 else { return }
        guard batteryPercent <= settings.powerSaverThreshold else { return }

        didAutoArmPowerSaver = true
        setPowerSaving(true, automatic: true)
    }

    func start(sport: WatchSport, route: WatchRoute?) {
        self.sport = sport
        self.route = route
        metrics = LiveMetrics()
        metrics.startDate = .now
        metrics.isHeartRateEstimated = false
        metrics.remainingDistance = route?.distance ?? 0
        metrics.nextWaypointName = route?.waypoints.first?.name ?? "—"
        reroute = nil
        navigationBanner = nil
        offCourseSince = nil
        lastOffCourseAlertAt = nil
        lastRerouteAt = nil
        announcedApproachIDs = []
        announcedArrivalIDs = []
        laps = []
        track = []
        startCoordinate = nil
        solarAnchor = nil
        lastStrokeTotal = nil
        lastStrokeTotalAt = nil
        lastLengthAt = nil
        strokesAtLastLength = 0
        heartRateSum = 0
        heartRateSamples = 0
        cadenceSum = 0
        cadenceSamples = 0
        lapHeartRateSum = 0
        lapHeartRateSamples = 0
        lapStartAscent = 0
        stillSeconds = 0
        ascentAnchor = 0
        stationaryFixes = 0
        pausedSeconds = 0
        pauseBeganAt = nil
        hasTrustedFix = false
        startBanner = nil
        startedWithPreciseFix = false
        lastFix = nil
        lastFixAt = nil
        lastAltitudeAt = nil
        lastHeartRateAt = nil
        lastStepTotal = nil
        lastStepTotalAt = nil
        normalSamples = []
        savingSamples = []
        isGPSLive = false
        gpsBars = 0
        tickCount = 0
        didOverridePowerSaver = false
        didAutoArmPowerSaver = false
        isWaterLocked = false
        isPowerSaving = settings?.isPowerSaverEnabled ?? false
        readBattery()

        wireSensors()
        settings?.markUsed(sport)
        onRecordingBegan?(sport)

        let countdown = max(0, settings?.countdownSeconds ?? 3)
        phase = countdown > 0 ? .countdown(countdown) : .acquiring

        Task { [weak self] in
            guard let self else { return }
            if countdown > 0 {
                for value in stride(from: countdown, through: 1, by: -1) {
                    phase = .countdown(value)
                    WKInterfaceDevice.current().play(.click)
                    try? await Task.sleep(for: .seconds(0.7))
                    guard case .countdown = phase else { return }
                }
            }
            await sensors.start(
                sport: sport,
                isPowerSaving: isPowerSaving,
                poolLengthMetres: settings?.poolLengthMetres ?? 25
            )

            // Precise start holds the clock until the receiver can actually
            // place you. Without it the first fix lands wherever the last
            // workout left off and the opening metres are fiction.
            let wantsPreciseStart = sport.usesGPS && (settings?.usesPreciseStart ?? false)
            guard wantsPreciseStart else {
                beginRecording()
                return
            }

            // Give the receiver a moment before taking the screen. A fix that
            // lands inside this window starts the workout without the athlete
            // ever seeing a waiting screen appear and disappear.
            await waitForTrustedFix(until: Date.now.addingTimeInterval(Fix.acquiringGrace))

            switch phase {
            case .countdown, .acquiring: break
            default: return
            }

            guard hasTrustedFix else {
                phase = .acquiring
                publishFaceState()
                return
            }
            beginRecording()
        }
    }

    /// Polls for a fix good enough to record against, up to a deadline.
    ///
    /// Polling rather than a continuation because the fix arrives through the
    /// ordinary sensor path, which already does the quality gating — this only
    /// needs to notice when that path has succeeded.
    private func waitForTrustedFix(until deadline: Date) async {
        while !hasTrustedFix, Date.now < deadline {
            switch phase {
            case .countdown, .acquiring: break
            default: return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Starts the clock. Called by the countdown, by the first trusted fix under
    /// precise start, or by the athlete overriding the wait.
    private func beginRecording() {
        // Only a workout that has been armed but has not started yet can begin.
        switch phase {
        case .countdown, .acquiring: break
        default: return
        }

        // Elapsed time is measured from here, not from the button press: a
        // countdown and a satellite search are not part of the workout.
        metrics.startDate = .now
        metrics.elapsed = 0
        pausedSeconds = 0
        phase = .active
        WKInterfaceDevice.current().play(.start)
        announceStart()
        if sport.isWaterSport, settings?.usesWaterLock ?? true {
            lockForWater()
        }
        publishFaceState()
        startTicking()
    }

    /// States what the start actually got, for anyone who asked for a precise
    /// one. Never claims an accuracy the receiver has not reported.
    private func announceStart() {
        guard sport.usesGPS, settings?.usesPreciseStart ?? false else { return }
        startedWithPreciseFix = hasTrustedFix

        if hasTrustedFix, metrics.horizontalAccuracy > 0 {
            let value = WatchFormat.shortDistance(metrics.horizontalAccuracy)
            let unit = WatchFormat.shortDistanceUnit(metrics.horizontalAccuracy)
            showStartBanner("Precise start · \(value) \(unit)")
        } else if hasTrustedFix {
            showStartBanner("Precise start")
        } else {
            showStartBanner("Started without a fix")
        }
    }

    private func showStartBanner(_ text: String) {
        startBanner = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.startBanner = nil
        }
    }

    /// Skips the wait for a precise fix and records from this moment, accepting
    /// that the opening metres may be loose.
    func startWithoutFix() {
        guard phase == .acquiring else { return }
        beginRecording()
    }

    func pause() {
        guard phase == .active else { return }
        phase = .paused
        pauseBeganAt = .now
        metrics.currentSpeed = 0
        sensors.pause()
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        // Time spent paused is time the workout did not happen, so it comes off
        // the elapsed clock rather than being quietly included.
        if let pauseBeganAt {
            pausedSeconds += Date().timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        phase = .active
        isAutoPaused = false
        stillSeconds = 0
        // The first fix after a break is measured from where you are now, not
        // from where you stopped.
        lastFix = nil
        sensors.resume()
        WKInterfaceDevice.current().play(.start)
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    func markLap(automatic: Bool = false) {
        guard phase == .active || phase == .paused else { return }
        let lap = WatchLap(
            index: laps.count + 1,
            duration: metrics.lapElapsed,
            distance: metrics.lapDistance,
            averageHeartRate: lapHeartRateSamples > 0 ? lapHeartRateSum / Double(lapHeartRateSamples) : 0,
            ascent: max(0, metrics.ascent - lapStartAscent),
            isAutomatic: automatic
        )
        laps.append(lap)
        metrics.lastLapDuration = lap.duration
        metrics.lastLapDistance = lap.distance
        metrics.lastLapAscent = lap.ascent
        metrics.lastLapHeartRate = lap.averageHeartRate
        metrics.lapCount = laps.count + 1
        metrics.lapAscent = 0
        metrics.lapHeartRate = 0
        metrics.lapElapsed = 0
        metrics.lapDistance = 0
        lapHeartRateSum = 0
        lapHeartRateSamples = 0
        lapStartAscent = metrics.ascent

        lastLapBanner = "Lap \(lap.index) · \(WatchFormat.duration(lap.duration))"
        if settings?.usesHapticAlerts ?? true {
            WKInterfaceDevice.current().play(.notification)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.lastLapBanner = nil
        }
    }

    func end() {
        ticker?.cancel()
        ticker = nil
        phase = .finished
        if metrics.lapElapsed > 5 { markLap() }
        WKInterfaceDevice.current().play(.success)
        Task { await sensors.stop() }
        releasePowerSaving()
        onRecordingEnded?(sport, route?.name ?? sport.title)
        sendSummaryToPhone()
        publishFaceState()
    }

    func discard() {
        ticker?.cancel()
        ticker = nil
        phase = .idle
        releasePowerSaving()
        onRecordingDiscarded?()
        Task { await sensors.discard() }
        publishFaceState()
    }

    /// Power saver exists to get you home, so it stops when the workout does.
    ///
    /// Leaving it on silently turns down the sensors of whatever comes next,
    /// which is how a watch ends up recording a race at reduced accuracy. An
    /// athlete who armed it in settings keeps that arming for the next start;
    /// what is cleared here is only the running state.
    private func releasePowerSaving() {
        guard isPowerSaving else { return }
        isPowerSaving = false
        didAutoArmPowerSaver = false
        didOverridePowerSaver = false
        sensors.setPowerSaving(false)
        showPowerBanner("FULL POWER RESTORED")
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        phase = .idle
        metrics = LiveMetrics()
        laps = []
        track = []
    }

    /// Hands the finished workout back to the paired iPhone over WatchConnectivity.
    /// The phone queues it as an activity even if it is not open right now.
    private func sendSummaryToPhone() {
        guard metrics.elapsed > 30 else { return }
        let identifier = UUID()
        let summary = WorkoutSummaryTransfer(
            id: identifier,
            sport: sport.rawValue,
            routeName: route?.name,
            startDate: metrics.startDate,
            duration: metrics.elapsed,
            distance: metrics.distance,
            ascent: metrics.ascent,
            calories: metrics.calories,
            averageHeartRate: metrics.averageHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            trainingEffect: metrics.trainingEffect,
            zoneSeconds: metrics.zoneSeconds,
            track: track.map { point in
                WorkoutSummaryTransfer.TrackPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    elevation: point.altitude
                )
            }
        )
        WatchLink.shared.sendWorkout(summary)

        // Show it in the watch's own history straight away; the phone will push
        // a refreshed dashboard carrying the same workout under the same id.
        onFinishedWorkout?(
            ActivityTransfer(
                id: identifier,
                name: route?.name ?? "\(sport.title) · Watch",
                activity: Self.activityKind(for: sport).rawValue,
                startDate: metrics.startDate,
                duration: metrics.elapsed,
                distance: metrics.distance,
                elevationGain: metrics.ascent,
                averageHeartRate: metrics.averageHeartRate,
                calories: metrics.calories,
                trainingEffect: metrics.trainingEffect,
                zoneMinutes: metrics.zoneSeconds.map { $0 / 60 },
                track: track.map { point in
                    SyncTrackPoint(
                        latitude: point.latitude,
                        longitude: point.longitude,
                        elevation: point.altitude
                    )
                }
            )
        )
    }

    private static func activityKind(for sport: WatchSport) -> WatchActivityKind {
        switch sport.family {
        case .run: .run
        case .ride: .ride
        default: .hike
        }
    }

    // MARK: - Sensor wiring

    private func wireSensors() {
        sensors.onFix = { [weak self] fix in self?.ingest(fix: fix) }
        sensors.onHeartRate = { [weak self] bpm in self?.ingest(heartRate: bpm) }
        sensors.onEnergy = { [weak self] kcal in
            guard let self, kcal > metrics.calories else { return }
            metrics.calories = kcal
        }
        sensors.onDistance = { [weak self] metres in
            // Health's distance is authoritative indoors, where the treadmill
            // belt and the wrist motion are the only evidence there is.
            guard let self, !sport.usesGPS, metres > metrics.distance else { return }
            let delta = metres - metrics.distance
            metrics.distance = metres
            metrics.lapDistance += delta
        }
        sensors.onCadence = { [weak self] rpm in
            guard let self, rpm > 0, rpm < 250 else { return }
            metrics.cadence = rpm
        }
        sensors.onPower = { [weak self] watts in
            guard let self, watts >= 0, watts < 2000 else { return }
            metrics.power = watts
        }
        sensors.onStepTotal = { [weak self] steps in
            self?.ingest(stepTotal: steps)
        }
        sensors.onStrokeTotal = { [weak self] strokes in
            self?.ingest(strokeTotal: strokes)
        }
        sensors.onLengthCompleted = { [weak self] in
            self?.completeLength()
        }
        sensors.onPressure = { [weak self] kilopascals in
            guard let self, kilopascals > 0 else { return }
            // Hectopascals is what every forecast and storm warning is quoted
            // in, so the conversion happens once, here.
            metrics.pressure = kilopascals * 10
        }
    }

    /// Turns the running stroke total into a rate, and remembers the count so a
    /// completed length knows how many strokes it took.
    private func ingest(strokeTotal strokes: Double) {
        guard strokes.isFinite, strokes >= 0 else { return }
        defer {
            lastStrokeTotal = strokes
            lastStrokeTotalAt = .now
        }
        metrics.strokes = strokes
        guard phase == .active,
              let previousTotal = lastStrokeTotal,
              let previousAt = lastStrokeTotalAt else { return }

        let seconds = Date().timeIntervalSince(previousAt)
        let newStrokes = strokes - previousTotal
        guard seconds >= 5, seconds <= 120, newStrokes >= 0 else { return }

        let perMinute = newStrokes / seconds * 60
        guard perMinute > 0, perMinute < 200 else { return }
        metrics.strokeRate = metrics.strokeRate == 0
            ? perMinute
            : metrics.strokeRate * 0.6 + perMinute * 0.4
    }

    /// Banks one pool length and scores it.
    ///
    /// SWOLF is the sum of the seconds a length took and the strokes it cost —
    /// the standard measure of swimming efficiency, where lower is better
    /// because it rewards going faster without thrashing.
    private func completeLength() {
        guard phase == .active else { return }
        let now = Date()
        let startedAt = lastLengthAt ?? metrics.startDate
        let seconds = now.timeIntervalSince(startedAt)
        lastLengthAt = now

        metrics.poolLengths += 1
        let strokesThisLength = max(0, metrics.strokes - strokesAtLastLength)
        strokesAtLastLength = metrics.strokes

        guard seconds > 0, seconds < 600 else { return }
        metrics.lastLengthSeconds = seconds
        metrics.swolf = seconds + strokesThisLength
    }

    /// Turns the running step total into steps per minute.
    ///
    /// HealthKit reports steps cumulatively, so cadence is the slope between two
    /// readings rather than a value the sensor hands over directly.
    private func ingest(stepTotal steps: Double) {
        guard steps.isFinite, steps >= 0 else { return }
        defer {
            lastStepTotal = steps
            lastStepTotalAt = .now
        }
        guard phase == .active,
              let previousTotal = lastStepTotal,
              let previousAt = lastStepTotalAt else { return }

        let seconds = Date().timeIntervalSince(previousAt)
        let newSteps = steps - previousTotal
        // Too short a window turns rounding into wild swings; too long and the
        // reading no longer describes now.
        guard seconds >= 5, seconds <= 120, newSteps >= 0 else { return }

        // Banked before the cadence window is judged: a step is a step even when
        // the gap between readings is too long to derive a rate from.
        metrics.steps += newSteps

        let perMinute = newSteps / seconds * 60
        guard perMinute > 0, perMinute < 300 else { return }
        metrics.cadence = metrics.cadence == 0
            ? perMinute
            : metrics.cadence * 0.6 + perMinute * 0.4
    }

    /// Folds one GPS reading into the workout, rejecting everything that cannot
    /// be trusted to represent real movement.
    private func ingest(fix: GeoFix) {
        // A bad fix is worse than no fix: it moves numbers the athlete will read
        // back later as fact.
        guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= Fix.worstAccuracy else { return }
        guard abs(fix.timestamp.timeIntervalSinceNow) <= Fix.staleness else { return }

        isGPSLive = true
        lastFixAt = .now
        gpsBars = fix.horizontalAccuracy < 8 ? 3 : (fix.horizontalAccuracy < 20 ? 2 : 1)
        // Mirrored onto the metrics so signal and accuracy can be placed on a
        // data screen like any other reading.
        metrics.gpsBars = gpsBars
        metrics.isGPSLive = true
        metrics.horizontalAccuracy = fix.horizontalAccuracy
        if fix.horizontalAccuracy <= Fix.trustedAccuracy { hasTrustedFix = true }
        currentCoordinate = fix.coordinate
        updateSolarTimes(coordinate: fix.coordinate)

        // Position and bearing are readings like any other, so they ride on the
        // metrics where a data screen can show them.
        metrics.latitude = fix.latitude
        metrics.longitude = fix.longitude
        metrics.hasPosition = true
        if startCoordinate == nil, phase == .active || phase == .acquiring {
            startCoordinate = fix.coordinate
        }
        if let startCoordinate {
            metrics.distanceToStart = CLLocation(
                latitude: startCoordinate.latitude, longitude: startCoordinate.longitude
            ).distance(from: CLLocation(latitude: fix.latitude, longitude: fix.longitude))
        }

        // Precise start: this is the fix the workout was waiting for.
        if phase == .acquiring, hasTrustedFix {
            lastFix = fix
            beginRecording()
            return
        }
        if fix.course >= 0 {
            heading = fix.course
            metrics.bearing = fix.course
        }
        if metrics.altitude == 0, fix.altitude.isFinite {
            metrics.altitude = fix.altitude
            ascentAnchor = fix.altitude
        }

        guard phase == .active, let previous = lastFix else {
            lastFix = fix
            return
        }

        let interval = fix.timestamp.timeIntervalSince(previous.timestamp)
        // Readings can arrive out of order; keep the older anchor rather than
        // measuring backwards in time.
        guard interval > 0 else { return }

        let from = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let to = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        let step = to.distance(from: from)
        guard step.isFinite else { return }

        // A jump implying an impossible speed is a receiver glitch, not a
        // sprint. Re-anchor on it, but do not bank the distance.
        guard step / interval <= Fix.maxSpeed else {
            lastFix = fix
            return
        }

        // Standing still still produces fixes that wander by roughly the size of
        // the reported error. Anything inside that noise floor is not travel, so
        // the anchor deliberately stays put until real movement accumulates past
        // it — otherwise a rest stop invents distance one metre at a time.
        let noiseFloor = max(previous.horizontalAccuracy, fix.horizontalAccuracy) * Fix.jitterFactor
        guard step > noiseFloor else {
            stationaryFixes += 1
            if stationaryFixes >= 2 { metrics.currentSpeed = 0 }
            return
        }
        stationaryFixes = 0
        lastFix = fix

        // A loose fix can still place you on the map, but it is not accurate
        // enough to add to a total that gets compared against a race distance.
        guard fix.horizontalAccuracy <= Fix.trustedAccuracy else { return }

        metrics.distance += step
        metrics.lapDistance += step
        applyAltitude(fix.altitude, over: step, seconds: interval)

        // The receiver measures speed by Doppler shift, which is far steadier
        // than dividing two noisy positions. Fall back only when it declines to
        // report one (a negative value).
        metrics.currentSpeed = fix.speed >= 0 ? fix.speed : step / interval

        track.append(
            WatchTrackPoint(
                latitude: fix.latitude,
                longitude: fix.longitude,
                altitude: fix.altitude,
                distance: metrics.distance
            )
        )
        onLocation?(fix.coordinate, fix.altitude)
    }

    private func ingest(heartRate bpm: Double) {
        guard bpm > 30, bpm < 240 else { return }
        metrics.heartRate = bpm
        metrics.isHeartRateEstimated = false
        guard phase == .active || phase == .paused else { return }
        lastHeartRateAt = .now
        metrics.maxHeartRate = max(metrics.maxHeartRate, bpm)
        heartRateSum += bpm
        heartRateSamples += 1
        metrics.averageHeartRate = heartRateSum / Double(heartRateSamples)
        lapHeartRateSum += bpm
        lapHeartRateSamples += 1
        metrics.lapHeartRate = lapHeartRateSum / Double(lapHeartRateSamples)
    }

    // MARK: - Tick

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                tick()
            }
        }
    }

    private func tick() {
        guard phase == .active else { return }

        tickCount += 1

        // Wall clock, not a count of ticks. watchOS throttles timers hard when
        // the wrist is down, so a stopwatch that counts its own wake-ups loses
        // minutes over a long day out.
        if isAutoPaused { pausedSeconds += 1 }
        metrics.elapsed = max(0, Date().timeIntervalSince(metrics.startDate) - pausedSeconds)
        metrics.pausedTime = pausedSeconds
        metrics.lapAscent = max(0, metrics.ascent - lapStartAscent)

        // Speed is a reading, not a state: when the receiver stops reporting
        // (which is exactly what standing still looks like) it decays to zero
        // instead of holding the last value forever.
        if let lastFixAt, Date().timeIntervalSince(lastFixAt) > Fix.speedTimeout {
            metrics.currentSpeed = 0
        }
        if sport.usesGPS, let lastFixAt, Date().timeIntervalSince(lastFixAt) > Fix.signalTimeout {
            isGPSLive = false
            gpsBars = 0
            metrics.isGPSLive = false
            metrics.gpsBars = 0
        }

        if tickCount % 15 == 0 {
            readBattery()
            checkBatteryThreshold()
            publishFaceState()
        }
        // Cheap read of the shared container so a tap on the watch face reaches
        // a workout that is already running.
        if tickCount % 3 == 0 {
            applyFaceRequestIfNeeded()
        }

        // Indoors there is no speed to judge by, so movement is whatever the
        // workout session says it is and auto-pause stays out of the way.
        let moving = sport.usesGPS ? metrics.currentSpeed > 0.4 : true
        if moving {
            stillSeconds = 0
            metrics.movingTime += 1
            metrics.lapElapsed += 1
            isAutoPaused = false
        } else {
            stillSeconds += 1
            if (settings?.isAutoPauseEnabled ?? true) && stillSeconds > 6 {
                isAutoPaused = true
            } else {
                metrics.lapElapsed += 1
            }
        }

        accumulateEffort()
        // Route maths is the expensive part of the tick, so power saver runs it
        // every other second. Timing and distance stay exact.
        if !isPowerSaving || tickCount % 2 == 0 {
            updateNavigation()
        }
        checkAutoLap()
    }

    /// Folds a barometric/GPS altitude reading into height, ascent and grade.
    ///
    /// Altitude wanders by several metres even standing still, and naïvely
    /// summing every upward wobble is how a flat run reports 300 m of climbing.
    /// Ascent is therefore measured against an anchor that only moves once the
    /// change clears the noise threshold, so a rest stop cannot invent vertical.
    private func applyAltitude(_ raw: Double, over horizontal: Double, seconds: TimeInterval) {
        guard raw.isFinite else { return }

        let previous = metrics.altitude
        let smoothed = previous == 0 ? raw : previous * 0.7 + raw * 0.3
        metrics.altitude = smoothed
        metrics.maxAltitude = max(metrics.maxAltitude ?? smoothed, smoothed)
        metrics.minAltitude = min(metrics.minAltitude ?? smoothed, smoothed)
        if ascentAnchor == 0 { ascentAnchor = smoothed }

        let sustained = smoothed - ascentAnchor
        if sustained >= Fix.ascentThreshold {
            metrics.ascent += sustained
            ascentAnchor = smoothed
        } else if sustained <= -Fix.ascentThreshold {
            metrics.descent += abs(sustained)
            ascentAnchor = smoothed
        }

        guard previous != 0 else { return }
        let step = smoothed - previous

        // Metres per hour, from the real gap between fixes rather than assuming
        // they arrive exactly one second apart.
        if seconds > 0 {
            let instantaneous = step / seconds * 3600
            metrics.verticalSpeed = metrics.verticalSpeed * 0.7
                + max(-4000, min(4000, instantaneous)) * 0.3
        }

        if horizontal > 1 {
            let instantaneous = (step / horizontal) * 100
            metrics.grade = metrics.grade * 0.75 + max(-45, min(45, instantaneous)) * 0.25
        }
    }

    /// Rolls up the values that are derived from sensor readings rather than
    /// read directly. Nothing here invents a reading that never arrived.
    private func accumulateEffort() {
        // Zone time only accrues while the optical sensor is actually reporting;
        // a missing heart rate is not zone one.
        if metrics.heartRate > 0 {
            let zone = metrics.heartRateZone
            if metrics.zoneSeconds.indices.contains(zone - 1) {
                metrics.zoneSeconds[zone - 1] += 1
            }
        }

        metrics.maxSpeed = max(metrics.maxSpeed, metrics.currentSpeed)
        if metrics.pace > 0, metrics.distance > 200 {
            metrics.bestPace = metrics.bestPace == 0 ? metrics.pace : min(metrics.bestPace, metrics.pace)
        }

        if metrics.cadence > 0 {
            cadenceSum += metrics.cadence
            cadenceSamples += 1
            metrics.averageCadence = cadenceSum / Double(cadenceSamples)
        }

        // Training effect rises with time spent in the higher zones, so it only
        // means anything once real heart rate has been recorded.
        let weighted = metrics.zoneSeconds.enumerated().reduce(0.0) { total, entry in
            total + entry.element * Double(entry.offset + 1)
        }
        metrics.trainingEffect = min(5, weighted / 2600)
    }

    /// Sun events ride on the metrics so they can sit on a data screen like
    /// any other reading. Recomputed only when the athlete has travelled far
    /// enough for position to change the answer.
    private func updateSolarTimes(coordinate: CLLocationCoordinate2D) {
        if let anchor = solarAnchor,
           abs(anchor.latitude - coordinate.latitude) < 0.005,
           abs(anchor.longitude - coordinate.longitude) < 0.005 {
            return
        }
        solarAnchor = coordinate
        metrics.sunrise = SolarTimes.nextSunrise(
            after: .now, latitude: coordinate.latitude, longitude: coordinate.longitude
        )
        metrics.sunset = SolarTimes.nextSunset(
            after: .now, latitude: coordinate.latitude, longitude: coordinate.longitude
        )
    }

    private func updateNavigation() {
        guard let route, let coordinate = currentCoordinate, !route.points.isEmpty else { return }

        let nearest = WatchRouteMath.nearestIndex(to: coordinate, in: route.points)
        metrics.offCourseMetres = nearest.distance
        let distances = WatchRouteMath.cumulativeDistances(of: route.points)
        let covered = distances.indices.contains(nearest.index) ? distances[nearest.index] : 0
        metrics.courseDistance = covered
        metrics.remainingDistance = max(0, route.distance - covered)
        metrics.remainingAscent = WatchRouteMath.ascentRemaining(from: nearest.index, in: route.points)
        metrics.remainingDescent = WatchRouteMath.descentRemaining(from: nearest.index, in: route.points)
        metrics.routeAscent = route.elevationGain

        if metrics.currentSpeed > 0.4 {
            metrics.etaSeconds = metrics.remainingDistance / metrics.currentSpeed
        }

        if let next = route.waypoints.first(where: { $0.distanceAlongRoute > covered }) {
            metrics.nextWaypointName = next.name
            metrics.distanceToWaypoint = max(0, next.distanceAlongRoute - covered)
            announceWaypointIfNeeded(next, distance: metrics.distanceToWaypoint)
        } else {
            metrics.nextWaypointName = "Finish"
            metrics.distanceToWaypoint = metrics.remainingDistance
        }

        updateCourseState(coordinate: coordinate, offBy: nearest.distance, route: route)
    }

    // MARK: - Navigation alerts

    /// Buzzes once on approach and again on arrival, so a junction is never
    /// missed just because the wrist was down.
    private func announceWaypointIfNeeded(_ waypoint: WatchWaypoint, distance: Double) {
        guard settings?.usesNavigationAlerts ?? true else { return }

        if distance <= Navigation.waypointArrival, !announcedArrivalIDs.contains(waypoint.id) {
            announcedArrivalIDs.insert(waypoint.id)
            announcedApproachIDs.insert(waypoint.id)
            play(.notification)
            showNavigationBanner(waypoint.name)
            return
        }

        if distance <= Navigation.waypointApproach, !announcedApproachIDs.contains(waypoint.id) {
            announcedApproachIDs.insert(waypoint.id)
            play(.directionUp)
            showNavigationBanner("\(waypoint.name) · \(WatchFormat.shortDistance(distance))")
        }
    }

    /// Tracks straying off the line, alerts about it, and keeps the way back
    /// current while it lasts.
    private func updateCourseState(coordinate: CLLocationCoordinate2D, offBy distance: Double, route: WatchRoute) {
        if distance > Navigation.offCourse {
            let since = offCourseSince ?? .now
            offCourseSince = since
            // Wait out the grace period so GPS drift never raises an alarm.
            guard Date().timeIntervalSince(since) >= Navigation.grace else { return }

            let wasOffCourse = metrics.isOffCourse
            metrics.isOffCourse = true
            refreshRerouteIfNeeded(from: coordinate, route: route, force: !wasOffCourse)

            let isDue = lastOffCourseAlertAt.map { Date().timeIntervalSince($0) >= Navigation.repeatAlert } ?? true
            guard isDue else { return }
            lastOffCourseAlertAt = .now
            if settings?.usesNavigationAlerts ?? true {
                play(.failure)
                showNavigationBanner("Off course · \(WatchFormat.shortDistance(distance))")
            }
        } else if distance <= Navigation.backOnCourse {
            offCourseSince = nil
            guard metrics.isOffCourse else { return }
            metrics.isOffCourse = false
            reroute = nil
            lastOffCourseAlertAt = nil
            lastRerouteAt = nil
            if settings?.usesNavigationAlerts ?? true {
                play(.success)
                showNavigationBanner("Back on route")
            }
        }
    }

    private func refreshRerouteIfNeeded(from coordinate: CLLocationCoordinate2D, route: WatchRoute, force: Bool) {
        guard settings?.isReroutingEnabled ?? true else {
            reroute = nil
            return
        }
        // Rebuilding scans the whole route, so it runs on a timer rather than
        // on every fix.
        if !force, let last = lastRerouteAt, Date().timeIntervalSince(last) < Navigation.rerouteInterval {
            return
        }
        lastRerouteAt = .now
        reroute = buildReroute(from: coordinate, route: route)
    }

    /// Picks the better of two honest options: the straight line back to the
    /// course, or the ground already walked.
    private func buildReroute(from coordinate: CLLocationCoordinate2D, route: WatchRoute) -> RerouteAdvice? {
        guard !route.points.isEmpty else { return nil }

        let nearest = WatchRouteMath.nearestIndex(to: coordinate, in: route.points)
        guard route.points.indices.contains(nearest.index) else { return nil }
        let target = route.points[nearest.index]
        let here = WatchRoutePoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            elevation: metrics.altitude
        )

        let direct = RerouteAdvice(
            strategy: .direct,
            guidance: [here, target],
            distance: nearest.distance,
            bearing: GeoMath.bearing(from: coordinate, to: target.coordinate),
            rejoinIndex: nearest.index
        )

        guard let retrace = backtrackPath(from: here, route: route),
              retrace.distance <= nearest.distance * Navigation.backtrackTolerance,
              let step = retrace.guidance.dropFirst().first else {
            return direct
        }

        return RerouteAdvice(
            strategy: .backtrack,
            guidance: retrace.guidance,
            distance: retrace.distance,
            bearing: GeoMath.bearing(from: coordinate, to: step.coordinate),
            rejoinIndex: retrace.rejoinIndex
        )
    }

    /// Walks the recorded track backwards until it touches the route again.
    private func backtrackPath(
        from here: WatchRoutePoint,
        route: WatchRoute
    ) -> (guidance: [WatchRoutePoint], distance: Double, rejoinIndex: Int)? {
        guard track.count > 2 else { return nil }

        // Only the recent tail can plausibly lead back, and thinning keeps the
        // scan cheap enough to run mid-workout.
        let tail = Array(track.suffix(400))
        let step = max(1, tail.count / 120)
        var path: [WatchRoutePoint] = [here]
        var total: Double = 0
        var previous = here

        for (offset, point) in tail.reversed().enumerated() {
            guard offset % step == 0 else { continue }
            let candidate = WatchRoutePoint(
                latitude: point.latitude,
                longitude: point.longitude,
                elevation: point.altitude
            )
            total += GeoMath.metres(from: previous.coordinate, to: candidate.coordinate)
            path.append(candidate)
            previous = candidate

            let nearest = WatchRouteMath.nearestIndex(to: candidate.coordinate, in: route.points)
            if nearest.distance <= Navigation.backOnCourse {
                return (path, total, nearest.index)
            }
        }
        return nil
    }

    private func showNavigationBanner(_ text: String) {
        navigationBanner = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.navigationBanner = nil
        }
    }

    private func play(_ haptic: WKHapticType) {
        guard settings?.usesHapticAlerts ?? true else { return }
        WKInterfaceDevice.current().play(haptic)
    }

    /// Splits a lap every whole unit of distance, in whatever units the athlete
    /// has chosen — every mile for an imperial athlete, every kilometre for a
    /// metric one.
    private func checkAutoLap() {
        guard settings?.isAutoLapEnabled ?? true else { return }
        let threshold = settings?.autoLapMetres ?? 1000
        guard threshold > 0, metrics.lapDistance >= threshold else { return }
        markLap(automatic: true)
    }
}
