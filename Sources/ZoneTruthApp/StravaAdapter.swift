import Foundation
import ZoneTruthCore

enum StravaConnectionStatus: Equatable, Sendable {
    case unavailable
    case disconnected
    case connected
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
