import Foundation

/// The watch's metric type choices, as named options rather than loose strings.
///
/// The store persists these as strings because the watch decodes the same
/// document, but every screen that offers them needs the same list in the same
/// order with the same names — so the list lives here once instead of being
/// retyped as picker rows.
nonisolated enum MetricTypefaceOption: String, CaseIterable, Identifiable, Sendable {
    case rounded, instrument, classic, serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .instrument: "Instrument"
        case .classic: "Classic"
        case .serif: "Serif"
        }
    }

    /// The stored value's name, falling back to the default rather than showing
    /// a document written by a newer version as blank.
    static func title(for raw: String) -> String {
        Self(rawValue: raw)?.title ?? Self.rounded.title
    }
}

nonisolated enum MetricWeightOption: String, CaseIterable, Identifiable, Sendable {
    case light, standard, heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .standard: "Standard"
        case .heavy: "Heavy"
        }
    }

    static func title(for raw: String) -> String {
        Self(rawValue: raw)?.title ?? Self.standard.title
    }
}

nonisolated enum MetricTintOption: String, CaseIterable, Identifiable, Sendable {
    case auto, mono, orange, amber, lime, cyan, blue, violet, magenta

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

    static func title(for raw: String) -> String {
        Self(rawValue: raw)?.title ?? Self.auto.title
    }
}
