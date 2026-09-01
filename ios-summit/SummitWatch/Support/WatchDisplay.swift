import SwiftUI
import WatchKit

/// The three broad sizes of Apple Watch this app runs on.
enum WatchDisplayClass {
    /// 40 mm and 41 mm — the tightest screens, where fixed type overflows first.
    case compact
    /// 42 mm, 44 mm and 45 mm.
    case standard
    /// 46 mm and the 49 mm Ultra.
    case large
}

/// One place that knows how big this particular watch actually is.
///
/// A layout tuned on a 45 mm is roughly 23% too tall for a 40 mm, which is the
/// difference between a workout page you read at a glance and one you have to
/// scroll mid-climb. Every size in the watch app is written against a 45 mm
/// reference and passed through here, so the same page fits every wrist.
enum WatchDisplay {
    static let size: CGSize = WKInterfaceDevice.current().screenBounds.size

    /// Reference geometry: Series 7–9 45 mm.
    private static let referenceWidth: CGFloat = 198
    private static let referenceHeight: CGFloat = 242

    /// How this watch compares with the reference, limited at both ends so the
    /// smallest screen stays legible and the Ultra does not look cartoonish.
    static let scale: CGFloat = {
        let raw = min(size.width / referenceWidth, size.height / referenceHeight)
        return min(1.06, max(0.78, raw))
    }()

    static let displayClass: WatchDisplayClass = {
        if size.width < 176 { return .compact }
        if size.width < 200 { return .standard }
        return .large
    }()

    static var isCompact: Bool { displayClass == .compact }

    /// How many readouts this particular watch can hold — the layout builder's
    /// limits, derived from the same size class the renderer scales by.
    static let capacity = WatchScreenCapacity.forScreen(width: size.width)

    /// Scales a point size that was designed against the 45 mm reference.
    /// - Parameter atLeast: a floor for things that stop working when too small,
    ///   such as tap targets and the smallest legible label.
    static func scaled(_ points: CGFloat, atLeast floor: CGFloat = 0) -> CGFloat {
        max(floor, (points * scale).rounded())
    }

    /// Type scales a little more gently than layout: shrinking a 9 pt caption by
    /// the full factor makes it unreadable, so small text keeps more of its size.
    static func fontSize(_ points: CGFloat) -> CGFloat {
        let gentleness = points < 14 ? 0.55 : 1.0
        let factor = 1 - (1 - scale) * gentleness
        return max(7.5, (points * factor).rounded(.toNearestOrEven))
    }

    /// Vertical breathing room, which is the first thing worth surrendering on a
    /// small screen and the first thing worth spending on an Ultra.
    static func spacing(_ points: CGFloat) -> CGFloat {
        max(2, (points * scale).rounded())
    }
}
