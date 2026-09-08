import AuthenticationServices
import Foundation
import Observation
import UIKit

/// Tokens as Strava hands them back.
private nonisolated struct StravaTokenResponse: Codable, Sendable {
    struct Athlete: Codable, Sendable {
        var firstname: String?
        var lastname: String?
        var username: String?

        var displayName: String? {
            let full = [firstname, lastname].compactMap { $0 }.joined(separator: " ")
            if !full.trimmingCharacters(in: .whitespaces).isEmpty { return full }
            return username
        }
    }

    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var athlete: Athlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

/// What Trekka keeps between launches. Held in the Keychain, never in defaults.
private nonisolated struct StravaCredentials: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var athleteName: String?

    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 120 }
}

/// The Keychain drawer the Strava tokens live in.
///
/// A refresh token is a standing key to somebody's training history. It does not
/// belong in `UserDefaults`, which is a plain file inside the app container and
/// rides along in every unencrypted backup.
private nonisolated enum StravaVault {
    private static let service = "app.rork.trekka.strava"
    private static let account = "credentials"

    static func save(_ credentials: StravaCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read() -> StravaCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StravaCredentials.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated enum StravaError: LocalizedError {
    case notConfigured
    case cancelled
    case noCode
    case http(Int, String?)
    case rejected(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Strava is not set up in this build of Trekka."
        case .cancelled:
            "Sign-in was cancelled."
        case .noCode:
            "Strava did not send an authorisation back."
        case let .http(status, message):
            message ?? "Strava replied with an error (\(status))."
        case let .rejected(reason):
            reason
        case .timedOut:
            "Strava is still processing this workout. It should appear shortly."
        }
    }
}

/// The athlete's Strava connection: signing in, staying signed in, and sending
/// finished workouts across.
///
/// Two rules shape the whole file. Nothing leaves the phone without the athlete
/// asking for it — automatic sending is off until they turn it on. And a workout
/// whose track carries no clock is sent as a summary rather than as a trace with
/// invented timings: spreading the duration evenly across the points would hand
/// Strava a set of splits nobody ran.
@Observable
final class StravaService {
    /// What the connection is doing, in the words the settings screen uses.
    enum Connection: Equatable {
        case notConfigured
        case signedOut
        case connecting
        case connected(athlete: String?)
        case failed(String)
    }

    /// The outcome of the last send, kept so the screen can report it.
    enum SendResult: Equatable {
        case sent(String)
        case failed(String)
    }

    private static let autoUploadKey = "strava.autoUpload.v1"
    private static let sentKey = "strava.sentActivities.v1"
    /// Sign-in comes back to Trekka through a scheme of our own rather than a web
    /// address, so nothing has to be hosted for it and no server ever sees the
    /// code. `ASWebAuthenticationSession` catches the callback itself, which is
    /// why the scheme needs no entry in the app's registered URL types.
    ///
    /// Strava checks the redirect against the "Authorization Callback Domain" on
    /// the API settings page, comparing it to the *host* part of this URI — that
    /// field currently reads `trekkaoutdoors.com`, so the host here must match it
    /// exactly even though Trekka never visits that address. Changing one of the
    /// two without the other breaks sign-in with an `invalid` error from Strava
    /// before their page even loads.
    private static let callbackScheme = "trekka"
    private static let redirectURI = "trekka://trekkaoutdoors.com/strava"

    private(set) var connection: Connection = .signedOut
    /// The workout currently being sent, so its row can show a spinner.
    private(set) var sendingActivityID: UUID?
    private(set) var lastResult: SendResult?

    /// Send every new workout automatically. Off by default: publishing an
    /// athlete's whereabouts is not a sensible thing to start doing quietly.
    var isAutoUploadEnabled: Bool {
        didSet {
            guard oldValue != isAutoUploadEnabled else { return }
            UserDefaults.standard.set(isAutoUploadEnabled, forKey: Self.autoUploadKey)
        }
    }

    private var credentials: StravaCredentials?
    private var sentActivityIDs: Set<UUID>
    private var session: ASWebAuthenticationSession?
    private let presenter = StravaAuthPresenter()

    init() {
        isAutoUploadEnabled = UserDefaults.standard.bool(forKey: Self.autoUploadKey)
        let stored = UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? []
        sentActivityIDs = Set(stored.compactMap { UUID(uuidString: $0) })
        credentials = StravaVault.read()

        if !Self.isConfigured {
            connection = .notConfigured
        } else if let credentials {
            connection = .connected(athlete: credentials.athleteName)
        }
    }

    // MARK: - Configuration

    /// The keys Strava issued when Trekka Outdoors was registered (application
    /// 195885, callback domain `trekkaoutdoors.com`).
    ///
    /// They are written here rather than kept out of the source because Strava's
    /// mobile flow has no PKCE: the token exchange demands the client secret from
    /// the app itself, so any build of Trekka carries it regardless of where it is
    /// read from. Extracting it from the shipped binary is trivial, which is why
    /// Strava treats a mobile client secret as identifying, not protecting. It
    /// grants nothing on its own — every request still needs a token the athlete
    /// personally granted on Strava's own page, and it cannot read or touch any
    /// account that has not signed in here.
    ///
    /// A build-time value still wins if one is supplied, so the keys can be moved
    /// or rotated without another release.
    private static let registeredClientID = "195885"
    private static let registeredClientSecret = "6d48ee20afedc178490d43d7f57893e08f5c56f7"

    private static var clientID: String {
        let injected = Config.allValues["EXPO_PUBLIC_STRAVA_CLIENT_ID"] ?? ""
        return injected.isEmpty ? registeredClientID : injected
    }

    private static var clientSecret: String {
        let injected = Config.allValues["EXPO_PUBLIC_STRAVA_CLIENT_SECRET"] ?? ""
        return injected.isEmpty ? registeredClientSecret : injected
    }

    static var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    var athleteName: String? {
        credentials?.athleteName
    }

    func hasSent(_ id: UUID) -> Bool { sentActivityIDs.contains(id) }

    // MARK: - Signing in

    func connect() async {
        guard Self.isConfigured else {
            connection = .notConfigured
            return
        }
        connection = .connecting

        do {
            let code = try await authorizationCode()
            let token = try await exchange(code: code)
            store(token)
            connection = .connected(athlete: token.athlete?.displayName)
            EventLog.shared.info("Strava", "Connected to Strava")
        } catch StravaError.cancelled {
            connection = credentials == nil ? .signedOut : .connected(athlete: credentials?.athleteName)
        } catch {
            connection = .failed(error.localizedDescription)
            EventLog.shared.failure("Strava", "Sign-in failed", detail: error.localizedDescription)
        }
    }

    /// Signs out here and, if Strava will take the call, revokes the token at
    /// their end too. Leaving a live token behind on a "disconnect" is the kind
    /// of thing that only shows up years later on somebody's connected-apps list.
    func disconnect() async {
        if let token = credentials?.accessToken {
            var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/deauthorize")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        credentials = nil
        StravaVault.clear()
        isAutoUploadEnabled = false
        connection = Self.isConfigured ? .signedOut : .notConfigured
        lastResult = nil
        EventLog.shared.info("Strava", "Disconnected from Strava")
    }

    private func authorizationCode() async throws -> String {
        // The plain authorize endpoint, not `/oauth/mobile/authorize`: the mobile
        // one exists to hand off to an installed Strava app, which a web
        // authentication session cannot do.
        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:write,activity:read"),
        ]
        guard let url = components?.url else { throw StravaError.notConfigured }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackScheme
            ) { callback, error in
                if let error {
                    let code = (error as NSError).code
                    let isCancel = code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    continuation.resume(throwing: isCancel ? StravaError.cancelled : error)
                    return
                }
                guard let callback,
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: StravaError.noCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = presenter
            self.session = session
            guard session.start() else {
                continuation.resume(throwing: StravaError.cancelled)
                return
            }
        }
    }

    private func exchange(code: String) async throws -> StravaTokenResponse {
        try await token(body: [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ])
    }

    private func refresh(_ refreshToken: String) async throws -> StravaTokenResponse {
        try await token(body: [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    private func token(body: [String: String]) async throws -> StravaTokenResponse {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
    }

    private func store(_ token: StravaTokenResponse) {
        let saved = StravaCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date(timeIntervalSince1970: token.expiresAt),
            athleteName: token.athlete?.displayName ?? credentials?.athleteName
        )
        credentials = saved
        StravaVault.save(saved)
    }

    /// Returns a usable access token, refreshing it first if it has expired.
    private func accessToken() async throws -> String {
        guard Self.isConfigured else { throw StravaError.notConfigured }
        guard let current = credentials else { throw StravaError.rejected("Not connected to Strava.") }
        if current.isFresh { return current.accessToken }

        let refreshed = try await refresh(current.refreshToken)
        store(refreshed)
        return refreshed.accessToken
    }

    // MARK: - Sending a workout

    /// Sends one finished workout to Strava.
    ///
    /// A GPS workout goes across as its actual trace, so Strava draws the real
    /// map and works out the real splits. Anything without a timed track — a gym
    /// session, or a workout recorded before Trekka kept a clock against each fix
    /// — goes across as a summary, and the athlete is told that is what happened.
    @discardableResult
    func send(_ activity: ActivityRecord) async -> SendResult {
        guard sendingActivityID == nil else {
            return .failed("Another workout is still uploading.")
        }
        sendingActivityID = activity.id
        defer { sendingActivityID = nil }

        do {
            let token = try await accessToken()
            let result: SendResult

            if let gpx = GPXCodec.export(activity: activity) {
                try await upload(gpx: gpx, activity: activity, token: token)
                result = .sent("Sent to Strava with its map.")
            } else {
                try await createSummary(activity, token: token)
                result = .sent(
                    activity.track.isEmpty
                        ? "Sent to Strava."
                        : "Sent to Strava as a summary — this workout has no time stored against each point, so its map could not go with it."
                )
            }

            sentActivityIDs.insert(activity.id)
            persistSent()
            lastResult = result
            EventLog.shared.info("Strava", "Uploaded \(activity.name)")
            return result
        } catch {
            let message = error.localizedDescription
            lastResult = .failed(message)
            EventLog.shared.failure("Strava", "Upload failed", detail: message)
            return .failed(message)
        }
    }

    private func upload(gpx: String, activity: ActivityRecord, token: String) async throws {
        let boundary = "trekka.\(UUID().uuidString)"
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8) ?? Data())
            body.append("\(value)\r\n".data(using: .utf8) ?? Data())
        }

        field("name", activity.name)
        field("description", Self.description(for: activity))
        field("data_type", "gpx")
        field("sport_type", Self.sportType(for: activity.activity))
        field("external_id", activity.id.uuidString)

        body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"trekka-\(activity.id.uuidString).gpx\"\r\n"
                .data(using: .utf8) ?? Data()
        )
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(gpx.data(using: .utf8) ?? Data())
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data())

        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)

        guard let receipt = try? JSONDecoder().decode(StravaUploadReceipt.self, from: data) else { return }
        if let error = receipt.error, !error.isEmpty { throw StravaError.rejected(error) }
        guard let id = receipt.id else { return }
        try await awaitProcessing(uploadID: id, token: token)
    }

    /// Strava processes an upload after accepting it, so a file that will be
    /// rejected is accepted first and refused a few seconds later. Polling is the
    /// only way to know which happened, and the athlete deserves the real answer.
    private func awaitProcessing(uploadID: Int, token: String) async throws {
        for _ in 0..<8 {
            try? await Task.sleep(for: .seconds(2))

            var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            guard (try? Self.check(response, data: data)) != nil else { continue }
            guard let receipt = try? JSONDecoder().decode(StravaUploadReceipt.self, from: data) else { continue }

            if let error = receipt.error, !error.isEmpty { throw StravaError.rejected(error) }
            if receipt.activityID != nil { return }
        }
        throw StravaError.timedOut
    }

    /// The summary path: name, sport, when it started, how long it lasted and how
    /// far it went. No trace, and nothing implied about the pace in between.
    private func createSummary(_ activity: ActivityRecord, token: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var fields: [String: String] = [
            "name": activity.name,
            "sport_type": Self.sportType(for: activity.activity),
            "start_date_local": formatter.string(from: activity.startDate),
            "elapsed_time": String(Int(activity.duration.rounded())),
            "description": Self.description(for: activity),
        ]
        if activity.distance > 0 {
            fields["distance"] = String(format: "%.1f", activity.distance)
        }

        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/activities")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
    }

    private func persistSent() {
        // Only the recent tail is worth keeping; this list exists to stop the
        // same workout being sent twice, not to be a second history.
        let trimmed = Array(sentActivityIDs).suffix(500)
        sentActivityIDs = Set(trimmed)
        UserDefaults.standard.set(trimmed.map(\.uuidString), forKey: Self.sentKey)
    }

    // MARK: - Helpers

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8) ?? Data()
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let message = (try? JSONDecoder().decode(StravaAPIError.self, from: data))?.message
        throw StravaError.http(http.statusCode, message)
    }

    /// What Trekka measured, written into the Strava description so the numbers
    /// the athlete saw on their wrist are attached to the workout rather than
    /// silently replaced by Strava's own recalculation.
    private static func description(for activity: ActivityRecord) -> String {
        var lines = ["Recorded with Trekka."]
        if activity.elevationGain > 0 {
            lines.append("Climb \(Formatters.elevation(activity.elevationGain)) \(Formatters.elevationUnit)")
        }
        if activity.averageHeartRate > 0 {
            lines.append("Average heart rate \(Int(activity.averageHeartRate.rounded())) bpm")
        }
        if !activity.strengthSets.isEmpty {
            let volume = activity.strengthSets.reduce(0.0) { $0 + $1.volume }
            lines.append("\(activity.strengthSets.count) sets · \(Int(volume.rounded())) kg total volume")
        }
        return lines.joined(separator: "\n")
    }

    /// Trekka's activity list is longer than Strava's, so anything without a
    /// counterpart goes across as a plain workout rather than as the nearest
    /// sport that happens to sound similar.
    private static func sportType(for activity: RouteActivityType) -> String {
        switch activity {
        case .run: "TrailRun"
        case .roadRun, .ultraRun, .track: "Run"
        case .treadmill, .virtualRun: "VirtualRun"
        case .ride, .commute: "Ride"
        case .gravelRide: "GravelRide"
        case .mountainBike, .bikepacking: "MountainBikeRide"
        case .eBike: "EBikeRide"
        case .indoorRide: "VirtualRide"
        case .handCycling: "Handcycle"
        case .hike, .backpacking, .mountaineering, .ruck: "Hike"
        case .walk: "Walk"
        case .rockClimb, .boulder, .indoorClimb, .viaFerrata: "RockClimbing"
        case .backcountrySki: "BackcountrySki"
        case .alpineSki: "AlpineSki"
        case .snowboard, .splitboard: "Snowboard"
        case .nordicSki: "NordicSki"
        case .snowshoe: "Snowshoe"
        case .iceSkate: "IceSkate"
        case .openWaterSwim, .poolSwim: "Swim"
        case .kayak: "Kayaking"
        case .paddleboard: "StandUpPaddling"
        case .surf: "Surfing"
        case .sail: "Sail"
        case .strength: "WeightTraining"
        case .hiit: "HighIntensityIntervalTraining"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .elliptical: "Elliptical"
        case .stairStepper, .climbStairs: "StairStepper"
        case .row: "Rowing"
        case .golf: "Golf"
        case .soccer: "Soccer"
        case .tennis: "Tennis"
        case .pickleball: "Pickleball"
        case .badminton: "Badminton"
        case .squash: "Squash"
        case .tableTennis: "TableTennis"
        case .racquetball: "Racquetball"
        case .skateboard: "Skateboard"
        default: "Workout"
        }
    }
}

/// Strava's answer to an upload, before and after it has been processed.
private nonisolated struct StravaUploadReceipt: Codable, Sendable {
    var id: Int?
    var error: String?
    var status: String?
    var activityID: Int?

    enum CodingKeys: String, CodingKey {
        case id, error, status
        case activityID = "activity_id"
    }
}

private nonisolated struct StravaAPIError: Codable, Sendable {
    var message: String?
}

/// Gives the sign-in sheet a window to appear over.
private final class StravaAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
