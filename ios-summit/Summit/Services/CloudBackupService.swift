import CloudKit
import Foundation
import Observation

/// Keeps a copy of the athlete's Trekka data in their own private iCloud, so a
/// lost or replaced phone does not take their routes and history with it.
///
/// Each kind of data is written as its own record, which is what makes backing
/// up and restoring one thing at a time possible, and keeps a large activity
/// history from having to be re-uploaded because a watch screen moved.
@MainActor
@Observable
final class CloudBackupService {
    /// Whether iCloud can be used at all, and why not when it cannot.
    enum Availability: Equatable {
        case checking
        case ready
        case noAccount
        case restricted
        case unavailable(String)

        var isReady: Bool { self == .ready }

        var message: String {
            switch self {
            case .checking: "Checking iCloud…"
            case .ready: "Signed in and ready"
            case .noAccount: "Sign in to iCloud in Settings to back up"
            case .restricted: "iCloud is restricted on this device"
            case .unavailable(let reason): reason
            }
        }
    }

    /// What iCloud is holding for one section, read without downloading it.
    struct RemoteSection: Equatable, Sendable {
        var updatedAt: Date
        var summary: String
        var deviceName: String
    }

    private(set) var availability: Availability = .checking
    private(set) var remote: [BackupSection: RemoteSection] = [:]
    /// What is happening right now, phrased for display. `nil` when idle.
    private(set) var activity: String?
    private(set) var lastError: String?

    /// The most recent moment any section was written.
    var lastBackupAt: Date? {
        remote.values.map(\.updatedAt).max()
    }

    var hasBackup: Bool { !remote.isEmpty }

    var isWorking: Bool { activity != nil }

    private static let recordType = "SummitBackup"
    private static let payloadKey = "payload"
    private static let updatedAtKey = "updatedAt"
    private static let summaryKey = "summary"
    private static let deviceKey = "deviceName"
    private static let formatKey = "format"

    private let container = CKContainer.default()
    private var database: CKDatabase { container.privateCloudDatabase }

    // MARK: - Status

    /// Re-reads the iCloud account state and what is already stored. Cheap: the
    /// backup payloads themselves are deliberately left on the server.
    func refresh() async {
        lastError = nil
        do {
            switch try await container.accountStatus() {
            case .available:
                availability = .ready
            case .noAccount:
                availability = .noAccount
                remote = [:]
                return
            case .restricted:
                availability = .restricted
                remote = [:]
                return
            case .couldNotDetermine, .temporarilyUnavailable:
                availability = .unavailable("iCloud is not responding. Try again in a moment.")
                return
            @unknown default:
                availability = .unavailable("iCloud is not available on this device.")
                return
            }
        } catch {
            availability = .unavailable(Self.describe(error))
            return
        }

        await loadRemoteIndex()
    }

    private func loadRemoteIndex() async {
        let ids = BackupSection.ordered.map(Self.recordID)
        do {
            let results = try await database.records(
                for: ids,
                desiredKeys: [Self.updatedAtKey, Self.summaryKey, Self.deviceKey]
            )
            var found: [BackupSection: RemoteSection] = [:]
            for (id, result) in results {
                guard let section = BackupSection(rawValue: id.recordName),
                      let record = try? result.get(),
                      let updatedAt = record[Self.updatedAtKey] as? Date else { continue }
                found[section] = RemoteSection(
                    updatedAt: updatedAt,
                    summary: record[Self.summaryKey] as? String ?? section.title,
                    deviceName: record[Self.deviceKey] as? String ?? "another device"
                )
            }
            remote = found
        } catch {
            // A missing record type simply means nothing has ever been backed
            // up, which is a normal first run rather than a failure.
            if Self.isMissingSchema(error) {
                remote = [:]
            } else {
                lastError = Self.describe(error)
            }
        }
    }

    // MARK: - Backing up

    /// Writes the selected sections to iCloud, replacing what was there before.
    /// - Returns: true when everything selected was stored.
    @discardableResult
    func backUp(_ archive: SummitArchive, sections: Set<BackupSection>) async -> Bool {
        guard !sections.isEmpty else {
            lastError = BackupError.nothingSelected.errorDescription
            return false
        }
        guard availability.isReady else {
            lastError = availability.message
            return false
        }

        lastError = nil
        activity = "Backing up to iCloud…"
        defer { activity = nil }

        var records: [CKRecord] = []
        var staged: [URL] = []
        defer { staged.forEach { try? FileManager.default.removeItem(at: $0) } }

        for section in BackupSection.ordered where sections.contains(section) {
            guard archive.contains(section) else { continue }
            do {
                let data = try archive.slice(section).encoded()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("backup-\(section.rawValue)-\(UUID().uuidString).json")
                try data.write(to: url, options: .atomic)
                staged.append(url)

                let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: section))
                record[Self.payloadKey] = CKAsset(fileURL: url)
                record[Self.updatedAtKey] = archive.createdAt
                record[Self.summaryKey] = archive.summary(for: section) ?? section.title
                record[Self.deviceKey] = archive.deviceName
                record[Self.formatKey] = archive.format
                records.append(record)
            } catch {
                lastError = "Could not prepare \(section.title.lowercased()) for iCloud."
                return false
            }
        }

        guard !records.isEmpty else {
            lastError = BackupError.nothingSelected.errorDescription
            return false
        }

        do {
            // This device's copy wins outright: the athlete pressed Back up here,
            // so a half-merged record would be the wrong answer.
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            await loadRemoteIndex()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    // MARK: - Restoring

    /// Fetches the selected sections back out of iCloud as one archive.
    func fetchArchive(sections: Set<BackupSection>) async -> SummitArchive? {
        guard !sections.isEmpty else {
            lastError = BackupError.nothingSelected.errorDescription
            return nil
        }
        guard availability.isReady else {
            lastError = availability.message
            return nil
        }

        lastError = nil
        activity = "Fetching from iCloud…"
        defer { activity = nil }

        let ids = BackupSection.ordered.filter(sections.contains).map(Self.recordID)
        do {
            let results = try await database.records(for: ids)
            var archive: SummitArchive?
            for (_, result) in results {
                guard let record = try? result.get(),
                      let asset = record[Self.payloadKey] as? CKAsset,
                      let url = asset.fileURL,
                      let data = try? Data(contentsOf: url),
                      let slice = try? SummitArchive.decode(data) else { continue }
                archive = archive.map { $0.merging(slice) } ?? slice
            }
            guard let archive else {
                lastError = "There is nothing in iCloud to restore yet."
                return nil
            }
            return archive
        } catch {
            lastError = Self.isMissingSchema(error)
                ? "There is nothing in iCloud to restore yet."
                : Self.describe(error)
            return nil
        }
    }

    // MARK: - Deleting

    /// Removes the selected sections from iCloud. Nothing on the phone changes.
    @discardableResult
    func deleteBackup(sections: Set<BackupSection>) async -> Bool {
        guard availability.isReady else {
            lastError = availability.message
            return false
        }
        lastError = nil
        activity = "Removing from iCloud…"
        defer { activity = nil }

        let ids = BackupSection.ordered.filter(sections.contains).map(Self.recordID)
        do {
            _ = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys)
            await loadRemoteIndex()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Plumbing

    private static func recordID(for section: BackupSection) -> CKRecord.ID {
        CKRecord.ID(recordName: section.rawValue)
    }

    /// True when the server has never seen this kind of record, which happens
    /// before the first backup rather than because something went wrong.
    private static func isMissingSchema(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .unknownItem { return true }
        if ckError.code == .partialFailure {
            let failures = ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
            return !failures.isEmpty && failures.allSatisfy { $0.code == .unknownItem }
        }
        return false
    }

    /// Turns a CloudKit failure into something worth reading, without leaking
    /// internals into the interface.
    private static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "iCloud could not be reached. Try again."
        }
        switch ckError.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to use backups."
        case .networkUnavailable, .networkFailure:
            return "No connection to iCloud. Try again once you are back online."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up space, then try again."
        case .zoneBusy, .serviceUnavailable, .requestRateLimited:
            return "iCloud is busy. Try again in a moment."
        case .permissionFailure:
            return "This device is not allowed to use iCloud for Trekka."
        case .managedAccountRestricted:
            return "iCloud is restricted on this account."
        case .unknownItem:
            return "There is nothing in iCloud to restore yet."
        default:
            return "iCloud could not finish that. Try again."
        }
    }
}
