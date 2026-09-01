import SwiftUI

/// Stealth-black visual system with Ultra-orange accents, tuned for the small screen.
nonisolated enum WatchTheme {
    static let canvas = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.122)
    static let surfaceRaised = Color(red: 0.145, green: 0.145, blue: 0.165)
    static let border = Color(red: 0.196, green: 0.196, blue: 0.220)
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.075)
    static let highlight = Color(red: 1.0, green: 0.831, blue: 0.286)
    static let textPrimary = Color(red: 0.937, green: 0.937, blue: 0.945)
    static let textSecondary = Color(red: 0.937, green: 0.937, blue: 0.945).opacity(0.55)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let positive = Color(red: 0.32, green: 0.85, blue: 0.55)

    static let cardRadius: CGFloat = 10

    /// Five-step heart-rate zone ramp: cool blue through red.
    static let zoneColors: [Color] = [
        Color(red: 0.24, green: 0.55, blue: 0.98),
        Color(red: 0.11, green: 0.78, blue: 0.71),
        Color(red: 0.95, green: 0.77, blue: 0.24),
        Color(red: 1.0, green: 0.42, blue: 0.08),
        Color(red: 1.0, green: 0.22, blue: 0.19),
    ]

    static func zoneColor(_ zone: Int) -> Color {
        let index = max(0, min(zoneColors.count - 1, zone - 1))
        return zoneColors[index]
    }
}

/// Matte card surface with a hairline border, matching the phone app's panels.
struct WatchPanel: ViewModifier {
    var radius: CGFloat = WatchTheme.cardRadius
    var fill: Color = WatchTheme.surface

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(WatchTheme.border, lineWidth: 0.75)
            }
    }
}

extension View {
    func watchPanel(radius: CGFloat = WatchTheme.cardRadius, fill: Color = WatchTheme.surface) -> some View {
        modifier(WatchPanel(radius: radius, fill: fill))
    }

    /// Uppercase tracking-wide caption used above every metric readout.
    func fieldLabelStyle(_ tint: Color = WatchTheme.textSecondary) -> some View {
        self
            .font(.watch(10, weight: .semibold))
            .textCase(.uppercase)
            .kerning(WatchDisplay.isCompact ? 0.2 : 0.5)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

extension Font {
    /// Tabular rounded numerals for every metric readout, sized for this watch.
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: WatchDisplay.fontSize(size), weight: weight, design: .rounded).monospacedDigit()
    }

    /// Body and label type, sized for this watch. Every point size in the watch
    /// app is written for a 45 mm and scaled from there.
    static func watch(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: WatchDisplay.fontSize(size), weight: weight)
    }
}
