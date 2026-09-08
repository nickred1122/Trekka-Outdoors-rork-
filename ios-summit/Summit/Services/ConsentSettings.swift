import Foundation
import Observation

/// What the athlete has agreed to, and when.
///
/// Acceptance is recorded per document and per version, so a later revision to
/// one agreement asks only for that one again. Nothing is written until the
/// athlete actually presses the button — ticking a box and then quitting leaves
/// no record, because they never finished agreeing.
@Observable
final class ConsentSettings {
    private static let storageKey = "legal.consent.v1"

    nonisolated private struct Record: Codable, Sendable {
        var versions: [String: Int]
        var acceptedAt: Date?
    }

    private(set) var acceptedVersions: [String: Int]
    private(set) var acceptedAt: Date?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Record.self, from: data) {
            acceptedVersions = stored.versions
            acceptedAt = stored.acceptedAt
        } else {
            acceptedVersions = [:]
            acceptedAt = nil
        }
    }

    // MARK: - Reading

    /// Whether this exact version of a document has been accepted.
    func hasAccepted(_ document: LegalDocument) -> Bool {
        (acceptedVersions[document.kind.rawValue] ?? 0) >= document.version
    }

    /// The gate. Every current document, at its current version.
    var isAccepted: Bool {
        LegalDocument.all.allSatisfy(hasAccepted)
    }

    /// Documents still waiting on an answer — all three on a fresh install, or
    /// just the revised one after an update.
    var outstanding: [LegalDocument] {
        LegalDocument.all.filter { !hasAccepted($0) }
    }

    /// True when some documents were accepted before but a revision needs
    /// agreeing again, so the screen can say so rather than pretending this is
    /// the first time.
    var isReconsenting: Bool {
        !acceptedVersions.isEmpty && !isAccepted
    }

    var acceptedDateText: String? {
        guard let acceptedAt else { return nil }
        return acceptedAt.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Writing

    /// Records agreement to every current document.
    func acceptAll(at date: Date = .now) {
        for document in LegalDocument.all {
            acceptedVersions[document.kind.rawValue] = document.version
        }
        acceptedAt = date
        persist()
    }

    private func persist() {
        let record = Record(versions: acceptedVersions, acceptedAt: acceptedAt)
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
