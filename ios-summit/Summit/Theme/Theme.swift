import SwiftUI
import UIKit

private extension Color {
    /// Resolves against the current trait collection, so the appearance
    /// setting (system / dark / light) restyles every surface at once.
    init(light: UIColor, dark: UIColor) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// Stealth-black visual system with Ultra-orange accents, paired with a
/// daylight palette that takes over when the app is set to light mode.
enum Theme {
    static let canvas = Color(
        light: UIColor(red: 0.957, green: 0.957, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1)
    )
    static let surface = Color(
        light: .white,
        dark: UIColor(red: 0.102, green: 0.102, blue: 0.122, alpha: 1)
    )
    static let surfaceRaised = Color(
        light: UIColor(red: 0.918, green: 0.918, blue: 0.933, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.137, blue: 0.157, alpha: 1)
    )
    static let border = Color(
        light: UIColor(red: 0.843, green: 0.843, blue: 0.867, alpha: 1),
        dark: UIColor(red: 0.165, green: 0.165, blue: 0.188, alpha: 1)
    )
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.075)
    static let highlight = Color(
        light: UIColor(red: 0.72, green: 0.42, blue: 0.0, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.831, blue: 0.286, alpha: 1)
    )
    static let textPrimary = Color(
        light: UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
        dark: UIColor(red: 0.910, green: 0.910, blue: 0.918, alpha: 1)
    )
    static let danger = Color(
        light: UIColor(red: 0.82, green: 0.13, blue: 0.10, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1)
    )
    /// Matches the watch's positive green so both devices agree.
    static let positive = Color(
        light: UIColor(red: 0.05, green: 0.52, blue: 0.28, alpha: 1),
        dark: UIColor(red: 0.32, green: 0.85, blue: 0.55, alpha: 1)
    )
    static let terrain = Color(
        light: UIColor(red: 0.929, green: 0.929, blue: 0.945, alpha: 1),
        dark: UIColor(red: 0.063, green: 0.063, blue: 0.078, alpha: 1)
    )
    static let contour = Color(
        light: UIColor(red: 0.678, green: 0.678, blue: 0.714, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.227, blue: 0.251, alpha: 1)
    )

    /// Chrome that floats over a map.
    ///
    /// Map controls sit on their own sheet rather than on the app canvas, so
    /// they need their own pair rather than reusing `surface`. Fixed black was
    /// leaving a near-black glyph on a near-black disc in light mode, which is
    /// why the locate button read as a solid black blob.
    static let mapControl = Color(
        light: UIColor(white: 1, alpha: 0.94),
        dark: UIColor(white: 0.04, alpha: 0.62)
    )
    static let mapControlBorder = Color(
        light: UIColor(white: 0, alpha: 0.14),
        dark: UIColor(white: 1, alpha: 0.14)
    )
    /// Always the opposite of `mapControl`, so a glyph can never vanish into it.
    static let mapControlLabel = Color(
        light: UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
        dark: UIColor(white: 1, alpha: 1)
    )
    /// A larger sheet over a map — the planner console, a floating card.
    /// Heavier than `mapControl` because text sits on it at length.
    static let mapPanel = Color(
        light: UIColor(white: 0.99, alpha: 0.94),
        dark: UIColor(white: 0.02, alpha: 0.78)
    )
    /// The faint wash behind an inactive control on map chrome. Tinted from the
    /// label rather than fixed white, so it darkens the sheet in daylight
    /// instead of disappearing into it.
    static let mapFill = Color(
        light: UIColor(white: 0, alpha: 0.06),
        dark: UIColor(white: 1, alpha: 0.07)
    )

    static let cardRadius: CGFloat = 16

    /// UIKit counterparts for global chrome (navigation bars), which must stay
    /// dynamic so they follow the appearance setting without reconfiguration.
    static let canvasUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1)
            : UIColor(red: 0.957, green: 0.957, blue: 0.965, alpha: 1)
    }
    static let borderUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.165, blue: 0.188, alpha: 1)
            : UIColor(red: 0.843, green: 0.843, blue: 0.867, alpha: 1)
    }
    static let textPrimaryUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.910, green: 0.910, blue: 0.918, alpha: 1)
            : UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
    }

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

/// Matte elevated card surface with a hairline border — the app's recurring container.
struct PanelBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func panel(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    /// Uppercase tracking-wide caption used for tile labels.
    func metricLabelStyle() -> some View {
        self
            .font(.system(.caption2, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
    }
}

extension Font {
    /// Tabular monospaced numerals for every metric readout.
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
