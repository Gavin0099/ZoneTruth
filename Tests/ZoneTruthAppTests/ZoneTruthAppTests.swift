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
