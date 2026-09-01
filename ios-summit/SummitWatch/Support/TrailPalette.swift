import SwiftUI

/// The colours a course line or breadcrumb trail can be drawn in on the map.
///
/// Two lines share the map — the course you meant to follow and the trail you
/// actually laid — so telling them apart at a glance, in bright sun and with
/// gloves on, is the whole point of letting these be chosen.
nonisolated enum TrailColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case orange
    case amber
    case lime
    case cyan
    case blue
    case violet
    case magenta
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orange: "Orange"
        case .amber: "Amber"
        case .lime: "Lime"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .violet: "Violet"
        case .magenta: "Magenta"
        case .white: "White"
        }
    }

    var color: Color {
        switch self {
        case .orange: Color(red: 1.0, green: 0.416, blue: 0.075)
        case .amber: Color(red: 1.0, green: 0.831, blue: 0.286)
        case .lime: Color(red: 0.62, green: 0.94, blue: 0.20)
        case .cyan: Color(red: 0.12, green: 0.88, blue: 0.92)
        case .blue: Color(red: 0.28, green: 0.58, blue: 1.0)
        case .violet: Color(red: 0.66, green: 0.44, blue: 1.0)
        case .magenta: Color(red: 1.0, green: 0.32, blue: 0.72)
        case .white: Color(red: 0.97, green: 0.97, blue: 0.98)
        }
    }

    /// Falls back to the app's own accent rather than failing to draw a line.
    static func resolve(_ rawValue: String?) -> TrailColor? {
        guard let rawValue else { return nil }
        return TrailColor(rawValue: rawValue)
    }
}
