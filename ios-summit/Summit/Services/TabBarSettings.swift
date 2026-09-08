import Foundation
import Observation
// `move(fromOffsets:toOffset:)` on Array is SwiftUI's, not Foundation's.
import SwiftUI

/// Which screens sit in the bottom bar, and in what order.
nonisolated struct TabBarPreferences: Codable, Sendable, Equatable {
    var order: [AppTab]
    var hidden: [AppTab]

    /// Seven screens will not fit a bottom bar, so Trekka's own arrangement
    /// hides the calendar by default — it is the one whose job the log and the
    /// insights screen both partly do. Anybody who lives in it can switch it
    /// back on, and anybody upgrading keeps whatever they already had.
    static let standard = TabBarPreferences(
        order: [.today, .routes, .activities, .insights, .fuel, .calendar, .settings],
        hidden: [.calendar]
    )

    /// Repairs stored data when tabs are added or removed between versions, and
    /// enforces the two rules the bar cannot break.
    func normalized() -> TabBarPreferences {
        let known = Set(AppTab.allCases)
        var repaired = self
        repaired.order = order.filter { known.contains($0) }
        for tab in AppTab.allCases where !repaired.order.contains(tab) {
            repaired.order.append(tab)
        }
        repaired.hidden = hidden.filter { known.contains($0) }

        // Settings can never be hidden. It is the only way back to this screen,
        // and a bar with no way to undo its own arrangement is a trap.
        repaired.hidden.removeAll { $0 == .settings }

        // At least one screen besides Settings has to survive, or the app opens
        // onto its own preferences.
        let visible = repaired.order.filter { !repaired.hidden.contains($0) }
        if visible.count <= 1 {
            repaired.hidden.removeAll { $0 == .today }
        }
        return repaired
    }
}

/// The athlete's own bottom bar, persisted between launches.
///
/// Six tabs is one more than the bar comfortably holds, and which of them earns
/// a permanent slot is genuinely personal: somebody logging every meal wants
/// Fuel where their thumb already is, and somebody who never opens the calendar
/// should not be paying screen width for it.
@Observable
final class TabBarSettings {
    private var preferences: TabBarPreferences

    private let defaultsKey = "tabbar.preferences.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "tabbar.preferences.v1"),
           let stored = try? JSONDecoder().decode(TabBarPreferences.self, from: data) {
            preferences = stored.normalized()
        } else {
            preferences = .standard
        }
    }

    /// The tabs actually drawn in the bar, in the athlete's order.
    var visibleTabs: [AppTab] {
        preferences.order.filter { !preferences.hidden.contains($0) }
    }

    var hiddenTabs: [AppTab] {
        preferences.order.filter { preferences.hidden.contains($0) }
    }

    /// The order used by the editor, which lists everything including hidden.
    var allTabsInOrder: [AppTab] { preferences.order }

    func isVisible(_ tab: AppTab) -> Bool {
        !preferences.hidden.contains(tab)
    }

    /// Settings stays put, and the bar keeps at least one other screen.
    func canHide(_ tab: AppTab) -> Bool {
        guard tab != .settings else { return false }
        guard isVisible(tab) else { return true }
        return visibleTabs.count > 2
    }

    func toggle(_ tab: AppTab) {
        if preferences.hidden.contains(tab) {
            preferences.hidden.removeAll { $0 == tab }
        } else {
            guard canHide(tab) else { return }
            preferences.hidden.append(tab)
        }
        preferences = preferences.normalized()
        persist()
    }

    /// Reorders the whole list, hidden entries included, so a tab keeps its place
    /// when it is switched back on.
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        preferences.order.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    func resetToDefaults() {
        preferences = .standard
        persist()
    }

    // MARK: - Backup

    var snapshot: TabBarPreferences { preferences }

    func restore(_ restored: TabBarPreferences) {
        preferences = restored.normalized()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
