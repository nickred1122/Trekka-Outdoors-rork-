import SwiftUI

/// The colours a course line or breadcrumb trail can be drawn in.
///
/// Mirrors the watch's own `TrailColor` case for case, including raw values:
/// the two devices exchange these as strings inside the layout document, so a
/// colour chosen on the phone has to name the same colour on the wrist.
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

    static func resolve(_ rawValue: String?) -> TrailColor? {
        guard let rawValue else { return nil }
        return TrailColor(rawValue: rawValue)
    }
}

/// The live line colours, mirrored here by `WatchLayoutStore`.
///
/// Same reasoning as `Formatters.units`: every map surface in the app has to
/// draw the course the same colour, and threading the preference through every
/// map card, route row and workout screen would put it in a dozen initialisers
/// for no benefit.
nonisolated enum TrailStyle {
    static var route: TrailColor = .orange
    static var breadcrumb: TrailColor = .amber
}
