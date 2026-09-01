import SwiftUI

/// Rotation that never takes the long way round.
///
/// Bearings are reported in 0–360, so walking north makes the heading flip
/// between 359 and 1. Fed straight into `rotationEffect` with an animation
/// attached, SwiftUI does exactly what it is told and animates the 358 degrees
/// *backwards* — the compass and the reroute arrow both spun a full turn in the
/// wrong direction every time the athlete crossed north, which is precisely the
/// moment a navigation arrow has to be trustworthy.
///
/// This keeps a continuous angle that is free to run past 360 or below zero, and
/// moves it by the shortest equivalent step each time. The angle shown is always
/// the same direction on screen; only the number behind it keeps counting.
struct CompassRotation: ViewModifier {
    let degrees: Double
    var animation: Animation = .easeOut(duration: 0.35)

    /// Nil until the first reading, so the view appears already pointing the
    /// right way rather than swinging round from zero as it opens.
    @State private var continuous: Double?

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(continuous ?? degrees))
            .animation(animation, value: continuous)
            .onChange(of: degrees, initial: true) { _, target in
                continuous = Self.shortestEquivalent(of: target, from: continuous)
            }
    }

    /// The value closest to `current` that points the same way as `target`.
    static func shortestEquivalent(of target: Double, from current: Double?) -> Double {
        guard let current, current.isFinite, target.isFinite else { return target }
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return current + delta
    }
}

extension View {
    /// Rotates to a compass bearing by the shortest way round.
    func compassRotation(
        degrees: Double,
        animation: Animation = .easeOut(duration: 0.35)
    ) -> some View {
        modifier(CompassRotation(degrees: degrees, animation: animation))
    }
}
