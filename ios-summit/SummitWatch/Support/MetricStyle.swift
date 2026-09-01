import SwiftUI

/// The typeface every metric readout on the watch is drawn in.
///
/// A number read at arm's length, mid-effort, in bright sun is a different
/// problem from a number read at a desk, and athletes genuinely disagree about
/// the answer — some want the softness of rounded digits, some want the hard
/// edges of an instrument panel. So it is a choice rather than our taste.
nonisolated enum MetricTypeface: String, CaseIterable, Codable, Sendable, Identifiable {
    case rounded
    case instrument
    case classic
    case serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .instrument: "Instrument"
        case .classic: "Classic"
        case .serif: "Serif"
        }
    }

    var detail: String {
        switch self {
        case .rounded: "Soft numerals, Trekka's default"
        case .instrument: "Squared off, like a bike computer"
        case .classic: "The system typeface"
        case .serif: "Printed map lettering"
        }
    }

    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .instrument: .monospaced
        case .classic: .default
        case .serif: .serif
        }
    }
}

/// The colour a metric's value is drawn in.
///
/// `auto` leaves each page's own judgement alone — heart rate in its zone
/// colour, a warning in amber — which is why it is the default. Everything
/// else overrides the lot, for anyone who wants one consistent readout colour.
nonisolated enum FieldTint: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case mono
    case orange
    case amber
    case lime
    case cyan
    case blue
    case violet
    case magenta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .mono: "Plain white"
        case .orange: "Orange"
        case .amber: "Amber"
        case .lime: "Lime"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .violet: "Violet"
        case .magenta: "Magenta"
        }
    }

    /// The swatch shown in the picker. `auto` has no single colour of its own,
    /// so it borrows the accent to stand for "whatever the page decides".
    var swatch: Color {
        resolve(WatchTheme.accent)
    }

    /// The colour to actually draw with, given whatever the page had in mind.
    func resolve(_ fallback: Color) -> Color {
        switch self {
        case .auto: fallback
        case .mono: WatchTheme.textPrimary
        case .orange: Color(red: 1.0, green: 0.416, blue: 0.075)
        case .amber: Color(red: 1.0, green: 0.831, blue: 0.286)
        case .lime: Color(red: 0.62, green: 0.94, blue: 0.20)
        case .cyan: Color(red: 0.12, green: 0.88, blue: 0.92)
        case .blue: Color(red: 0.28, green: 0.58, blue: 1.0)
        case .violet: Color(red: 0.66, green: 0.44, blue: 1.0)
        case .magenta: Color(red: 1.0, green: 0.32, blue: 0.72)
        }
    }
}

/// How thick metric numerals are drawn.
nonisolated enum MetricWeightChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case standard
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .standard: "Standard"
        case .heavy: "Heavy"
        }
    }

    /// Shifts whatever weight the call site asked for, so the relative
    /// hierarchy of a page — hero louder than a compact row — survives the
    /// athlete's choice instead of being flattened by it.
    func apply(_ weight: Font.Weight) -> Font.Weight {
        switch self {
        case .standard: return weight
        case .light:
            switch weight {
            case .black, .heavy: return .bold
            case .bold: return .semibold
            case .semibold: return .medium
            default: return .regular
            }
        case .heavy:
            switch weight {
            case .regular, .light, .thin: return .medium
            case .medium: return .semibold
            case .semibold: return .bold
            default: return .heavy
            }
        }
    }
}

/// The live metric style, mirrored here by `WatchScreenSettings`.
///
/// Kept as plain statics for the same reason `WatchFormat.units` is: every
/// metric cell, banner and summary on the wrist has to draw the same way, and
/// threading a preference down through every page and layout builder would put
/// the setting in a hundred initialisers to no benefit.
nonisolated enum MetricStyle {
    static var typeface: MetricTypeface = .rounded
    static var tint: FieldTint = .auto
    static var weight: MetricWeightChoice = .standard
}
