import Foundation
import XCTest
@testable import ZoneTruthApp
@testable import ZoneTruthCore

final class ZoneTruthAppTests: XCTestCase {
    func testJSONWorkoutRepositoryLoadsImportedWorkouts() throws {
        let fileManager = FileManager.default
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("workouts.json")

        try samplePayload.write(to: fileURL, atomically: true, encoding: .utf8)

        let repository = JSONWorkoutRepository(fileURL: fileURL, fileManager: fileManager)
        let result = repository.loadResult()

        XCTAssertEqual(result.source, .jsonImport)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.workoutType, .running)
        XCTAssertEqual(result.workouts.first?.intent, .zone2)
        XCTAssertEqual(result.workouts.first?.heartRateSamples.count, 3)
    }

    func testJSONWorkoutRepositoryReturnsEmptyForInvalidJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("workouts.json")

        try "{ invalid json".write(to: fileURL, atomically: true, encoding: .utf8)

        let repository = JSONWorkoutRepository(fileURL: fileURL, fileManager: .default)

        let result = repository.loadResult()

        XCTAssertTrue(result.workouts.isEmpty)
        XCTAssertEqual(result.source, .jsonImport)
        XCTAssertNotNil(result.statusMessage)
    }

    func testFallbackWorkoutRepositoryUsesFallbackWhenImportMissing() throws {
        let directoryURL = try makeTemporaryDirectory()
        let missingURL = directoryURL.appendingPathComponent("missing.json")

        let repository = CompositeWorkoutRepository(
            repositories: [
                JSONWorkoutRepository(fileURL: missingURL, fileManager: .default),
                MockWorkoutRepository(),
            ]
        )

        let result = repository.loadResult()

        XCTAssertFalse(result.workouts.isEmpty)
        XCTAssertEqual(result.source, .mockSamples)
        XCTAssertNotNil(result.statusMessage)
    }

    func testHealthKitWorkoutRepositoryReturnsEmptyWhenUnauthorized() {
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .notDetermined,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()]
            )
        )

        let result = repository.loadResult()

        XCTAssertTrue(result.workouts.isEmpty)
        XCTAssertEqual(result.source, .healthKit)
        XCTAssertNotNil(result.statusMessage)
    }

    func testStravaActivityRepositoryReturnsDisconnectedStatusWithoutSession() {
        let repository = StravaActivityRepository(
            client: StubStravaClient(
                connectionStatus: .disconnected,
                activities: []
            )
        )

        let result = repository.loadResult()

        XCTAssertTrue(result.workouts.isEmpty)
        XCTAssertEqual(result.source, .strava)
        XCTAssertNotNil(result.statusMessage)
    }

    func testStravaActivityRepositoryMapsConnectedActivitiesAfterRefresh() async {
        let repository = StravaActivityRepository(
            client: StubStravaClient(
                connectionStatus: .connected,
                activities: [makeStravaActivitySnapshot()]
            )
        )

        let result = await repository.refreshResult()

        XCTAssertEqual(result.source, .strava)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.workoutType, .running)
        XCTAssertEqual(result.workouts.first?.heartRateSamples.count, 2)
    }

    func testStravaOAuthConfigurationBuildsMobileAuthorizationURL() {
        let configuration = StravaOAuthConfiguration(
            clientID: 123,
            clientSecret: "secret",
            redirectURI: "zonetruth://strava/callback",
            requestedScopes: [.activityRead, .activityReadAll],
            approvalPrompt: .auto,
            callbackScheme: "zonetruth"
        )

        let urlString = configuration.mobileAuthorizationURL?.absoluteString

        XCTAssertNotNil(urlString)
        XCTAssertTrue(urlString?.contains("client_id=123") == true)
        XCTAssertTrue(urlString?.contains("response_type=code") == true)
        XCTAssertTrue(urlString?.contains("scope=activity:read,activity:read_all") == true)
    }

    func testStravaAuthorizationParserParsesAcceptedCallback() {
        let callbackURL = URL(string: "zonetruth://strava/callback?state=zonetruth&code=abc123&scope=activity:read_all,activity:read")!

        let result = StravaAuthorizationParser.parseCallbackURL(callbackURL)

        switch result {
        case .code(let authorizationCode):
            XCTAssertEqual(authorizationCode.code, "abc123")
            XCTAssertEqual(authorizationCode.state, "zonetruth")
            XCTAssertEqual(authorizationCode.scope, [.activityReadAll, .activityRead])
        default:
            XCTFail("Expected authorization code callback")
        }
    }

    func testStravaAuthorizationParserParsesDeniedCallback() {
        let callbackURL = URL(string: "zonetruth://strava/callback?state=zonetruth&error=access_denied")!

        let result = StravaAuthorizationParser.parseCallbackURL(callbackURL)

        switch result {
        case .accessDenied(let state):
            XCTAssertEqual(state, "zonetruth")
        default:
            XCTFail("Expected access denied callback")
        }
    }

    func testStravaTokenExchangeResponseMapsToSession() throws {
        let json = """
        {
          "token_type": "Bearer",
          "access_token": "access-token",
          "refresh_token": "refresh-token",
          "expires_at": 1780000000,
          "expires_in": 21600,
          "athlete": {
            "id": 999
          }
        }
        """

        let response = try JSONDecoder.zoneTruth.decode(StravaTokenExchangeResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.session.athleteID, 999)
        XCTAssertEqual(response.session.accessToken, "access-token")
        XCTAssertEqual(response.session.refreshToken, "refresh-token")
    }

    func testHealthKitWorkoutRepositoryMapsAuthorizedSnapshotsAfterRefresh() async {
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()]
            )
        )

        let result = await repository.refreshResult()

        XCTAssertEqual(result.source, .healthKit)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.workoutType, .cycling)
        XCTAssertEqual(result.workouts.first?.intent, .activityReview)
        XCTAssertEqual(result.workouts.first?.heartRateSamples.count, 2)
    }

    func testHealthKitWorkoutRepositoryRequestsAuthorizationWhenNeeded() async {
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .notDetermined,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: []
            )
        )

        let status = await repository.requestAuthorizationIfNeeded()

        XCTAssertEqual(status, .sharingAuthorized)
    }

    func testHealthKitWorkoutRepositoryRequestHealthAccessReturnsAuthorizedRefreshResult() async {
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .notDetermined,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()]
            )
        )

        let result = await repository.requestHealthAccess()

        XCTAssertEqual(result.source, .healthKit)
        XCTAssertEqual(result.workouts.count, 1)
    }

    func testCompositeWorkoutRepositoryRequestsHealthAccessBeforeFallback() async {
        let repository = CompositeWorkoutRepository(
            repositories: [
                HealthKitWorkoutRepository(
                    store: StubHealthKitWorkoutStore(
                        isAvailable: true,
                        authorizationStatus: .notDetermined,
                        requestedAuthorizationStatus: .sharingAuthorized,
                        snapshots: [makeHealthSnapshot()]
                    )
                ),
                MockWorkoutRepository(),
            ]
        )

        let result = await repository.requestHealthAccess()

        XCTAssertEqual(result.source, .healthKit)
        XCTAssertEqual(result.workouts.count, 1)
    }

    @MainActor
    func testViewModelCanRequestHealthAccessWhenFallbackDataIsActive() {
        let viewModel = WorkoutListViewModel(
            repository: CompositeWorkoutRepository(
                repositories: [
                    HealthKitWorkoutRepository(
                        store: StubHealthKitWorkoutStore(
                            isAvailable: true,
                            authorizationStatus: .notDetermined,
                            requestedAuthorizationStatus: .sharingAuthorized,
                            snapshots: []
                        )
                    ),
                    MockWorkoutRepository(),
                ]
            )
        )

        XCTAssertTrue(viewModel.canRequestHealthAccess)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private var samplePayload: String {
        """
        {
          "workouts": [
            {
              "workoutType": "running",
              "startDate": "2026-04-24T06:00:00Z",
              "endDate": "2026-04-24T06:20:00Z",
              "intent": "Zone 2",
              "heartRateSamples": [
                { "timestamp": "2026-04-24T06:00:00Z", "bpm": 112 },
                { "timestamp": "2026-04-24T06:01:00Z", "bpm": 118 },
                { "timestamp": "2026-04-24T06:02:00Z", "bpm": 121 }
              ]
            }
          ]
        }
        """
    }

    private func makeHealthSnapshot() -> HealthKitWorkoutSnapshot {
        let start = Date(timeIntervalSince1970: 1_714_000_000)
        return HealthKitWorkoutSnapshot(
            workoutType: .cycling,
            startDate: start,
            endDate: start.addingTimeInterval(20 * 60),
            heartRateSamples: [
                HeartRateSample(timestamp: start, bpm: 118),
                HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 121),
            ]
        )
    }

    private func makeStravaActivitySnapshot() -> StravaActivitySnapshot {
        let start = Date(timeIntervalSince1970: 1_715_000_000)
        return StravaActivitySnapshot(
            activityID: 42,
            name: "Evening Run",
            workoutType: .running,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            heartRateSamples: [
                HeartRateSample(timestamp: start, bpm: 121),
                HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 124),
            ]
        )
    }
}

private struct StubHealthKitWorkoutStore: HealthKitWorkoutStore {
    let isAvailable: Bool
    let authorizationStatus: HealthAuthorizationStatus
    let requestedAuthorizationStatus: HealthAuthorizationStatus
    let snapshots: [HealthKitWorkoutSnapshot]

    func requestAuthorization() async -> HealthAuthorizationStatus {
        requestedAuthorizationStatus
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkoutSnapshot] {
        _ = limit
        return snapshots
    }
}

private struct StubStravaClient: StravaClient {
    let connectionStatus: StravaConnectionStatus
    let activities: [StravaActivitySnapshot]

    func fetchRecentActivities(limit: Int) async throws -> [StravaActivitySnapshot] {
        _ = limit
        return activities
    }
}
