import SwiftUI

/// What the workout's action control does — on screen, and through the physical
/// gestures watchOS lets an app claim.
///
/// Apple reserves the side button and the Digital Crown press for the system
/// (Dock, Siri, the power menu, Emergency SOS), and no app can take them. What
/// an app *can* claim is the primary action: on Series 9, Ultra 2 and later that
/// is the double tap of finger and thumb, and through AssistiveTouch it is
/// whatever gesture the athlete has bound there. Apple Watch Ultra's Action
/// button reaches it through a Shortcut.
///
/// So this is the honest version of "use the physical buttons": one action,
/// chosen by the athlete, reachable without looking at the screen and without
/// swiping to a menu with wet or gloved hands.
nonisolated enum WatchQuickAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case pauseResume
    case lap
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pauseResume: "Pause / resume"
        case .lap: "Lap"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .pauseResume: "Stops and restarts the clock"
        case .lap: "Banks a lap and starts the next"
        case .off: "No action button on the workout screen"
        }
    }

    var isEnabled: Bool { self != .off }

    /// The glyph for the current state, so a paused workout offers "resume"
    /// rather than repeating the word it was already showing.
    func symbol(isPaused: Bool) -> String {
        switch self {
        case .pauseResume: isPaused ? "play.fill" : "pause.fill"
        case .lap: "flag.fill"
        case .off: "circle"
        }
    }

    func label(isPaused: Bool) -> String {
        switch self {
        case .pauseResume: isPaused ? "Resume" : "Pause"
        case .lap: "Lap"
        case .off: ""
        }
    }
}
