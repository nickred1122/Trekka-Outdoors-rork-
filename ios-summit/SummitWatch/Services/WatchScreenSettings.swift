import Foundation
import Observation
import SwiftUI

/// Everything the athlete can configure about the watch, persisted on device.
///
/// Screens are stored per sport so a trail run and a gravel ride can carry
/// completely different page stacks.
@Observable
final class WatchScreenSettings {
    private var screensBySport: [String: [WatchScreen]] = [:]
    private var recentSportIDs: [String] = []

    var autoLapKilometres: Double = 1 { didSet { persist() } }
    var isAutoLapEnabled: Bool = true { didSet { persist() } }
    var isAutoPauseEnabled: Bool = true { didSet { persist() } }
    var usesHapticAlerts: Bool = true { didSet { persist() } }
    /// Buzzes when you stray off the course or approach a waypoint.
    var usesNavigationAlerts: Bool = true { didSet { persist() } }
    /// Works out a way back to the route whenever you go off course.
    var isReroutingEnabled: Bool = true { didSet { persist() } }
    /// Draws the map on a dark sheet rather than cream paper.
    ///
    /// Still named for the satellite toggle it replaced: the value is mirrored
    /// verbatim in the phone's sync payload, so renaming it would break the link
    /// with watch builds already in the field.
    var prefersHybridMap: Bool = false { didSet { persist() } }
    var keepsScreenOn: Bool = true { didSet { persist() } }
    /// Seconds counted down before recording starts. 0 starts immediately.
    var countdownSeconds: Int = 3 { didSet { persist() } }
    /// Holds the clock until the receiver has a fix worth trusting, so the first
    /// metres of a workout are real rather than a guess that gets saved.
    var usesPreciseStart: Bool = false { didSet { persist() } }
    /// Whether signal and charge ride above every page. Off by default now that
    /// both can be placed on a data screen as ordinary fields.
    var showsStatusBadges: Bool = false { didSet { persist() } }
    /// Colour of the planned course line on the map.
    var routeTrailColor: TrailColor = .orange { didSet { persist() } }
    /// Colour of the breadcrumb trail of where you have actually been.
    var breadcrumbTrailColor: TrailColor = .amber { didSet { persist() } }
    /// Typeface every metric readout is drawn in.
    var metricTypeface: MetricTypeface = .rounded {
        didSet {
            MetricStyle.typeface = metricTypeface
            persist()
        }
    }
    /// One colour for every readout, or each page's own judgement.
    var fieldTint: FieldTint = .auto {
        didSet {
            MetricStyle.tint = fieldTint
            persist()
        }
    }
    /// How thick metric numerals are drawn.
    var metricWeight: MetricWeightChoice = .standard {
        didSet {
            MetricStyle.weight = metricWeight
            persist()
        }
    }
    /// Starts every workout in power saver.
    var isPowerSaverEnabled: Bool = false { didSet { persist() } }
    /// Battery percentage that arms power saver mid-workout. 0 disables it.
    var powerSaverThreshold: Int = 20 { didSet { persist() } }
    /// Locks the screen automatically for swims and other water sports.
    var usesWaterLock: Bool = true { didSet { persist() } }
    /// Asks before a workout is stopped. On by default: ending is the one
    /// control on the wrist that cannot be undone, and a cuff or a jacket sleeve
    /// finds it as easily as a finger does.
    var confirmsWorkoutEnd: Bool = true { didSet { persist() } }
    var maxHeartRate: Int = 188 {
        didSet {
            LiveMetrics.maxHeartRateCeiling = Double(maxHeartRate)
            persist()
        }
    }
    /// Metric or imperial. Mirrored into `WatchFormat` so every cell, banner and
    /// summary on the wrist converts the same way.
    var unitSystem: UnitSystem = .deviceDefault {
        didSet {
            WatchFormat.units = unitSystem
            persist()
        }
    }

    private let defaultsKey = "watch.screens.v1"

    /// Set by the connectivity bridge so wrist edits reach the phone.
    var onLocalChange: ((Data) -> Void)?
    private var isApplyingRemoteEdit = false

    init() {
        load()
        LiveMetrics.maxHeartRateCeiling = Double(maxHeartRate)
        WatchFormat.units = unitSystem
        applyMetricStyle()
    }

    /// Pushes the type choices into the static holder every metric cell reads.
    private func applyMetricStyle() {
        MetricStyle.typeface = metricTypeface
        MetricStyle.tint = fieldTint
        MetricStyle.weight = metricWeight
    }

    /// The auto-lap trigger in metres, from a lap length set in the athlete's
    /// own unit. Stored as a number of kilometres or miles, never as metres, so
    /// switching units keeps "every 1" meaning "every 1".
    var autoLapMetres: Double {
        unitSystem.metres(fromDistance: autoLapKilometres)
    }

    // MARK: - Screens

    func screens(for sport: WatchSport) -> [WatchScreen] {
        screensBySport[sport.rawValue] ?? sport.defaultScreens
    }

    /// Enabled pages only — what the workout carousel actually shows.
    func activeScreens(for sport: WatchSport, hasRoute: Bool) -> [WatchScreen] {
        screens(for: sport).filter { screen in
            guard screen.isEnabled else { return false }
            if screen.kind.requiresGPS && !sport.usesGPS { return false }
            // Climb and Up Ahead read the loaded course, so without one there is
            // nothing honest to put on them.
            if screen.kind.requiresRoute && !hasRoute { return false }
            if screen.kind == .elevation && !hasRoute && !sport.usesElevation { return false }
            if screen.kind == .data && screen.fields.isEmpty { return false }
            return true
        }
    }

    func setScreens(_ screens: [WatchScreen], for sport: WatchSport) {
        screensBySport[sport.rawValue] = screens
        persist()
    }

    func addScreen(_ screen: WatchScreen, to sport: WatchSport) {
        var current = screens(for: sport)
        current.append(screen)
        setScreens(current, for: sport)
    }

    func removeScreen(id: UUID, from sport: WatchSport) {
        var current = screens(for: sport)
        current.removeAll { $0.id == id }
        setScreens(current, for: sport)
    }

    func toggleScreen(id: UUID, for sport: WatchSport) {
        var current = screens(for: sport)
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].isEnabled.toggle()
        setScreens(current, for: sport)
    }

    func move(screenID: UUID, by offset: Int, for sport: WatchSport) {
        var current = screens(for: sport)
        guard let index = current.firstIndex(where: { $0.id == screenID }) else { return }
        let target = index + offset
        guard target >= 0, target < current.count else { return }
        current.swapAt(index, target)
        setScreens(current, for: sport)
    }

    func screen(id: UUID, for sport: WatchSport) -> WatchScreen? {
        screens(for: sport).first { $0.id == id }
    }

    // MARK: - Fields

    func setFields(_ fields: [WatchDataField], screenID: UUID, sport: WatchSport) {
        var current = screens(for: sport)
        guard let index = current.firstIndex(where: { $0.id == screenID }) else { return }
        current[index].fields = Array(fields.prefix(WatchScreen.maxFields))
        setScreens(current, for: sport)
    }

    /// Chooses the arrangement for a data screen, resizing its metric list to
    /// match. Passing nil returns the screen to arranging itself.
    func setLayout(_ layout: WatchScreenLayout?, screenID: UUID, sport: WatchSport) {
        var current = screens(for: sport)
        guard let index = current.firstIndex(where: { $0.id == screenID }) else { return }
        current[index] = current[index].fitted(
            to: layout,
            suggestions: WatchDataField.suggestions(for: sport)
        )
        setScreens(current, for: sport)
    }

    func addField(_ field: WatchDataField, screenID: UUID, sport: WatchSport) {
        guard let screen = screen(id: screenID, for: sport),
              screen.fields.count < WatchScreen.maxFields else { return }
        setFields(screen.fields + [field], screenID: screenID, sport: sport)
    }

    func replaceField(at slot: Int, with field: WatchDataField, screenID: UUID, sport: WatchSport) {
        guard let screen = screen(id: screenID, for: sport), screen.fields.indices.contains(slot) else { return }
        var fields = screen.fields
        fields[slot] = field
        setFields(fields, screenID: screenID, sport: sport)
    }

    /// Removing a slot from a screen with a chosen layout would leave a hole, so
    /// the layout steps down to the next arrangement of the same shape.
    func removeField(at slot: Int, screenID: UUID, sport: WatchSport) {
        guard let screen = screen(id: screenID, for: sport), screen.fields.indices.contains(slot) else { return }
        var fields = screen.fields
        fields.remove(at: slot)
        if let layout = screen.layout {
            // The watch's own capacity decides how far the shape can shrink, so
            // a page designed for a bigger screen still lands inside this one.
            let capacity = WatchDisplay.capacity
            let shrunk = layout.trimmed(toSlots: max(fields.count, 1), capacity: capacity)
                ?? WatchScreenLayout.automatic(
                    forSlots: min(max(fields.count, 1), capacity.maxSlots),
                    capacity: capacity
                )
            var current = screens(for: sport)
            guard let index = current.firstIndex(where: { $0.id == screenID }) else { return }
            current[index].fields = fields
            current[index].layout = fields.isEmpty ? nil : (layout.slotCount == fields.count ? layout : shrunk)
            setScreens(current, for: sport)
            return
        }
        setFields(fields, screenID: screenID, sport: sport)
    }

    func moveField(at slot: Int, by offset: Int, screenID: UUID, sport: WatchSport) {
        guard let screen = screen(id: screenID, for: sport), screen.fields.indices.contains(slot) else { return }
        let target = slot + offset
        guard target >= 0, target < screen.fields.count else { return }
        var fields = screen.fields
        fields.swapAt(slot, target)
        setFields(fields, screenID: screenID, sport: sport)
    }

    func resetScreens(for sport: WatchSport) {
        screensBySport[sport.rawValue] = nil
        persist()
    }

    func isCustomized(_ sport: WatchSport) -> Bool {
        screensBySport[sport.rawValue] != nil
    }

    // MARK: - Incoming transfer

    /// Applies a layout document pushed from the phone over WatchConnectivity.
    /// The payload is exactly what this store persists, so decoding is native.
    func applyIncoming(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        isApplyingRemoteEdit = true
        defer {
            isApplyingRemoteEdit = false
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        screensBySport = payload.screens
        recentSportIDs = payload.recents
        autoLapKilometres = payload.autoLapKilometres
        isAutoLapEnabled = payload.isAutoLapEnabled
        isAutoPauseEnabled = payload.isAutoPauseEnabled
        usesHapticAlerts = payload.usesHapticAlerts
        usesNavigationAlerts = payload.usesNavigationAlerts ?? usesNavigationAlerts
        isReroutingEnabled = payload.isReroutingEnabled ?? isReroutingEnabled
        prefersHybridMap = payload.prefersHybridMap
        keepsScreenOn = payload.keepsScreenOn
        isPowerSaverEnabled = payload.isPowerSaverEnabled ?? isPowerSaverEnabled
        powerSaverThreshold = payload.powerSaverThreshold ?? powerSaverThreshold
        usesWaterLock = payload.usesWaterLock ?? usesWaterLock
        confirmsWorkoutEnd = payload.confirmsWorkoutEnd ?? confirmsWorkoutEnd
        countdownSeconds = payload.countdownSeconds ?? countdownSeconds
        usesPreciseStart = payload.usesPreciseStart ?? usesPreciseStart
        showsStatusBadges = payload.showsStatusBadges ?? showsStatusBadges
        routeTrailColor = TrailColor.resolve(payload.routeTrailColor) ?? routeTrailColor
        breadcrumbTrailColor = TrailColor.resolve(payload.breadcrumbTrailColor) ?? breadcrumbTrailColor
        metricTypeface = payload.metricTypeface.flatMap(MetricTypeface.init(rawValue:)) ?? metricTypeface
        fieldTint = payload.fieldTint.flatMap(FieldTint.init(rawValue:)) ?? fieldTint
        metricWeight = payload.metricWeight.flatMap(MetricWeightChoice.init(rawValue:)) ?? metricWeight
        maxHeartRate = payload.maxHeartRate
        unitSystem = payload.unitSystem.flatMap(UnitSystem.init(rawValue:)) ?? unitSystem
        LiveMetrics.maxHeartRateCeiling = Double(maxHeartRate)
        WatchFormat.units = unitSystem
        applyMetricStyle()
    }

    // MARK: - Recents

    var recentSports: [WatchSport] {
        recentSportIDs.compactMap(WatchSport.init(rawValue:))
    }

    func markUsed(_ sport: WatchSport) {
        recentSportIDs.removeAll { $0 == sport.rawValue }
        recentSportIDs.insert(sport.rawValue, at: 0)
        recentSportIDs = Array(recentSportIDs.prefix(4))
        persist()
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var screens: [String: [WatchScreen]]
        var recents: [String]
        var autoLapKilometres: Double
        var isAutoLapEnabled: Bool
        var isAutoPauseEnabled: Bool
        var usesHapticAlerts: Bool
        var prefersHybridMap: Bool
        var keepsScreenOn: Bool
        var maxHeartRate: Int
        // Optional so documents written before power saver still decode.
        var isPowerSaverEnabled: Bool?
        var powerSaverThreshold: Int?
        var usesWaterLock: Bool?
        var confirmsWorkoutEnd: Bool?
        var usesNavigationAlerts: Bool?
        var isReroutingEnabled: Bool?
        var unitSystem: String?
        var countdownSeconds: Int?
        var usesPreciseStart: Bool?
        var showsStatusBadges: Bool?
        var routeTrailColor: String?
        var breadcrumbTrailColor: String?
        var metricTypeface: String?
        var fieldTint: String?
        var metricWeight: String?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        screensBySport = payload.screens
        recentSportIDs = payload.recents
        autoLapKilometres = payload.autoLapKilometres
        isAutoLapEnabled = payload.isAutoLapEnabled
        isAutoPauseEnabled = payload.isAutoPauseEnabled
        usesHapticAlerts = payload.usesHapticAlerts
        usesNavigationAlerts = payload.usesNavigationAlerts ?? true
        isReroutingEnabled = payload.isReroutingEnabled ?? true
        prefersHybridMap = payload.prefersHybridMap
        keepsScreenOn = payload.keepsScreenOn
        isPowerSaverEnabled = payload.isPowerSaverEnabled ?? false
        powerSaverThreshold = payload.powerSaverThreshold ?? 20
        usesWaterLock = payload.usesWaterLock ?? true
        confirmsWorkoutEnd = payload.confirmsWorkoutEnd ?? true
        countdownSeconds = payload.countdownSeconds ?? 3
        usesPreciseStart = payload.usesPreciseStart ?? false
        showsStatusBadges = payload.showsStatusBadges ?? false
        routeTrailColor = TrailColor.resolve(payload.routeTrailColor) ?? .orange
        breadcrumbTrailColor = TrailColor.resolve(payload.breadcrumbTrailColor) ?? .amber
        metricTypeface = payload.metricTypeface.flatMap(MetricTypeface.init(rawValue:)) ?? .rounded
        fieldTint = payload.fieldTint.flatMap(FieldTint.init(rawValue:)) ?? .auto
        metricWeight = payload.metricWeight.flatMap(MetricWeightChoice.init(rawValue:)) ?? .standard
        maxHeartRate = payload.maxHeartRate
        unitSystem = payload.unitSystem.flatMap(UnitSystem.init(rawValue:)) ?? .deviceDefault
    }

    private func persist() {
        guard !isApplyingRemoteEdit else { return }
        let payload = Payload(
            screens: screensBySport,
            recents: recentSportIDs,
            autoLapKilometres: autoLapKilometres,
            isAutoLapEnabled: isAutoLapEnabled,
            isAutoPauseEnabled: isAutoPauseEnabled,
            usesHapticAlerts: usesHapticAlerts,
            prefersHybridMap: prefersHybridMap,
            keepsScreenOn: keepsScreenOn,
            maxHeartRate: maxHeartRate,
            isPowerSaverEnabled: isPowerSaverEnabled,
            powerSaverThreshold: powerSaverThreshold,
            usesWaterLock: usesWaterLock,
            confirmsWorkoutEnd: confirmsWorkoutEnd,
            usesNavigationAlerts: usesNavigationAlerts,
            isReroutingEnabled: isReroutingEnabled,
            unitSystem: unitSystem.rawValue,
            countdownSeconds: countdownSeconds,
            usesPreciseStart: usesPreciseStart,
            showsStatusBadges: showsStatusBadges,
            routeTrailColor: routeTrailColor.rawValue,
            breadcrumbTrailColor: breadcrumbTrailColor.rawValue,
            metricTypeface: metricTypeface.rawValue,
            fieldTint: fieldTint.rawValue,
            metricWeight: metricWeight.rawValue
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        onLocalChange?(data)
    }
}
