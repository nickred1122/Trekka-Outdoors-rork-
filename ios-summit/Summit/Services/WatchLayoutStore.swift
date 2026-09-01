import Foundation
import Observation
import SwiftUI

/// Owns the watch screen layout designed on the phone.
///
/// The persisted document uses the same key and shape as the watch app's own
/// store, so what is designed here is exactly what the watch reads.
@Observable
final class WatchLayoutStore {
    enum DeliveryState: Equatable {
        case idle
        case sending(progress: Double)
        case delivered(Date)
        case failed(String)
    }

    private var pagesBySport: [String: [WatchPage]] = [:]
    private(set) var delivery: DeliveryState = .idle

    var isAutoLapEnabled: Bool = true { didSet { persist() } }
    var autoLapKilometres: Double = 1 { didSet { persist() } }
    var isAutoPauseEnabled: Bool = true { didSet { persist() } }
    var usesHapticAlerts: Bool = true { didSet { persist() } }
    var prefersHybridMap: Bool = false { didSet { persist() } }
    var keepsScreenOn: Bool = true { didSet { persist() } }
    /// Starts every watch workout in power saver.
    var isPowerSaverEnabled: Bool = false { didSet { persist() } }
    /// Battery percentage that arms power saver mid-workout. 0 disables it.
    var powerSaverThreshold: Int = 20 { didSet { persist() } }
    /// Locks the watch screen automatically for water sports.
    var usesWaterLock: Bool = true { didSet { persist() } }
    /// Asks before a watch workout is stopped, so a brush against the screen
    /// cannot end a recording outright.
    var confirmsWorkoutEnd: Bool = true { didSet { persist() } }
    /// Buzzes when you stray off the course or approach a waypoint.
    var usesNavigationAlerts: Bool = true { didSet { persist() } }
    /// Works out a way back to the route whenever you go off course.
    var isReroutingEnabled: Bool = true { didSet { persist() } }
    var maxHeartRate: Int = 188 { didSet { persist() } }
    /// Colour of the planned course line, on both devices.
    var routeTrailColor: TrailColor = .orange {
        didSet {
            TrailStyle.route = routeTrailColor
            persist()
        }
    }
    /// Colour of the breadcrumb trail of where you have actually been.
    var breadcrumbTrailColor: TrailColor = .amber {
        didSet {
            TrailStyle.breadcrumb = breadcrumbTrailColor
            persist()
        }
    }
    /// Watch-only type choices, edited here and carried in the same document.
    /// The phone has no metric cells of its own to restyle, but it is the
    /// comfortable place to set them up.
    var metricTypeface: String = "rounded" { didSet { persist() } }
    var fieldTint: String = "auto" { didSet { persist() } }
    var metricWeight: String = "standard" { didSet { persist() } }
    /// Metric or imperial, carried in the same document as the layout so the
    /// watch reads its units from exactly the file it reads its pages from.
    var unitSystem: UnitSystem = .deviceDefault { didSet { persist() } }

    private let defaultsKey = "watch.screens.v1"
    private var deliveryTask: Task<Void, Never>?
    /// Suppresses persistence side effects while a watch-originated edit is applied.
    private var isApplyingRemoteEdit = false

    init() {
        load()
        applyTrailStyle()
    }

    /// Pushes the line colours into the static holder every map surface reads.
    private func applyTrailStyle() {
        TrailStyle.route = routeTrailColor
        TrailStyle.breadcrumb = breadcrumbTrailColor
    }

    // MARK: - Pages

    func pages(for sport: WatchSportProfile) -> [WatchPage] {
        pagesBySport[sport.rawValue] ?? sport.defaultPages
    }

    func enabledPages(for sport: WatchSportProfile) -> [WatchPage] {
        pages(for: sport).filter { page in
            guard page.isEnabled else { return false }
            if page.kind == .data && page.fields.isEmpty { return false }
            if (page.kind == .map || page.kind == .compass) && !sport.usesGPS { return false }
            return true
        }
    }

    func isCustomized(_ sport: WatchSportProfile) -> Bool {
        pagesBySport[sport.rawValue] != nil
    }

    func setPages(_ pages: [WatchPage], for sport: WatchSportProfile) {
        pagesBySport[sport.rawValue] = pages
        persist()
    }

    func addPage(_ page: WatchPage, to sport: WatchSportProfile) {
        setPages(pages(for: sport) + [page], for: sport)
    }

    func removePages(at offsets: IndexSet, from sport: WatchSportProfile) {
        var current = pages(for: sport)
        current.remove(atOffsets: offsets)
        setPages(current, for: sport)
    }

    func movePages(fromOffsets offsets: IndexSet, toOffset destination: Int, for sport: WatchSportProfile) {
        var current = pages(for: sport)
        current.move(fromOffsets: offsets, toOffset: destination)
        setPages(current, for: sport)
    }

    func togglePage(id: UUID, for sport: WatchSportProfile) {
        var current = pages(for: sport)
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].isEnabled.toggle()
        setPages(current, for: sport)
    }

    func page(id: UUID, for sport: WatchSportProfile) -> WatchPage? {
        pages(for: sport).first { $0.id == id }
    }

    func resetPages(for sport: WatchSportProfile) {
        pagesBySport[sport.rawValue] = nil
        persist()
    }

    // MARK: - Fields

    func setFields(_ fields: [WatchMetric], pageID: UUID, sport: WatchSportProfile) {
        var current = pages(for: sport)
        guard let index = current.firstIndex(where: { $0.id == pageID }) else { return }
        current[index].fields = Array(fields.prefix(WatchPage.maxFields))
        setPages(current, for: sport)
    }

    /// Chooses the arrangement for a data page, resizing its metric list to
    /// match. Passing nil returns the page to arranging itself.
    func setLayout(_ layout: WatchPageLayout?, pageID: UUID, sport: WatchSportProfile) {
        var current = pages(for: sport)
        guard let index = current.firstIndex(where: { $0.id == pageID }) else { return }
        current[index] = current[index].fitted(
            to: layout,
            suggestions: WatchMetric.suggestions(for: sport)
        )
        setPages(current, for: sport)
    }

    func addField(_ metric: WatchMetric, pageID: UUID, sport: WatchSportProfile) {
        guard let page = page(id: pageID, for: sport), page.fields.count < WatchPage.maxFields else { return }
        setFields(page.fields + [metric], pageID: pageID, sport: sport)
    }

    func replaceField(at slot: Int, with metric: WatchMetric, pageID: UUID, sport: WatchSportProfile) {
        guard let page = page(id: pageID, for: sport), page.fields.indices.contains(slot) else { return }
        var fields = page.fields
        fields[slot] = metric
        setFields(fields, pageID: pageID, sport: sport)
    }

    /// Removing a slot from a page with a chosen layout would leave a hole, so
    /// the layout steps down to another arrangement of that size.
    func removeFields(at offsets: IndexSet, pageID: UUID, sport: WatchSportProfile) {
        guard let page = page(id: pageID, for: sport) else { return }
        var fields = page.fields
        fields.remove(atOffsets: offsets)
        guard page.layout != nil else {
            setFields(fields, pageID: pageID, sport: sport)
            return
        }
        var current = pages(for: sport)
        guard let index = current.firstIndex(where: { $0.id == pageID }) else { return }
        current[index].fields = fields
        // The paired watch's capacity decides how far the shape can shrink, so
        // a page designed for a bigger screen still lands inside this one.
        let capacity = WatchLink.shared.watchCapacity
        current[index].layout = fields.isEmpty
            ? nil
            : (page.layout?.trimmed(toSlots: fields.count, capacity: capacity)
                ?? .automatic(forSlots: min(max(fields.count, 1), capacity.maxSlots), capacity: capacity))
        setPages(current, for: sport)
    }

    func moveFields(fromOffsets offsets: IndexSet, toOffset destination: Int, pageID: UUID, sport: WatchSportProfile) {
        guard let page = page(id: pageID, for: sport) else { return }
        var fields = page.fields
        fields.move(fromOffsets: offsets, toOffset: destination)
        setFields(fields, pageID: pageID, sport: sport)
    }

    // MARK: - Delivery

    /// Sends the layout to the paired watch over WatchConnectivity.
    ///
    /// The watch decodes the exact document this store persists, so what was
    /// designed here is what appears on the wrist.
    func sendToWatch() {
        deliveryTask?.cancel()
        guard let data = encodedPayload() else {
            delivery = .failed("Could not read the layout document. Try again.")
            return
        }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...4 {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                delivery = .sending(progress: Double(step) / 5)
            }
            delivery = WatchLink.shared.sendLayout(data)
                ? .delivered(.now)
                : .failed("No Apple Watch with Trekka detected. Pair the watch and install the app, then try again.")
        }
    }

    // MARK: - Incoming from the watch

    /// Applies a layout document edited on the watch so both devices agree.
    func applyIncoming(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        isApplyingRemoteEdit = true
        pagesBySport = payload.screens
        recents = payload.recents
        autoLapKilometres = payload.autoLapKilometres
        isAutoLapEnabled = payload.isAutoLapEnabled
        isAutoPauseEnabled = payload.isAutoPauseEnabled
        usesHapticAlerts = payload.usesHapticAlerts
        prefersHybridMap = payload.prefersHybridMap
        keepsScreenOn = payload.keepsScreenOn
        isPowerSaverEnabled = payload.isPowerSaverEnabled ?? isPowerSaverEnabled
        powerSaverThreshold = payload.powerSaverThreshold ?? powerSaverThreshold
        usesWaterLock = payload.usesWaterLock ?? usesWaterLock
        confirmsWorkoutEnd = payload.confirmsWorkoutEnd ?? confirmsWorkoutEnd
        maxHeartRate = payload.maxHeartRate
        unitSystem = payload.unitSystem.flatMap(UnitSystem.init(rawValue:)) ?? unitSystem
        routeTrailColor = TrailColor.resolve(payload.routeTrailColor) ?? routeTrailColor
        breadcrumbTrailColor = TrailColor.resolve(payload.breadcrumbTrailColor) ?? breadcrumbTrailColor
        metricTypeface = payload.metricTypeface ?? metricTypeface
        fieldTint = payload.fieldTint ?? fieldTint
        metricWeight = payload.metricWeight ?? metricWeight
        applyTrailStyle()
        isApplyingRemoteEdit = false
        UserDefaults.standard.set(data, forKey: defaultsKey)
        delivery = .delivered(.now)
    }

    // MARK: - Backup

    /// How many sports carry a layout of the athlete's own making.
    var customizedSportCount: Int { pagesBySport.count }

    /// The exact document the watch reads, for backing up and exporting.
    func archivedDocument() -> Data? { encodedPayload() }

    /// Puts back a watch document from a backup, then saves it and sends it to
    /// the watch so the wrist matches the phone straight away.
    @discardableResult
    func restore(document data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return false }
        isApplyingRemoteEdit = true
        adopt(payload)
        isApplyingRemoteEdit = false
        persist()
        pushSilently()
        return true
    }

    /// Pushes the current document without the staged progress animation.
    @discardableResult
    func pushSilently() -> Bool {
        guard let data = encodedPayload() else { return false }
        return WatchLink.shared.sendLayout(data)
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var screens: [String: [WatchPage]]
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
        var routeTrailColor: String?
        var breadcrumbTrailColor: String?
        var metricTypeface: String?
        var fieldTint: String?
        var metricWeight: String?
    }

    private var recents: [String] = []

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        adopt(payload)
    }

    /// Takes on a stored document wholesale, filling in anything written before
    /// a setting existed with that setting's default.
    private func adopt(_ payload: Payload) {
        pagesBySport = payload.screens
        recents = payload.recents
        autoLapKilometres = payload.autoLapKilometres
        isAutoLapEnabled = payload.isAutoLapEnabled
        isAutoPauseEnabled = payload.isAutoPauseEnabled
        usesHapticAlerts = payload.usesHapticAlerts
        prefersHybridMap = payload.prefersHybridMap
        keepsScreenOn = payload.keepsScreenOn
        isPowerSaverEnabled = payload.isPowerSaverEnabled ?? false
        powerSaverThreshold = payload.powerSaverThreshold ?? 20
        usesWaterLock = payload.usesWaterLock ?? true
        confirmsWorkoutEnd = payload.confirmsWorkoutEnd ?? true
        maxHeartRate = payload.maxHeartRate
        unitSystem = payload.unitSystem.flatMap(UnitSystem.init(rawValue:)) ?? .deviceDefault
        usesNavigationAlerts = payload.usesNavigationAlerts ?? true
        isReroutingEnabled = payload.isReroutingEnabled ?? true
        routeTrailColor = TrailColor.resolve(payload.routeTrailColor) ?? .orange
        breadcrumbTrailColor = TrailColor.resolve(payload.breadcrumbTrailColor) ?? .amber
        metricTypeface = payload.metricTypeface ?? "rounded"
        fieldTint = payload.fieldTint ?? "auto"
        metricWeight = payload.metricWeight ?? "standard"
        applyTrailStyle()
    }

    private func encodedPayload() -> Data? {
        let payload = Payload(
            screens: pagesBySport,
            recents: recents,
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
            routeTrailColor: routeTrailColor.rawValue,
            breadcrumbTrailColor: breadcrumbTrailColor.rawValue,
            metricTypeface: metricTypeface,
            fieldTint: fieldTint,
            metricWeight: metricWeight
        )
        return try? JSONEncoder().encode(payload)
    }

    private func persist() {
        guard !isApplyingRemoteEdit, let data = encodedPayload() else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        if case .delivered = delivery { delivery = .idle }
    }
}
