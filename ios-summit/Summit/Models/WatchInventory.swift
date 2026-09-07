import Foundation

/// One offline map stored on the watch, as the watch itself reports it.
///
/// `kind` travels as a string rather than `MapPackKind` on purpose: a kind added
/// on one side must not make the whole inventory fail to decode on the other,
/// and an unknown kind is still worth listing with its name and size.
nonisolated struct WatchPackReport: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var kind: String
    var createdAt: Date
    var routeID: UUID?
    var tileCount: Int
    var fileBytes: Int
    /// True when the watch downloaded this itself rather than being sent it.
    var isLocal: Bool

    var sizeDescription: String {
        MapPackFormat.describe(bytes: fileBytes)
    }
}

/// One route cached on the watch.
nonisolated struct WatchRouteReport: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var distanceMetres: Double
    var pointCount: Int
    /// Whether the ground under this route is stored on the watch.
    var hasStoredMap: Bool
}

/// Everything the watch is carrying, reported by the watch so the phone never
/// has to guess.
///
/// The phone used to infer the watch's contents from what it had sent, which is
/// not the same thing: a transfer can fail, the watch trims its own storage when
/// space runs short, and the watch can now download maps on its own. Only the
/// watch knows what is actually on it, so only the watch is allowed to say.
nonisolated struct WatchInventory: Codable, Sendable {
    var reportedAt: Date
    var packs: [WatchPackReport]
    var routes: [WatchRouteReport]
    /// Space still free on the watch, as its file system reports it.
    var freeBytes: Int
    /// How many packs the watch will hold before dropping its oldest.
    var packLimit: Int

    var packBytes: Int {
        packs.reduce(0) { $0 + $1.fileBytes }
    }

    var packBytesDescription: String {
        MapPackFormat.describe(bytes: packBytes)
    }

    var freeBytesDescription: String {
        MapPackFormat.describe(bytes: freeBytes)
    }

    func pack(forRoute routeID: UUID) -> WatchPackReport? {
        packs.first { $0.routeID == routeID }
    }

    func hasPack(id: UUID) -> Bool {
        packs.contains { $0.id == id }
    }
}
