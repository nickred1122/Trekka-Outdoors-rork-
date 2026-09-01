import SwiftUI

/// The complication's slice of Summit's palette. Watch faces tint accessory
/// widgets themselves, so only the two signal colours are declared here.
nonisolated enum WidgetTheme {
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.075)
    static let positive = Color(red: 0.32, green: 0.85, blue: 0.55)
}

extension Font {
    /// Tabular numerals so the hours reading does not jitter every minute.
    static func summitMetric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
