import Foundation
import Observation

/// Owns the offline maps stored on the watch.
///
/// The phone builds a pack and ships it across as a single file; this saves it,
/// hands it to the map renderer, and keeps the watch's storage in check. Once a
/// pack has landed the map draws with no phone and no signal, which is the whole
/// point of the exercise.
@Observable
@MainActor
final class WatchMapPackStore {
    private(set) var packs: [MapPackSummary] = []
    /// Set briefly when a pack arrives, so the UI can acknowledge it.
    private(set) var lastReceivedAt: Date?

    private var readers: [UUID: MapPackReader] = [:]
    private let bridge = MapPackBridge()
    private let directoryName = "OfflineMaps"

    /// The watch has far less room than the phone, and a workout must never fail
    /// because the disk filled. Oldest packs give way first.
    private let packLimit = 6

    var totalBytes: Int {
        packs.reduce(0) { $0 + $1.fileBytes }
    }

    var totalSizeDescription: String {
        MapPackFormat.describe(bytes: totalBytes)
    }

    var hasPacks: Bool { !packs.isEmpty }

    init() {
        loadFromDisk()
        Task { [bridge] in
            await TopoTileSource.shared.attach(local: bridge)
        }
    }

    /// Whether a route's ground is stored here.
    func hasPack(forRoute routeID: UUID) -> Bool {
        packs.contains { $0.routeID == routeID }
    }

    // MARK: - Receiving

    /// Takes a pack file delivered by the phone.
    ///
    /// WatchConnectivity hands over a URL in a temporary place that it reclaims
    /// as soon as this returns, so the file is moved before anything else.
    func ingest(fileURL: URL, packID: UUID) {
        do {
            let destination = try self.fileURL(for: packID)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: fileURL, to: destination)

            readers[packID] = nil
            let reader = try MapPackReader(url: destination)
            readers[packID] = reader

            trimToLimit()
            bridge.replace(readers: Array(readers.values))
            refreshSummaries()
            lastReceivedAt = Date()

            // Ground already fetched over the network for this area should give
            // way to the pack, which is on disk and needs no signal.
            Task { await TopoTileSource.shared.purge() }
        } catch {
            // A pack that cannot be stored is simply absent; the map falls back
            // to fetching online, and the route line still navigates offline.
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Deleting

    func delete(packID: UUID) {
        readers[packID] = nil
        if let url = try? fileURL(for: packID) {
            try? FileManager.default.removeItem(at: url)
        }
        bridge.replace(readers: Array(readers.values))
        refreshSummaries()
        Task { await TopoTileSource.shared.purge() }
    }

    func deleteAll() {
        for id in readers.keys {
            if let url = try? fileURL(for: id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        readers.removeAll()
        bridge.replace(readers: [])
        refreshSummaries()
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
            if let url = try? fileURL(for: summary.id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Disk

    private func directory() throws -> URL {
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

    private func fileURL(for id: UUID) throws -> URL {
        try directory().appendingPathComponent("\(id.uuidString).trekkapack")
    }

    private func loadFromDisk() {
        guard let directory = try? directory(),
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
}
