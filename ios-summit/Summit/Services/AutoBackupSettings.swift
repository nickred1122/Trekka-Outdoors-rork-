import Foundation
import Observation

/// How often Trekka should back itself up without being asked.
nonisolated enum BackupSchedule: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var detail: String {
        switch self {
        case .off: "Back up only when you tap Back up now"
        case .daily: "Once a day, when you next open Trekka"
        case .weekly: "Once a week, when you next open Trekka"
        }
    }

    /// How long between backups, or nil when automatic backup is off.
    var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }
}

/// Whether the last automatic attempt worked, so the backup screen can be
/// honest without nagging anywhere else in the app.
nonisolated enum AutoBackupOutcome: Equatable, Sendable {
    case succeeded
    case failed(String)
}

/// Runs the iCloud backup on a schedule.
///
/// Deliberately opportunistic rather than a background task: iOS gives no
/// guarantee about when a background window arrives, and a backup that claims to
/// be daily but silently is not would be worse than one that plainly runs when
/// the app is next opened. So it runs on launch and on returning to the app, and
/// says exactly when it last succeeded.
@Observable
final class AutoBackupSettings {
    private static let scheduleKey = "backup.auto.schedule.v1"
    private static let lastRunKey = "backup.auto.lastRun.v1"

    private(set) var schedule: BackupSchedule
    /// When a backup last completed — automatic or manual, since either one
    /// makes the next automatic run unnecessary.
    private(set) var lastRunAt: Date?
    private(set) var lastOutcome: AutoBackupOutcome?
    private(set) var isRunning = false

    /// Stops a failing account being retried on every trip back into the app.
    private var nextAttemptAfter: Date?
    private static let retryDelay: TimeInterval = 60 * 60

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.scheduleKey)
        schedule = stored.flatMap(BackupSchedule.init(rawValue:)) ?? .off
        let last = UserDefaults.standard.double(forKey: Self.lastRunKey)
        lastRunAt = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    func setSchedule(_ newSchedule: BackupSchedule) {
        guard newSchedule != schedule else { return }
        schedule = newSchedule
        UserDefaults.standard.set(newSchedule.rawValue, forKey: Self.scheduleKey)
        // A fresh choice deserves a fresh attempt, even if the last one failed.
        nextAttemptAfter = nil
        lastOutcome = nil
    }

    /// Records a completed backup, whoever started it.
    func recordBackup(at date: Date = .now) {
        lastRunAt = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastRunKey)
    }

    /// Whether a backup is owed right now.
    func isDue(now: Date = .now) -> Bool {
        guard let interval = schedule.interval else { return false }
        if let nextAttemptAfter, now < nextAttemptAfter { return false }
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= interval
    }

    /// When the next automatic backup is expected, for display.
    var nextRunAt: Date? {
        guard let interval = schedule.interval, let lastRunAt else { return nil }
        return lastRunAt.addingTimeInterval(interval)
    }

    /// Backs up everything if the schedule says one is owed.
    ///
    /// Silent by design: this runs while the athlete is doing something else, so
    /// a failure is recorded for the backup screen rather than thrown in front
    /// of whatever they actually opened the app to do.
    func runIfDue(cloud: CloudBackupService, stores: BackupStores) async {
        guard isDue(), !isRunning, !cloud.isWorking else { return }

        isRunning = true
        defer { isRunning = false }

        // The account state is checked first: with no iCloud account this is not
        // a failure worth reporting every hour, it is simply not set up.
        if !cloud.availability.isReady {
            await cloud.refresh()
        }
        guard cloud.availability.isReady else {
            nextAttemptAfter = Date().addingTimeInterval(Self.retryDelay)
            return
        }

        let sections = Set(BackupSection.allCases)
        let archive = BackupArchive.make(sections: sections, from: stores)
        let stored = await cloud.backUp(archive, sections: sections)

        if stored {
            recordBackup()
            lastOutcome = .succeeded
            nextAttemptAfter = nil
        } else {
            lastOutcome = .failed(cloud.lastError ?? "iCloud could not be reached.")
            nextAttemptAfter = Date().addingTimeInterval(Self.retryDelay)
        }
    }
}
