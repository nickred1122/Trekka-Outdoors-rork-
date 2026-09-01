import Foundation
import UIKit

/// The stores a backup reads from and restores into, gathered so the archive
/// code does not have to reach into the view tree.
@MainActor
struct BackupStores {
    let routes: RouteStore
    let watchLayout: WatchLayoutStore
    let dashboard: DashboardSettings
    let appearance: AppearanceSettings
    let units: UnitSettings
    let mapPacks: MapPackStore
}

/// What a restore does with data already on this phone.
nonisolated enum RestoreStrategy: String, CaseIterable, Identifiable, Sendable {
    /// Adds what is missing and leaves everything else alone.
    case merge
    /// Puts the phone back exactly as the backup found it.
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }

    var detail: String {
        switch self {
        case .merge: "Adds anything missing and keeps what is already on this phone."
        case .replace: "Puts this phone back exactly as the backup found it. Anything recorded since is removed."
        }
    }
}

/// Builds archives from the live stores and puts them back again.
@MainActor
enum BackupArchive {
    // MARK: - Building

    static func make(sections: Set<BackupSection>, from stores: BackupStores) -> SummitArchive {
        SummitArchive(
            deviceName: deviceName,
            appVersion: appVersion,
            routes: sections.contains(.routes) ? stores.routes.routes : nil,
            activities: sections.contains(.activities) ? stores.routes.activities : nil,
            watchSetup: sections.contains(.watchSetup) ? watchSetup(from: stores) : nil,
            appSettings: sections.contains(.appSettings) ? appSettings(from: stores) : nil
        )
    }

    private static func watchSetup(from stores: BackupStores) -> WatchSetupArchive? {
        guard let document = stores.watchLayout.archivedDocument() else { return nil }
        return WatchSetupArchive(
            document: document,
            customizedSports: stores.watchLayout.customizedSportCount
        )
    }

    private static func appSettings(from stores: BackupStores) -> AppSettingsArchive {
        AppSettingsArchive(
            dashboard: stores.dashboard.snapshot,
            appearance: stores.appearance.mode.rawValue,
            units: stores.units.system.rawValue
        )
    }

    /// What a section holds on this phone right now, phrased for display.
    static func liveSummary(for section: BackupSection, in stores: BackupStores) -> String {
        switch section {
        case .routes:
            let count = stores.routes.routes.count
            return "\(count) route\(count == 1 ? "" : "s")"
        case .activities:
            let count = stores.routes.activities.count
            return "\(count) activit\(count == 1 ? "y" : "ies")"
        case .watchSetup:
            let count = stores.watchLayout.customizedSportCount
            return count == 0 ? "Default screens" : "\(count) custom sport layout\(count == 1 ? "" : "s")"
        case .appSettings:
            return "Dashboard, units and appearance"
        }
    }

    // MARK: - Restoring

    /// Puts an archive back into the stores.
    /// - Returns: one plain line per section describing what actually changed,
    ///   so the athlete is told the result rather than just "done".
    @discardableResult
    static func apply(
        _ archive: SummitArchive,
        sections: Set<BackupSection>,
        strategy: RestoreStrategy,
        to stores: BackupStores
    ) -> [String] {
        var report: [String] = []

        if sections.contains(.routes), let routes = archive.routes {
            switch strategy {
            case .merge:
                let added = stores.routes.mergeRoutes(routes)
                report.append(added == 0 ? "Routes were already here" : "Added \(added) route\(added == 1 ? "" : "s")")
            case .replace:
                stores.routes.replaceRoutes(with: routes)
                report.append("Restored \(routes.count) route\(routes.count == 1 ? "" : "s")")
            }
        }

        if sections.contains(.activities), let activities = archive.activities {
            switch strategy {
            case .merge:
                let added = stores.routes.mergeActivities(activities)
                report.append(added == 0 ? "Activities were already here" : "Added \(added) activit\(added == 1 ? "y" : "ies")")
            case .replace:
                stores.routes.replaceActivities(with: activities)
                report.append("Restored \(activities.count) activit\(activities.count == 1 ? "y" : "ies")")
            }
        }

        // Both of these are single documents: there is no sensible way to hold
        // half of one screen layout and half of another, so they always replace.
        if sections.contains(.watchSetup), let watchSetup = archive.watchSetup {
            let restored = stores.watchLayout.restore(document: watchSetup.document)
            report.append(restored ? "Watch screens restored and sent to your watch" : "Watch screens could not be read")
        }

        if sections.contains(.appSettings), let settings = archive.appSettings {
            if let dashboard = settings.dashboard {
                stores.dashboard.restore(dashboard)
            }
            if let mode = settings.appearance.flatMap(AppearanceMode.init(rawValue:)) {
                stores.appearance.set(mode)
            }
            if let system = settings.units.flatMap(UnitSystem.init(rawValue:)) {
                stores.units.set(system)
                stores.watchLayout.unitSystem = system
            }
            report.append("App settings restored")
        }

        // Offline maps are not carried in a backup, so restored routes come back
        // with no claim to one. This puts each route's mark back in step with the
        // packs genuinely on this phone.
        if sections.contains(.routes) {
            stores.mapPacks.reconcile(with: stores.routes.routes)
        }

        return report
    }

    // MARK: - Identity

    static var deviceName: String {
        UIDevice.current.name
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
