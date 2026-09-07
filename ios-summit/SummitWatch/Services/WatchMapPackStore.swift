import Foundation
import Observation

/// Owns the offline maps stored on the watch.
///
/// Packs arrive two ways: shipped across from the phone as a single file, or
/// downloaded by the watch itself over its own radio. Either way they land in
/// the same directory in the same format, so the map draws from them
/// identically and neither path is a special case.
@Observable
@MainActor
final class WatchMapPackStore {
    private(set) var packs: [MapPackSummary] = []
    /// Set briefly when a pack arrives, so the UI can acknowledge it.
    private(set) var lastReceivedAt: Date?

    private var readers: [UUID: MapPackReader] = [:]
    private let bridge = MapPackBridge()

    /// Told whenever what is stored here changes, so the phone can be given a
    /// fresh inventory. The phone must never have to infer the watch's contents
    /// from what it once sent.
    var onInventoryChanged: (() -> Void)?

    /// The watch has far less room than the phone, and a workout must never fail
    /// because the disk filled. Oldest packs give way first.
    let packLimit = 6

    /// Packs this watch downloaded itself, rather than being sent.
    ///
    /// Worth remembering only so the athlete can tell, on either device, which
    /// maps came from where — a pack downloaded on the wrist will not be on the
    /// phone, and that is a fact worth showing rather than hiding.
    private var localPackIDs: Set<UUID> = []
    private let localKey = "watch.packs.local.v1"

    // Read from the nonisolated file helpers, which run on whatever thread
    // WatchConnectivity hands a pack over on.
    nonisolated private static let directoryName = "OfflineMaps"

    var totalBytes: Int {
        packs.reduce(0) { $0 + $1.fileBytes }
    }

    var totalSizeDescription: String {
        MapPackFormat.describe(bytes: totalBytes)
    }

    var hasPacks: Bool { !packs.isEmpty }

    /// Space left on the watch, as the file system reports it. Never an estimate.
    var freeBytes: Int {
        Self.freeBytes()
    }

    var freeSizeDescription: String {
        MapPackFormat.describe(bytes: freeBytes)
    }

    init() {
        if let stored = UserDefaults.standard.stringArray(forKey: localKey) {
            localPackIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        }
        loadFromDisk()
        Task { [bridge] in
            await TopoTileSource.shared.attach(local: bridge)
        }
    }

    /// Whether a route's ground is stored here.
    func hasPack(forRoute routeID: UUID) -> Bool {
        packs.contains { $0.routeID == routeID }
    }

    func pack(forRoute routeID: UUID) -> MapPackSummary? {
        packs.first { $0.routeID == routeID }
    }

    func isLocal(packID: UUID) -> Bool {
        localPackIDs.contains(packID)
    }

    // MARK: - Reporting

    /// What this watch is carrying, for the phone to show.
    func report(routes: [WatchRoute]) -> WatchInventory {
        WatchInventory(
            reportedAt: Date(),
            packs: packs.map { summary in
                WatchPackReport(
                    id: summary.id,
                    name: summary.name,
                    kind: summary.kind.rawValue,
                    createdAt: summary.createdAt,
                    routeID: summary.routeID,
                    tileCount: summary.tileCount,
                    fileBytes: summary.fileBytes,
                    isLocal: localPackIDs.contains(summary.id)
                )
            },
            routes: routes.map { route in
                WatchRouteReport(
                    id: route.id,
                    name: route.name,
                    distanceMetres: route.distance,
                    pointCount: route.points.count,
                    hasStoredMap: hasPack(forRoute: route.id)
                )
            },
            freeBytes: freeBytes,
            packLimit: packLimit
        )
    }

    // MARK: - Receiving

    /// Takes hold of a pack file the phone has just delivered.
    ///
    /// This is deliberately static and free of any actor: WatchConnectivity
    /// hands over a URL in a temporary place it reclaims the instant the
    /// delegate call returns, and it makes that call on a background thread,
    /// often having woken the app for the purpose. Hopping to the main actor
    /// first — which is what the previous version did by going through the
    /// store — could return before the bytes were safe, and the pack would be
    /// gone. So the file is moved to its final home synchronously, before
    /// anything else is allowed to happen.
    ///
    /// It also means a pack lands correctly even when nothing is listening: the
    /// file is already where `loadFromDisk` looks, so the next launch finds it.
    nonisolated static func receive(fileURL: URL, packID: UUID) -> Bool {
        do {
            let destination = try packURL(for: packID)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: fileURL, to: destination)
            return true
        } catch {
            // Moving across volumes can refuse; a copy is the fallback.
            do {
                let destination = try packURL(for: packID)
                try FileManager.default.copyItem(at: fileURL, to: destination)
                return true
            } catch {
                return false
            }
        }
    }

    /// Opens a pack already sitting on disk and puts it to work.
    ///
    /// Used both for a pack the phone just delivered and for one the watch
    /// downloaded itself, so there is a single path from "file exists" to
    /// "the map can draw it".
    func adopt(packID: UUID, isLocal: Bool = false) {
        guard let url = try? Self.packURL(for: packID) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        readers[packID] = nil
        guard let reader = try? MapPackReader(url: url) else {
            // A damaged pack is worse than no pack: it would draw holes in
            // ground the athlete was told they had.
            try? FileManager.default.removeItem(at: url)
            return
        }
        readers[packID] = reader

        if isLocal {
            localPackIDs.insert(packID)
        }

        trimToLimit()
        bridge.replace(readers: Array(readers.values))
        refreshSummaries()
        persistLocalIDs()
        lastReceivedAt = Date()
        onInventoryChanged?()

        // Ground already fetched over the network for this area should give
        // way to the pack, which is on disk and needs no signal.
        Task { await TopoTileSource.shared.purge() }
    }

    // MARK: - Deleting

    func delete(packID: UUID) {
        readers[packID] = nil
        localPackIDs.remove(packID)
        if let url = try? Self.packURL(for: packID) {
            try? FileManager.default.removeItem(at: url)
        }
        bridge.replace(readers: Array(readers.values))
        refreshSummaries()
        persistLocalIDs()
        onInventoryChanged?()
        Task { await TopoTileSource.shared.purge() }
    }

    func deleteAll() {
        for id in readers.keys {
            if let url = try? Self.packURL(for: id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        readers.removeAll()
        localPackIDs.removeAll()
        bridge.replace(readers: [])
        refreshSummaries()
        persistLocalIDs()
        onInventoryChanged?()
        Task { await TopoTileSource.shared.purge() }
    }

    /// Drops the oldest packs once there are too many.
    private func trimToLimit() {
        guard readers.count > packLimit else { return }
        let ordered = readers.values
            .map(\.summary)
            .sorted { $0.createdAt < $1.createdAt }
        let excess = ordered.prefix(readers.count - packLimit)
        for summary in excess {
            readers[summary.id] = nil
            localPackIDs.remove(summary.id)
            if let url = try? Self.packURL(for: summary.id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Disk

    nonisolated static func directory() throws -> URL {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            throw MapPackError.malformed
        }
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    nonisolated static func packURL(for id: UUID) throws -> URL {
        try directory().appendingPathComponent("\(id.uuidString).trekkapack")
    }

    /// Free space on the watch, straight from the file system.
    ///
    /// `volumeAvailableCapacityForImportantUsage` — the figure the phone would
    /// use — does not exist on watchOS, so this reads the plain free size. It
    /// is the more conservative of the two anyway, which is the right way to be
    /// wrong when deciding whether a download will fit.
    nonisolated static func freeBytes() -> Int {
        guard let directory = try? directory(),
              let attributes = try? FileManager.default.attributesOfFileSystem(
                  forPath: directory.path
              ),
              let free = attributes[.systemFreeSize] as? NSNumber else {
            return 0
        }
        return free.intValue
    }

    private func loadFromDisk() {
        guard let directory = try? Self.directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return }

        for file in files where file.pathExtension == "trekkapack" {
            guard let reader = try? MapPackReader(url: file) else {
                // A damaged pack would draw holes in ground the athlete was
                // told they had, which is worse than having no pack at all.
                try? FileManager.default.removeItem(at: file)
                continue
            }
            readers[reader.summary.id] = reader
        }

        bridge.replace(readers: Array(readers.values))
        refreshSummaries()
    }

    private func refreshSummaries() {
        packs = readers.values.map(\.summary).sorted { $0.createdAt > $1.createdAt }
    }

    private func persistLocalIDs() {
        UserDefaults.standard.set(localPackIDs.map(\.uuidString), forKey: localKey)
    }
}
