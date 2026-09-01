import Foundation

/// One kind of data the athlete can back up, restore, export or import.
///
/// The raw values are also the record names used in iCloud, so renaming a case
/// would orphan an existing backup — add a case instead.
nonisolated enum BackupSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case routes
    case activities
    case watchSetup
    case appSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: "Routes"
        case .activities: "Activities"
        case .watchSetup: "Watch screens"
        case .appSettings: "App settings"
        }
    }

    var symbol: String {
        switch self {
        case .routes: "map"
        case .activities: "waveform.path.ecg"
        case .watchSetup: "applewatch"
        case .appSettings: "slider.horizontal.3"
        }
    }

    var detail: String {
        switch self {
        case .routes: "Planned and imported routes, with their tracks and waypoints"
        case .activities: "Workouts Trekka recorded, including their GPS tracks"
        case .watchSetup: "Data screens, layouts, alerts, power saver and max heart rate"
        case .appSettings: "Dashboard tiles, units and appearance"
        }
    }

    /// Whether a restore can add to what is already on the phone rather than
    /// only standing in for it. A single settings document can only be replaced.
    var supportsMerging: Bool {
        switch self {
        case .routes, .activities: true
        case .watchSetup, .appSettings: false
        }
    }

    /// The order sections are presented and written in.
    static let ordered: [BackupSection] = [.routes, .activities, .watchSetup, .appSettings]
}

/// The watch document exactly as the watch reads it, so a restore puts back the
/// same bytes rather than a re-encoded approximation.
nonisolated struct WatchSetupArchive: Codable, Sendable {
    var document: Data
    /// Kept alongside so a backup can be described without decoding the document.
    var customizedSports: Int
}

/// Everything that configures the phone app itself.
nonisolated struct AppSettingsArchive: Codable, Sendable {
    var dashboard: DashboardPreferences?
    var appearance: String?
    var units: String?
}

/// A snapshot of the athlete's Trekka data, used for both iCloud backups and
/// exported files — one format, so a file restores the same way a backup does.
nonisolated struct SummitArchive: Codable, Sendable {
    /// Bumped only for changes older builds could not read correctly.
    static let currentFormat = 1

    var format: Int
    var createdAt: Date
    var deviceName: String
    var appVersion: String

    var routes: [PlannedRoute]?
    var activities: [ActivityRecord]?
    var watchSetup: WatchSetupArchive?
    var appSettings: AppSettingsArchive?

    init(
        format: Int = SummitArchive.currentFormat,
        createdAt: Date = .now,
        deviceName: String,
        appVersion: String,
        routes: [PlannedRoute]? = nil,
        activities: [ActivityRecord]? = nil,
        watchSetup: WatchSetupArchive? = nil,
        appSettings: AppSettingsArchive? = nil
    ) {
        self.format = format
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.routes = routes
        self.activities = activities
        self.watchSetup = watchSetup
        self.appSettings = appSettings
    }
}

// MARK: - Contents

extension SummitArchive {
    func contains(_ section: BackupSection) -> Bool {
        switch section {
        case .routes: routes != nil
        case .activities: activities != nil
        case .watchSetup: watchSetup != nil
        case .appSettings: appSettings != nil
        }
    }

    var includedSections: [BackupSection] {
        BackupSection.ordered.filter(contains)
    }

    var isEmpty: Bool { includedSections.isEmpty }

    /// How much of a section a backup holds, phrased for display. `nil` when the
    /// section is not in this archive at all.
    func summary(for section: BackupSection) -> String? {
        switch section {
        case .routes:
            guard let routes else { return nil }
            return "\(routes.count) route\(routes.count == 1 ? "" : "s")"
        case .activities:
            guard let activities else { return nil }
            return "\(activities.count) activit\(activities.count == 1 ? "y" : "ies")"
        case .watchSetup:
            guard let watchSetup else { return nil }
            return watchSetup.customizedSports == 0
                ? "Default screens"
                : "\(watchSetup.customizedSports) custom sport layout\(watchSetup.customizedSports == 1 ? "" : "s")"
        case .appSettings:
            guard appSettings != nil else { return nil }
            return "Dashboard, units and appearance"
        }
    }

    /// The same archive carrying only one section, which is how each section is
    /// written to iCloud so it can be restored on its own.
    func slice(_ section: BackupSection) -> SummitArchive {
        SummitArchive(
            format: format,
            createdAt: createdAt,
            deviceName: deviceName,
            appVersion: appVersion,
            routes: section == .routes ? routes : nil,
            activities: section == .activities ? activities : nil,
            watchSetup: section == .watchSetup ? watchSetup : nil,
            appSettings: section == .appSettings ? appSettings : nil
        )
    }

    /// Folds another archive's sections into this one, keeping the newer stamp.
    /// Used to rebuild one archive from the per-section records in iCloud.
    func merging(_ other: SummitArchive) -> SummitArchive {
        SummitArchive(
            format: max(format, other.format),
            createdAt: max(createdAt, other.createdAt),
            deviceName: other.createdAt > createdAt ? other.deviceName : deviceName,
            appVersion: other.createdAt > createdAt ? other.appVersion : appVersion,
            routes: other.routes ?? routes,
            activities: other.activities ?? activities,
            watchSetup: other.watchSetup ?? watchSetup,
            appSettings: other.appSettings ?? appSettings
        )
    }
}

// MARK: - Coding

nonisolated enum BackupError: LocalizedError, Equatable {
    case unreadable
    case tooNew(Int)
    case nothingSelected
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "That file is not a Trekka backup, or it has been damaged."
        case .tooNew:
            "This backup was made by a newer version of Trekka. Update the app, then try again."
        case .nothingSelected:
            "Choose at least one kind of data first."
        case .emptyArchive:
            "That backup does not contain any Trekka data."
        }
    }
}

extension SummitArchive {
    /// Dates travel as ISO-8601 so an exported file stays readable and stable
    /// across devices and locales.
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decode(_ data: Data) throws -> SummitArchive {
        guard let archive = try? decoder().decode(SummitArchive.self, from: data) else {
            throw BackupError.unreadable
        }
        guard archive.format <= currentFormat else { throw BackupError.tooNew(archive.format) }
        guard !archive.isEmpty else { throw BackupError.emptyArchive }
        return archive
    }

    /// The filename an export is offered under, dated so several sit together
    /// in a folder without overwriting one another.
    var suggestedFilename: String {
        let stamp = createdAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Trekka Backup \(stamp)"
    }
}
