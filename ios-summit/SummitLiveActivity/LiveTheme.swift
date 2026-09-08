import SwiftUI

/// Trekka's palette, restated here because an extension cannot see the app's
/// theme. These are the same values as `Theme.accent` and friends.
nonisolated enum LiveTheme {
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.075)
    static let paused = Color(red: 1.0, green: 0.831, blue: 0.286)
    static let positive = Color(red: 0.32, green: 0.85, blue: 0.55)
    static let canvas = Color(red: 0.071, green: 0.075, blue: 0.067)
    static let label = Color.white
}
