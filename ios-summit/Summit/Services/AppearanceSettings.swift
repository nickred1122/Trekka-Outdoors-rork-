import SwiftUI

/// Where the app takes its look from: whatever the phone does, or pinned
/// dark or light regardless of the system setting.
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }

    /// `nil` follows the system, per `preferredColorScheme` semantics.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// The persisted appearance preference, applied at the app root.
@Observable
final class AppearanceSettings {
    private static let storageKey = "appearance.mode.v1"

    private(set) var mode: AppearanceMode

    /// The scheme to pin, or `nil` to follow the system.
    var colorScheme: ColorScheme? { mode.colorScheme }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        mode = stored.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    func set(_ newMode: AppearanceMode) {
        guard newMode != mode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.storageKey)
    }
}
