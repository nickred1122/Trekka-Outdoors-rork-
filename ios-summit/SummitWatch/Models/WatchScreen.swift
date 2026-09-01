import Foundation

/// The kinds of page that can appear in a workout's page carousel.
nonisolated enum WatchScreenKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case data
    case map
    case elevation
    case climb
    case upAhead
    case zones
    case laps
    case compass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: "Data Screen"
        case .map: "Map"
        case .elevation: "Elevation Profile"
        case .climb: "Climb"
        case .upAhead: "Up Ahead"
        case .zones: "Heart Rate Zones"
        case .laps: "Laps"
        case .compass: "Compass"
        }
    }

    var symbol: String {
        switch self {
        case .data: "square.grid.2x2.fill"
        case .map: "map.fill"
        case .elevation: "mountain.2.fill"
        case .climb: "arrow.up.right"
        case .upAhead: "list.bullet.below.rectangle"
        case .zones: "chart.bar.fill"
        case .laps: "flag.checkered"
        case .compass: "location.north.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .data: "Your metrics, in a layout you choose"
        case .map: "Route line, breadcrumb and waypoints"
        case .elevation: "Climb profile with your position"
        case .climb: "The climb you are on, and what is left of it"
        case .upAhead: "Every waypoint and summit still to come"
        case .zones: "Time in each heart-rate zone"
        case .laps: "Every split as you record it"
        case .compass: "Bearing and direction of travel"
        }
    }

    /// Map and compass need a location fix to be useful.
    var requiresGPS: Bool {
        self == .map || self == .compass
    }

    /// Pages that only mean anything once a course is loaded.
    var requiresRoute: Bool {
        self == .climb || self == .upAhead
    }
}

/// One page in a sport's workout carousel.
nonisolated struct WatchScreen: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: WatchScreenKind
    var fields: [WatchDataField] = []
    var isEnabled: Bool = true
    /// A chosen arrangement, or nil to let the screen arrange itself around
    /// however many metrics it holds.
    var layout: WatchScreenLayout?

    static let maxFields = WatchScreenLayout.maxSlots

    static func data(_ fields: [WatchDataField], layout: WatchScreenLayout? = nil) -> WatchScreen {
        WatchScreen(
            kind: .data,
            fields: Array(fields.prefix(layout?.slotCount ?? maxFields)),
            layout: layout
        )
    }

    static func page(_ kind: WatchScreenKind) -> WatchScreen {
        WatchScreen(kind: kind)
    }

    /// The arrangement actually drawn: the chosen one, or the automatic shape
    /// for however many metrics are on the screen.
    var resolvedLayout: WatchScreenLayout {
        layout ?? .automatic(forSlots: fields.count)
    }

    /// Grows or trims the metric list to match a layout, keeping what is already
    /// there and topping up from the sport's usual suspects.
    func fitted(to layout: WatchScreenLayout?, suggestions: [WatchDataField]) -> WatchScreen {
        var copy = self
        copy.layout = layout
        guard let layout else { return copy }
        var filled = Array(fields.prefix(layout.slotCount))
        for candidate in suggestions where filled.count < layout.slotCount {
            guard !filled.contains(candidate) else { continue }
            filled.append(candidate)
        }
        // A short suggestion list must never leave a hole in the grid.
        while filled.count < layout.slotCount {
            filled.append(.duration)
        }
        copy.fields = filled
        return copy
    }

    /// Human label used in the editor list and the page header.
    var title: String {
        guard kind == .data else { return kind.title }
        guard let first = fields.first else { return "Empty Screen" }
        if fields.count == 1 { return first.title }
        return "\(first.title) +\(fields.count - 1)"
    }

    var summary: String {
        guard kind == .data else { return kind.detail }
        guard !fields.isEmpty else { return "No metrics yet" }
        return fields.map(\.label.capitalized).joined(separator: " · ")
    }
}

// Decoding lives in an extension so the memberwise initialiser survives.
extension WatchScreen {
    private enum CodingKeys: String, CodingKey {
        case id, kind, fields, isEnabled, layout
    }

    /// Skips metrics this build does not recognise instead of failing.
    ///
    /// The watch and the phone do not always ship the same list of metrics, and
    /// the two sync by exchanging one document. Refusing the whole document over
    /// a single unknown name would silently throw away every other setting the
    /// athlete had changed — which is exactly the bug this replaced.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try container.decode(WatchScreenKind.self, forKey: .kind),
            fields: (try container.decodeIfPresent([String].self, forKey: .fields) ?? [])
                .compactMap(WatchDataField.init(rawValue:)),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            // An unrecognised pattern falls back to the automatic arrangement
            // rather than throwing the whole document away.
            layout: (try? container.decodeIfPresent(WatchScreenLayout.self, forKey: .layout)) ?? nil
        )
    }
}
