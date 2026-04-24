import Foundation
import ZoneTruthCore

enum StravaConnectionStatus: Equatable, Sendable {
    case unavailable
    case disconnected
    case connected
}

enum StravaScope: String, CaseIterable, Codable, Sendable {
    case read = "read"
    case readAll = "read_all"
    case profileReadAll = "profile:read_all"
    case profileWrite = "profile:write"
    case activityRead = "activity:read"
    case activityReadAll = "activity:read_all"
    case activityWrite = "activity:write"
}

enum StravaApprovalPrompt: String, Codable, Sendable {
    case auto
    case force
}

struct StravaOAuthConfiguration: Equatable, Sendable {
    let clientID: Int
    let clientSecret: String
    let redirectURI: String
    let requestedScopes: [StravaScope]
    let approvalPrompt: StravaApprovalPrompt
    let callbackScheme: String

    init(
        clientID: Int,
        clientSecret: String,
        redirectURI: String,
        requestedScopes: [StravaScope] = [.activityRead, .activityReadAll],
        approvalPrompt: StravaApprovalPrompt = .auto,
        callbackScheme: String
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.requestedScopes = requestedScopes
        self.approvalPrompt = approvalPrompt
        self.callbackScheme = callbackScheme
    }

    var mobileAuthorizationURL: URL? {
        authorizationURL(baseURL: "https://www.strava.com/oauth/mobile/authorize")
    }

    var mobileAppAuthorizationURL: URL? {
        authorizationURL(baseURL: "strava://oauth/mobile/authorize")
    }

    private func authorizationURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: String(clientID)),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: approvalPrompt.rawValue),
            URLQueryItem(name: "scope", value: requestedScopes.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "state", value: callbackScheme),
        ]
        return components.url
    }
}

enum StravaAuthorizationResult: Equatable, Sendable {
    case code(StravaAuthorizationCode)
    case accessDenied(state: String?)
    case invalidCallback
}

struct StravaAuthorizationCode: Equatable, Sendable {
    let code: String
    let scope: [StravaScope]
    let state: String?
}

struct StravaTokenExchangeRequest: Equatable, Sendable {
    let clientID: Int
    let clientSecret: String
    let code: String

    var formBody: [String: String] {
        [
            "client_id": String(clientID),
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ]
    }
}

struct StravaTokenRefreshRequest: Equatable, Sendable {
    let clientID: Int
    let clientSecret: String
    let refreshToken: String

    var formBody: [String: String] {
        [
            "client_id": String(clientID),
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
    }
}

struct StravaTokenExchangeResponse: Equatable, Codable, Sendable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let expiresIn: Int
    let athlete: StravaTokenAthlete

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case athlete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        athlete = try container.decode(StravaTokenAthlete.self, forKey: .athlete)

        let epochSeconds = try container.decode(TimeInterval.self, forKey: .expiresAt)
        expiresAt = Date(timeIntervalSince1970: epochSeconds)
    }

    var session: StravaSession {
        StravaSession(
            athleteID: athlete.id,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}

struct StravaTokenAthlete: Equatable, Codable, Sendable {
    let id: Int?
}

protocol StravaOAuthClient {
    func exchangeToken(using request: StravaTokenExchangeRequest) async throws -> StravaTokenExchangeResponse
    func refreshToken(using request: StravaTokenRefreshRequest) async throws -> StravaTokenExchangeResponse
}

enum StravaOAuthError: Error, Equatable, Sendable {
    case invalidCallback
    case tokenExchangeNotImplemented
}

struct StravaSession: Equatable, Sendable {
    let athleteID: Int?
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

struct StravaActivitySnapshot: Equatable, Sendable {
    let activityID: Int
    let name: String
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    let heartRateSamples: [HeartRateSample]
    let defaultIntent: TrainingIntent

    init(
        activityID: Int,
        name: String,
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        heartRateSamples: [HeartRateSample],
        defaultIntent: TrainingIntent = .activityReview
    ) {
        self.activityID = activityID
        self.name = name
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.heartRateSamples = heartRateSamples
        self.defaultIntent = defaultIntent
    }

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples,
            intent: defaultIntent
        )
    }
}

protocol StravaClient {
    var connectionStatus: StravaConnectionStatus { get }
    func fetchRecentActivities(limit: Int) async throws -> [StravaActivitySnapshot]
}

enum StravaClientError: Error, Equatable, Sendable {
    case unavailable
    case disconnected
    case expiredSession
    case notImplemented
}

struct SystemStravaClient: StravaClient {
    let sessionStore: StravaSessionStore

    var connectionStatus: StravaConnectionStatus {
        guard let session = sessionStore.loadSession() else { return .disconnected }
        return session.isExpired ? .disconnected : .connected
    }

    func fetchRecentActivities(limit: Int) async throws -> [StravaActivitySnapshot] {
        _ = limit

        guard let session = sessionStore.loadSession() else {
            throw StravaClientError.disconnected
        }

        guard !session.isExpired else {
            throw StravaClientError.expiredSession
        }

        throw StravaClientError.notImplemented
    }
}

protocol StravaSessionStore {
    func loadSession() -> StravaSession?
}

struct StravaAuthorizationParser {
    static func parseCallbackURL(_ url: URL) -> StravaAuthorizationResult {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalidCallback
        }

        let queryItems = components.queryItems ?? []
        let state = value(named: "state", in: queryItems)

        if value(named: "error", in: queryItems) == "access_denied" {
            return .accessDenied(state: state)
        }

        guard let code = value(named: "code", in: queryItems), !code.isEmpty else {
            return .invalidCallback
        }

        let scopes = (value(named: "scope", in: queryItems) ?? "")
            .split(separator: ",")
            .compactMap { StravaScope(rawValue: String($0)) }

        return .code(
            StravaAuthorizationCode(
                code: code,
                scope: scopes,
                state: state
            )
        )
    }

    private static func value(named name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name == name })?.value
    }
}

struct SystemStravaOAuthClient: StravaOAuthClient {
    func exchangeToken(using request: StravaTokenExchangeRequest) async throws -> StravaTokenExchangeResponse {
        _ = request
        throw StravaOAuthError.tokenExchangeNotImplemented
    }

    func refreshToken(using request: StravaTokenRefreshRequest) async throws -> StravaTokenExchangeResponse {
        _ = request
        throw StravaOAuthError.tokenExchangeNotImplemented
    }
}

struct FileStravaSessionStore: StravaSessionStore {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadSession() -> StravaSession? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let sessionFile = try JSONDecoder.zoneTruth.decode(StravaSessionFile.self, from: data)
            return sessionFile.session
        } catch {
            return nil
        }
    }
}

final class StravaActivityRepository: WorkoutRepository {
    let client: StravaClient
    private let activityLimit: Int
    private var cachedWorkouts: [WorkoutInput]

    init(
        client: StravaClient,
        activityLimit: Int = 20,
        cachedWorkouts: [WorkoutInput] = []
    ) {
        self.client = client
        self.activityLimit = activityLimit
        self.cachedWorkouts = cachedWorkouts
    }

    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(
            workouts: cachedWorkouts,
            source: .strava,
            statusMessage: statusMessage(for: client.connectionStatus, workoutCount: cachedWorkouts.count)
        )
    }

    func refreshResult() async -> WorkoutLoadResult {
        switch client.connectionStatus {
        case .unavailable:
            cachedWorkouts = []
            return WorkoutLoadResult(
                workouts: [],
                source: .strava,
                statusMessage: "Strava is not configured for this build yet."
            )
        case .disconnected:
            cachedWorkouts = []
            return WorkoutLoadResult(
                workouts: [],
                source: .strava,
                statusMessage: "Strava is available as a future source, but no active session is connected."
            )
        case .connected:
            do {
                cachedWorkouts = try await client.fetchRecentActivities(limit: activityLimit).map(\.toDomainWorkout)
                return WorkoutLoadResult(
                    workouts: cachedWorkouts,
                    source: .strava,
                    statusMessage: statusMessage(for: .connected, workoutCount: cachedWorkouts.count)
                )
            } catch {
                cachedWorkouts = []
                return WorkoutLoadResult(
                    workouts: [],
                    source: .strava,
                    statusMessage: "Strava is connected, but activities could not be loaded yet."
                )
            }
        }
    }

    private func statusMessage(for status: StravaConnectionStatus, workoutCount: Int) -> String {
        switch status {
        case .unavailable:
            return "Strava is not configured for this build yet."
        case .disconnected:
            return "Strava is available as a future source, but no active session is connected."
        case .connected:
            return workoutCount > 0
                ? "Loaded workouts from Strava."
                : "Strava is connected, but no recent activities were found."
        }
    }
}

private struct StravaSessionFile: Decodable {
    let athleteID: Int?
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var session: StravaSession {
        StravaSession(
            athleteID: athleteID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}
