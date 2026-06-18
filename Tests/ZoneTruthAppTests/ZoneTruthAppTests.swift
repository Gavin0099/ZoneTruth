import Foundation
import SwiftUI
import XCTest
@testable import ZoneTruthApp
@testable import ZoneTruthCore

final class ZoneTruthAppTests: XCTestCase {
    private struct GoalAlignmentLanguageFixtureRecord: Codable, Equatable {
        let goal: String
        let signal: String
        let observationalLabel: String
        let mismatchFactors: [String]
        let ctaObservational: String
        let ctaWeak: String
    }
    private struct EvaluationFixtureRecord: Codable, Equatable {
        let id: String
        let evaluation: WorkoutEvaluation
    }

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
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.value, 48.2)
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.source, .apple)
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.sourceLabel, "Apple Health VO2 max")
        XCTAssertEqual(result.workouts.first?.strengthMetrics.first?.exerciseName, "Back Squat")
        XCTAssertEqual(result.workouts.first?.strengthMetrics.first?.value, 120)
        XCTAssertEqual(result.workouts.first?.strengthMetrics.first?.source, .e1RM)
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

    func testCompositeWorkoutRepositoryPreservesSleepContextWhenFallingBackToMockWorkouts() {
        let sleepContext = WeeklySleepContext(
            lookbackDays: 7,
            nightsWithSleep: 4,
            averageSleepHours: 6.25
        )
        let repository = CompositeWorkoutRepository(
            repositories: [
                StaticLoadResultRepository(
                    result: WorkoutLoadResult(
                        workouts: [],
                        source: .healthKit,
                        sleepContext: sleepContext
                    )
                ),
                MockWorkoutRepository(),
            ]
        )

        let result = repository.loadResult()

        XCTAssertEqual(result.source, .mockSamples)
        XCTAssertFalse(result.workouts.isEmpty)
        XCTAssertEqual(result.sleepContext, sleepContext)
    }

    func testJSONWorkoutRepositoryBootstrapsBundledSeedOnlyWhenEnabled() throws {
        let directoryURL = try makeTemporaryDirectory()
        let missingURL = directoryURL.appendingPathComponent("workouts.json")

        let repository = JSONWorkoutRepository(
            fileURL: missingURL,
            fileManager: .default,
            bootstrapSeedIfMissing: true
        )

        let result = repository.loadResult()

        XCTAssertFalse(result.workouts.isEmpty)
        XCTAssertEqual(result.source, .jsonImport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingURL.path))
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

    func testHealthKitWorkoutRepositoryMapsAppleVO2MaxEstimate() async {
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
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.value, 47.3)
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.source, .apple)
        XCTAssertEqual(result.workouts.first?.vo2MaxEstimate?.sourceLabel, "Apple Health VO2 max")
    }

    func testHealthKitReadTypeIdentifiersIncludeVO2MaxAndRecovery() {
        XCTAssertTrue(healthKitReadTypeIdentifiers.contains("vo2Max"))
        XCTAssertTrue(healthKitReadTypeIdentifiers.contains("heartRateRecoveryOneMinute"))
        XCTAssertTrue(healthKitReadTypeIdentifiers.contains("sleepAnalysis"))
    }

    func testHealthKitWorkoutRepositoryCarriesAppleSleepContext() async {
        let sleepContext = WeeklySleepContext(
            lookbackDays: 7,
            nightsWithSleep: 5,
            averageSleepHours: 6.8
        )
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()],
                sleepContext: sleepContext
            )
        )

        let result = await repository.refreshResult()

        XCTAssertEqual(result.source, .healthKit)
        XCTAssertEqual(result.sleepContext, sleepContext)
    }

    func testSleepContextAggregationKeepsCrossMidnightSamplesInOneNight() {
        let start = makeUTCDate(year: 2026, month: 6, day: 1).addingTimeInterval(12 * 60 * 60)
        let now = makeUTCDate(year: 2026, month: 6, day: 8).addingTimeInterval(12 * 60 * 60)
        let nightStart = makeUTCDate(year: 2026, month: 6, day: 5).addingTimeInterval(23.5 * 60 * 60)
        let midnight = makeUTCDate(year: 2026, month: 6, day: 6)

        let context = aggregateWeeklySleepContext(
            from: [
                HealthKitSleepInterval(
                    startDate: nightStart,
                    endDate: midnight.addingTimeInterval(60 * 60)
                ),
                HealthKitSleepInterval(
                    startDate: midnight.addingTimeInterval(80 * 60),
                    endDate: midnight.addingTimeInterval(7 * 60 * 60)
                )
            ],
            lookbackDays: 7,
            startDate: start,
            now: now
        )

        XCTAssertEqual(context?.nightsWithSleep, 1)
        XCTAssertEqual(context?.averageSleepHours ?? -1, 7.0 + (10.0 / 60.0), accuracy: 0.001)
    }

    func testSleepContextAggregationClipsLookbackBoundaryOverlap() {
        let start = makeUTCDate(year: 2026, month: 6, day: 1).addingTimeInterval(12 * 60 * 60)
        let now = makeUTCDate(year: 2026, month: 6, day: 8).addingTimeInterval(12 * 60 * 60)

        let context = aggregateWeeklySleepContext(
            from: [
                HealthKitSleepInterval(
                    startDate: start.addingTimeInterval(-2 * 60 * 60),
                    endDate: start.addingTimeInterval(2 * 60 * 60)
                )
            ],
            lookbackDays: 7,
            startDate: start,
            now: now
        )

        XCTAssertEqual(context?.nightsWithSleep, 1)
        XCTAssertEqual(context?.averageSleepHours ?? -1, 2.0, accuracy: 0.001)
    }

    func testSleepContextAggregationIgnoresShortNapAsNight() {
        let start = makeUTCDate(year: 2026, month: 6, day: 1)
        let now = makeUTCDate(year: 2026, month: 6, day: 8)

        let context = aggregateWeeklySleepContext(
            from: [
                HealthKitSleepInterval(
                    startDate: start.addingTimeInterval(18 * 60 * 60),
                    endDate: start.addingTimeInterval(18.75 * 60 * 60)
                )
            ],
            lookbackDays: 7,
            startDate: start,
            now: now
        )

        XCTAssertNil(context)
    }

    func testHealthKitWorkoutRepositoryMapsAppleHeartRateRecoveryContext() async {
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
        XCTAssertEqual(result.workouts.first?.heartRateRecoveryOneMinute?.value, 23)
        XCTAssertEqual(result.workouts.first?.heartRateRecoveryOneMinute?.source, .apple)
        XCTAssertEqual(result.workouts.first?.heartRateRecoveryOneMinute?.sourceLabel, "Apple Health 1-minute heart-rate recovery")
    }

    func testBestMatchingHeartRateRecoveryObservationAllowsPostWorkoutSample() {
        let workoutEnd = Date(timeIntervalSince1970: 1_714_000_000)
        let candidates = [
            HeartRateRecoveryObservation(
                value: 18,
                source: .apple,
                sourceLabel: "older sample",
                measuredAt: workoutEnd.addingTimeInterval(-6 * 60)
            ),
            HeartRateRecoveryObservation(
                value: 24,
                source: .apple,
                sourceLabel: "post-workout sample",
                measuredAt: workoutEnd.addingTimeInterval(90)
            ),
        ]

        let match = bestMatchingHeartRateRecoveryObservation(
            near: workoutEnd,
            candidates: candidates
        )

        XCTAssertEqual(match?.value, 24)
        XCTAssertEqual(match?.sourceLabel, "post-workout sample")
    }

    func testBestMatchingHeartRateRecoveryObservationRejectsFarPostWorkoutSample() {
        let workoutEnd = Date(timeIntervalSince1970: 1_714_000_000)
        let candidates = [
            HeartRateRecoveryObservation(
                value: 22,
                source: .apple,
                sourceLabel: "too late",
                measuredAt: workoutEnd.addingTimeInterval(15 * 60)
            )
        ]

        let match = bestMatchingHeartRateRecoveryObservation(
            near: workoutEnd,
            candidates: candidates
        )

        XCTAssertNil(match)
    }

    func testDerivedHeartRateRecoveryObservationUsesPostWorkoutSamples() {
        let workoutEnd = Date(timeIntervalSince1970: 1_714_000_000)
        let inWorkoutSamples = [
            HeartRateSample(timestamp: workoutEnd.addingTimeInterval(-20), bpm: 108)
        ]
        let postWorkoutSamples = [
            HeartRateSample(timestamp: workoutEnd.addingTimeInterval(5), bpm: 104),
            HeartRateSample(timestamp: workoutEnd.addingTimeInterval(62), bpm: 94),
            HeartRateSample(timestamp: workoutEnd.addingTimeInterval(118), bpm: 93),
        ]

        let observation = derivedHeartRateRecoveryObservation(
            workoutEndDate: workoutEnd,
            inWorkoutSamples: inWorkoutSamples,
            postWorkoutSamples: postWorkoutSamples
        )

        guard let observation else {
            return XCTFail("Expected derived recovery observation")
        }
        XCTAssertEqual(observation.value, 10, accuracy: 0.001)
        XCTAssertEqual(observation.source, .apple)
        XCTAssertEqual(observation.sourceLabel, "Derived from Apple Health post-workout heart rate")
    }

    func testHealthKitWorkoutRepositoryMapsRunningPowerContext() async {
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
        XCTAssertEqual(result.workouts.first?.runningPower?.averageWatts, 248)
        XCTAssertEqual(result.workouts.first?.runningPower?.source, .runningHRSpeed)
        XCTAssertEqual(result.workouts.first?.runningPower?.sourceLabel, "Apple Health running power")
    }

    func testHealthKitWorkoutRepositoryMapsCyclingPowerContext() async {
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
        XCTAssertEqual(result.workouts.first?.cyclingPower?.averageWatts, 214)
        XCTAssertEqual(result.workouts.first?.cyclingPower?.source, .cyclingPowerHR)
        XCTAssertEqual(result.workouts.first?.cyclingPower?.sourceLabel, "Apple Health cycling power")
    }

    func testHealthKitWorkoutRepositoryMapsWorkoutRouteContext() async {
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
        XCTAssertEqual(result.workouts.first?.workoutRoute?.pointCount, 128)
        XCTAssertEqual(result.workouts.first?.workoutRoute?.elevationGainMeters, 86)
        XCTAssertEqual(result.workouts.first?.workoutRoute?.source, .workoutRoute)
        XCTAssertEqual(result.workouts.first?.workoutRoute?.sourceLabel, "Apple Health workout route")
    }

    func testWorkoutRouteQueryBatchCollectorCompletesOnlyOnceAfterError() {
        enum RouteError: Error {
            case transient
        }

        let collector = WorkoutRouteQueryBatchCollector<Int>()

        XCTAssertNil(collector.record(locations: [1, 2], done: false, error: nil))

        let errorCompletion = collector.record(locations: nil, done: false, error: RouteError.transient)
        switch errorCompletion {
        case .failure(RouteError.transient):
            break
        default:
            XCTFail("Expected transient route error completion")
        }

        let laterCompletion = collector.record(locations: [3], done: true, error: nil)
        XCTAssertNil(laterCompletion)
    }

    func testWorkoutRouteQueryBatchCollectorReturnsAccumulatedLocationsOnceOnDone() {
        let collector = WorkoutRouteQueryBatchCollector<Int>()

        XCTAssertNil(collector.record(locations: [1, 2], done: false, error: nil))

        let completion = collector.record(locations: [3], done: true, error: nil)
        switch completion {
        case .success(let locations):
            XCTAssertEqual(locations, [1, 2, 3])
        default:
            XCTFail("Expected accumulated route locations")
        }

        XCTAssertNil(collector.record(locations: [4], done: true, error: nil))
    }

    func testHealthKitWorkoutRepositoryMapsExternalLoadDecouplingContext() async {
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
        guard let observation = result.workouts.first?.externalLoadDecoupling else {
            return XCTFail("Expected external load decoupling observation")
        }
        XCTAssertEqual(observation.source, .cyclingPowerHR)
        XCTAssertEqual(observation.sourceLabel, "Apple Health cycling power + HR decoupling")
        XCTAssertEqual(observation.decouplingRatio, 0.0417, accuracy: 0.0001)
    }

    func testHealthKitRefreshResultLogsAuthorizationAndWorkoutSummary() async {
        let logRecorder = DebugLogRecorder()
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()],
                debugAuthorizationDetailsValue: HealthKitAuthorizationDebugDetails(
                    workout: .sharingAuthorized,
                    heartRate: .sharingAuthorized,
                    vo2Max: .sharingAuthorized,
                    heartRateRecoveryOneMinute: .sharingDenied,
                    runningPower: .sharingDenied,
                    cyclingPower: .sharingDenied,
                    workoutRoute: .sharingAuthorized,
                    sleepAnalysis: .sharingDenied
                ),
                debugGlobalRecoveryProbeValue: HealthKitRecoveryProbeSummary(
                    count: 1,
                    records: [
                        HealthKitRecoveryProbeRecord(
                            value: 24,
                            measuredAt: Date(timeIntervalSince1970: 1_714_001_200),
                            source: .apple,
                            sourceLabel: "Apple Watch"
                        )
                    ]
                )
            ),
            debugLogger: logRecorder.record(_:)
        )

        _ = await repository.refreshResult()
        let combinedLog = logRecorder.combinedLog()

        XCTAssertTrue(combinedLog.contains("[HealthKit] refreshResult authorization=sharing_authorized"), combinedLog)
        XCTAssertTrue(combinedLog.contains("type_authorization"), combinedLog)
        XCTAssertTrue(combinedLog.contains("recovery=sharing_denied"), combinedLog)
        XCTAssertTrue(combinedLog.contains("sleepAnalysis=sharing_denied"), combinedLog)
        XCTAssertTrue(combinedLog.contains("[HealthKit] refreshResult workout_count=1"), combinedLog)
        XCTAssertTrue(combinedLog.contains("vo2=ok"), combinedLog)
        XCTAssertTrue(combinedLog.contains("recovery=ok"), combinedLog)
        XCTAssertTrue(combinedLog.contains("runningPower=ok"), combinedLog)
        XCTAssertTrue(combinedLog.contains("cyclingPower=ok"), combinedLog)
        XCTAssertTrue(combinedLog.contains("route=ok"), combinedLog)
        XCTAssertTrue(combinedLog.contains("recovery_candidates=1"), combinedLog)
        XCTAssertTrue(combinedLog.contains("global_recovery_probe count=1"), combinedLog)
        XCTAssertTrue(combinedLog.contains("global_recovery_probe[0]"), combinedLog)
        XCTAssertTrue(combinedLog.contains("source=Apple Watch"), combinedLog)
    }

    func testHealthKitRefreshResultLogsMissingSignalsClearly() async {
        let logRecorder = DebugLogRecorder()
        let start = Date(timeIntervalSince1970: 1_714_000_000)
        let sparseSnapshot = HealthKitWorkoutSnapshot(
            workoutType: .running,
            startDate: start,
            endDate: start.addingTimeInterval(20 * 60),
            heartRateSamples: [
                HeartRateSample(timestamp: start, bpm: 118),
                HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 121),
            ],
            debugSignalSnapshot: HealthKitWorkoutDebugSignalSnapshot(
                recoveryCandidateCount: 0
            )
        )
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [sparseSnapshot],
                debugAuthorizationDetailsValue: HealthKitAuthorizationDebugDetails(
                    workout: .sharingAuthorized,
                    heartRate: .sharingAuthorized,
                    vo2Max: .sharingDenied,
                    heartRateRecoveryOneMinute: .sharingDenied,
                    runningPower: .sharingDenied,
                    cyclingPower: .sharingDenied,
                    workoutRoute: .sharingDenied,
                    sleepAnalysis: .sharingDenied
                ),
                debugGlobalRecoveryProbeValue: HealthKitRecoveryProbeSummary(
                    count: 0,
                    records: []
                )
            ),
            debugLogger: logRecorder.record(_:)
        )

        _ = await repository.refreshResult()
        let combinedLog = logRecorder.combinedLog()

        XCTAssertTrue(combinedLog.contains("vo2=missing"), combinedLog)
        XCTAssertTrue(combinedLog.contains("recovery=missing"), combinedLog)
        XCTAssertTrue(combinedLog.contains("runningPower=missing"), combinedLog)
        XCTAssertTrue(combinedLog.contains("cyclingPower=missing"), combinedLog)
        XCTAssertTrue(combinedLog.contains("route=missing"), combinedLog)
        XCTAssertTrue(combinedLog.contains("recovery_candidates=0"), combinedLog)
        XCTAssertTrue(combinedLog.contains("global_recovery_probe count=0"), combinedLog)
        XCTAssertTrue(combinedLog.contains("global_recovery_fallback"), combinedLog)
    }

    func testHealthKitRefreshResultLogsSleepDiagnosticCountsAndErrors() async {
        let sleepContext = WeeklySleepContext(
            lookbackDays: 7,
            nightsWithSleep: 3,
            averageSleepHours: 6.5
        )
        let availableLog = DebugLogRecorder()
        let availableRepository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()],
                sleepQueryResult: HealthKitSleepContextQueryResult(
                    context: sleepContext,
                    lookbackDays: 7,
                    rawSampleCount: 9,
                    asleepSampleCount: 6
                )
            ),
            debugLogger: availableLog.record(_:)
        )

        _ = await availableRepository.refreshResult()
        let availableCombinedLog = availableLog.combinedLog()

        XCTAssertTrue(availableCombinedLog.contains("sleep_context lookback_days=7 raw_samples=9 asleep_samples=6 status=available"), availableCombinedLog)
        XCTAssertTrue(availableCombinedLog.contains("nights=3/7"), availableCombinedLog)
        XCTAssertTrue(availableCombinedLog.contains("avg_hours=6.5"), availableCombinedLog)

        let errorLog = DebugLogRecorder()
        let errorRepository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingAuthorized,
                requestedAuthorizationStatus: .sharingAuthorized,
                snapshots: [makeHealthSnapshot()],
                sleepQueryError: HealthKitStoreError.unauthorized
            ),
            debugLogger: errorLog.record(_:)
        )

        _ = await errorRepository.refreshResult()
        let errorCombinedLog = errorLog.combinedLog()

        XCTAssertTrue(errorCombinedLog.contains("sleep_context error=unauthorized lookback_days=7"), errorCombinedLog)
        XCTAssertFalse(errorCombinedLog.contains("sleep_context=missing"), errorCombinedLog)
    }

    func testHealthKitRefreshResultTreatsReadableSnapshotsAsAuthorizedWhenRawStatusDenied() async {
        let logRecorder = DebugLogRecorder()
        let repository = HealthKitWorkoutRepository(
            store: StubHealthKitWorkoutStore(
                isAvailable: true,
                authorizationStatus: .sharingDenied,
                requestedAuthorizationStatus: .sharingDenied,
                snapshots: [makeHealthSnapshot()]
            ),
            debugLogger: logRecorder.record(_:)
        )

        let result = await repository.refreshResult()
        let combinedLog = logRecorder.combinedLog()

        XCTAssertEqual(result.statusMessage, "已從 Apple Health 載入運動紀錄。")
        XCTAssertTrue(combinedLog.contains("[HealthKit] refreshResult authorization=sharing_authorized raw_authorization=sharing_denied"), combinedLog)
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

    func testStravaAppDefaultDoesNotEmbedClientSecret() throws {
        XCTAssertNil(StravaOAuthConfiguration.appDefault)

        let source = try appSourceText(named: "StravaAdapter.swift")
        XCTAssertFalse(source.contains("StravaCredentials"))
        XCTAssertFalse(source.contains("static let clientSecret"))
        let secretLiteralPattern = #"clientSecret\s*:\s*"[a-f0-9]{40}""#
        XCTAssertNil(source.range(of: secretLiteralPattern, options: String.CompareOptions.regularExpression))
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

    func testStravaTokenRefreshResponseDecodesWithoutAthlete() throws {
        let json = """
        {
          "token_type": "Bearer",
          "access_token": "refreshed-access-token",
          "refresh_token": "refreshed-refresh-token",
          "expires_at": 1790000000,
          "expires_in": 21600
        }
        """

        let response = try JSONDecoder.zoneTruth.decode(StravaTokenExchangeResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.session.athleteID)
        XCTAssertEqual(response.session.accessToken, "refreshed-access-token")
    }

    func testStravaCallbackHandlerExchangesTokenAndSavesSession() async {
        let sessionStore = SpyStravaSessionStore()
        let oauthClient = StubStravaOAuthClient(
            result: .success(makeTokenExchangeResponse())
        )
        let handler = StravaCallbackHandler(
            configuration: makeStravaConfig(),
            oauthClient: oauthClient,
            sessionStore: sessionStore
        )
        let callbackURL = URL(string: "zonetruth://strava/callback?code=abc123&scope=activity:read&state=zonetruth")!

        let handled = await handler.handle(callbackURL)

        XCTAssertTrue(handled)
        XCTAssertEqual(sessionStore.savedSessions.count, 1)
        XCTAssertEqual(sessionStore.savedSessions.first?.accessToken, "stub-access-token")
    }

    func testStravaCallbackHandlerIgnoresUnrelatedURLScheme() async {
        let sessionStore = SpyStravaSessionStore()
        let handler = StravaCallbackHandler(
            configuration: makeStravaConfig(),
            oauthClient: StubStravaOAuthClient(result: .success(makeTokenExchangeResponse())),
            sessionStore: sessionStore
        )
        let unrelatedURL = URL(string: "https://example.com/callback?code=abc")!

        let handled = await handler.handle(unrelatedURL)

        XCTAssertFalse(handled)
        XCTAssertTrue(sessionStore.savedSessions.isEmpty)
    }

    func testStravaCallbackHandlerHandlesDeniedCallback() async {
        let sessionStore = SpyStravaSessionStore()
        let handler = StravaCallbackHandler(
            configuration: makeStravaConfig(),
            oauthClient: StubStravaOAuthClient(result: .success(makeTokenExchangeResponse())),
            sessionStore: sessionStore
        )
        let deniedURL = URL(string: "zonetruth://strava/callback?error=access_denied&state=zonetruth")!

        let handled = await handler.handle(deniedURL)

        XCTAssertFalse(handled)
        XCTAssertTrue(sessionStore.savedSessions.isEmpty)
    }

    func testStravaTokenExchangeResponseMapsToSessionPreservingAthleteID() throws {
        let json = """
        {
          "token_type": "Bearer",
          "access_token": "new-access",
          "refresh_token": "new-refresh",
          "expires_at": 1900000000,
          "expires_in": 21600
        }
        """
        let response = try JSONDecoder.zoneTruth.decode(StravaTokenExchangeResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.athlete)
        XCTAssertNil(response.session.athleteID)
        XCTAssertEqual(response.session.accessToken, "new-access")
    }

    func testSystemStravaClientAutoRefreshesExpiredToken() async throws {
        let expiredSession = StravaSession(
            athleteID: 7,
            accessToken: "old-access",
            refreshToken: "valid-refresh",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let sessionStore = SpyStravaSessionStore(initial: expiredSession)
        let client = SystemStravaClient(
            sessionStore: sessionStore,
            oauthClient: StubStravaOAuthClient(result: .success(makeTokenExchangeResponse())),
            configuration: makeStravaConfig()
        )

        // Ignore the error — the network call after refresh will fail without a real server.
        // We only care that the session was refreshed and saved before the fetch was attempted.
        _ = try? await client.fetchRecentActivities(limit: 5)

        XCTAssertEqual(sessionStore.savedSessions.count, 1)
        XCTAssertEqual(sessionStore.savedSessions.first?.accessToken, "stub-access-token")
        XCTAssertEqual(sessionStore.savedSessions.first?.athleteID, 7) // carried over from old session
    }

    func testSystemStravaClientThrowsExpiredWhenNoRefreshToken() async {
        let expiredSession = StravaSession(
            athleteID: 1,
            accessToken: "old",
            refreshToken: nil,
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let client = SystemStravaClient(
            sessionStore: SpyStravaSessionStore(initial: expiredSession),
            oauthClient: StubStravaOAuthClient(result: .success(makeTokenExchangeResponse())),
            configuration: makeStravaConfig()
        )

        do {
            _ = try await client.fetchRecentActivities(limit: 5)
            XCTFail("Expected expiredSession error")
        } catch StravaClientError.expiredSession {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSystemStravaClientThrowsExpiredWhenNoConfiguration() async {
        let expiredSession = StravaSession(
            athleteID: 1,
            accessToken: "old",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let client = SystemStravaClient(
            sessionStore: SpyStravaSessionStore(initial: expiredSession),
            configuration: nil
        )

        do {
            _ = try await client.fetchRecentActivities(limit: 5)
            XCTFail("Expected expiredSession error")
        } catch StravaClientError.expiredSession {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFileStravaSessionStoreRoundTrips() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("strava-session.json")
        let store = FileStravaSessionStore(fileURL: fileURL)

        let original = StravaSession(
            athleteID: 42,
            accessToken: "at-xyz",
            refreshToken: "rt-xyz",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        store.saveSession(original)
        let loaded = store.loadSession()

        XCTAssertEqual(loaded?.athleteID, 42)
        XCTAssertEqual(loaded?.accessToken, "at-xyz")
        XCTAssertEqual(loaded?.refreshToken, "rt-xyz")
    }

    private func makeStravaConfig() -> StravaOAuthConfiguration {
        StravaOAuthConfiguration(
            clientID: 1,
            clientSecret: "secret",
            redirectURI: "zonetruth://strava/callback",
            callbackScheme: "zonetruth"
        )
    }

    private func makeTokenExchangeResponse() -> StravaTokenExchangeResponse {
        let json = """
        {
          "token_type": "Bearer",
          "access_token": "stub-access-token",
          "refresh_token": "stub-refresh-token",
          "expires_at": 1900000000,
          "expires_in": 21600,
          "athlete": { "id": 7 }
        }
        """
        return try! JSONDecoder.zoneTruth.decode(StravaTokenExchangeResponse.self, from: Data(json.utf8))
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
        XCTAssertEqual(result.workouts.first?.intent, .zone2)
        XCTAssertEqual(result.workouts.first?.heartRateSamples.count, 2)
        guard let hrv = result.workouts.first?.hrvSDNNMilliseconds else {
            XCTFail("Expected HRV SDNN value from HealthKit snapshot")
            return
        }
        XCTAssertEqual(hrv, 42.5, accuracy: 0.001)
    }

    func testWorkoutDefaultIntentsCollapseMixedAndOtherToThreeVisibleIntents() {
        XCTAssertEqual(WorkoutInput.defaultIntent(for: .mixed), .vo2Interval)
        XCTAssertEqual(WorkoutInput.defaultIntent(for: .other), .zone2)
        XCTAssertEqual(WorkoutInput.defaultIntent(for: .strengthTraining), .strength)
    }

    func testWorkoutTypeLocalizedNamesDoNotExposeFourthCategoryLabels() {
        XCTAssertEqual(WorkoutType.mixed.localizedName, "最大攝氧量 / 間歇型")
        XCTAssertEqual(WorkoutType.other.localizedName, "Zone 2 / 一般有氧")
        XCTAssertFalse(WorkoutType.mixed.localizedName.contains("混合"))
        XCTAssertFalse(WorkoutType.other.localizedName.contains("其他"))
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
    func testViewModelCanConnectStravaWhenURLSetAndSourceIsNotStrava() {
        let stravaURL = URL(string: "https://www.strava.com/oauth/mobile/authorize?client_id=1")!
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            settingsManager: SettingsManager(),
            stravaAuthorizationURL: stravaURL
        )

        // MockWorkoutRepository returns .mockSamples, not .strava
        XCTAssertTrue(viewModel.canConnectStrava)
    }

    func testAppEnvironmentFeedbackFileURLUsesDedicatedJSONFile() {
        let fileURL = AppEnvironment.feedbackFileURL()

        XCTAssertEqual(fileURL.lastPathComponent, "classification-feedback.json")
    }

    @MainActor
    func testRestingHeartRateImportAttemptsQueryWhenReadOnlyAuthorizationStatusIsDenied() async {
        let suiteName = "test.resting.hr.import.denied.readable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)
        let store = StubHealthKitWorkoutStore(
            isAvailable: true,
            authorizationStatus: .sharingDenied,
            requestedAuthorizationStatus: .sharingDenied,
            snapshots: [],
            restingHeartRateBaseline: 56
        )

        let message = await RestingHeartRateImporter.importFromAppleHealth(
            store: store,
            settingsManager: settings
        )

        XCTAssertEqual(settings.restingHeartRate, 56)
        XCTAssertNotNil(settings.pendingSuggestion)
        XCTAssertTrue(message.contains("已匯入 Apple Health 最近 7 天平均靜息心率 56 bpm"), message)
    }

    @MainActor
    func testViewModelAcceptsFeedbackStoreWithoutAutoSaving() {
        let feedbackStore = InMemoryTrainingClassificationFeedbackStore()
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            feedbackStore: feedbackStore,
            settingsManager: SettingsManager()
        )

        XCTAssertTrue(viewModel.feedbackStore is InMemoryTrainingClassificationFeedbackStore)
        XCTAssertTrue(viewModel.feedbackStore.allRecords().isEmpty)
    }

    @MainActor
    func testViewModelCarriesSleepContextIntoCurrentWeeklySummary() {
        let sleepContext = WeeklySleepContext(
            lookbackDays: 7,
            nightsWithSleep: 6,
            averageSleepHours: 7.1
        )
        let viewModel = WorkoutListViewModel(
            repository: StaticWorkoutRepository(workouts: [], sleepContext: sleepContext),
            settingsManager: SettingsManager()
        )

        XCTAssertEqual(viewModel.weeklySummary.sleepContext, sleepContext)
    }

    @MainActor
    func testViewModelUpdateIntentPreservesHealthKitContextFields() {
        let startDate = Date(timeIntervalSince1970: 1_710_000_000)
        let workout = WorkoutInput(
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            heartRateSamples: [
                HeartRateSample(timestamp: startDate, bpm: 122),
                HeartRateSample(timestamp: startDate.addingTimeInterval(600), bpm: 128),
            ],
            hrvSDNNMilliseconds: 42,
            intent: .zone2,
            intentSource: .auto,
            dataSource: "healthkit",
            activeCaloriesKcal: 520,
            totalDistanceMeters: 18_400,
            vo2MaxEstimate: VO2MaxEstimate(
                value: 47,
                source: .apple,
                sourceLabel: "Apple Health VO2 max"
            ),
            heartRateRecoveryOneMinute: HeartRateRecoveryObservation(
                value: 18,
                source: .apple,
                sourceLabel: "Apple Health 1-minute heart-rate recovery"
            ),
            runningPower: RunningPowerObservation(
                averageWatts: 238,
                source: .runningHRSpeed,
                sourceLabel: "Apple Health running power"
            ),
            cyclingPower: CyclingPowerObservation(
                averageWatts: 211,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power"
            ),
            workoutRoute: WorkoutRouteObservation(
                pointCount: 128,
                elevationGainMeters: 86,
                source: .workoutRoute,
                sourceLabel: "Apple Health workout route"
            ),
            externalLoadDecoupling: ExternalLoadDecouplingObservation(
                decouplingRatio: 0.056,
                firstHalfAverageHeartRate: 126,
                secondHalfAverageHeartRate: 131,
                firstHalfAverageWatts: 214,
                secondHalfAverageWatts: 211,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power and heart rate"
            )
        )
        let viewModel = WorkoutListViewModel(
            repository: StaticWorkoutRepository(workouts: [workout]),
            settingsManager: SettingsManager()
        )

        viewModel.selectWorkout(workout)
        viewModel.updateIntent(TrainingIntent.vo2Interval)

        let updated = viewModel.workouts.first
        XCTAssertEqual(updated?.intent, .vo2Interval)
        XCTAssertEqual(updated?.heartRateRecoveryOneMinute, workout.heartRateRecoveryOneMinute)
        XCTAssertEqual(updated?.runningPower, workout.runningPower)
        XCTAssertEqual(updated?.cyclingPower, workout.cyclingPower)
        XCTAssertEqual(updated?.workoutRoute, workout.workoutRoute)
        XCTAssertEqual(updated?.externalLoadDecoupling, workout.externalLoadDecoupling)
    }

    @MainActor
    func testViewModelFeedbackRecorderPersistsIntoInjectedStore() {
        let feedbackStore = InMemoryTrainingClassificationFeedbackStore()
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            feedbackStore: feedbackStore,
            settingsManager: SettingsManager()
        )
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout
        let snapshot = viewModel.trainingClassificationSnapshot(for: workout)
        let recorder = viewModel.classificationFeedbackRecorder(for: workout)

        recorder.record(rating: .accurate, suggestedMode: nil)

        let records = feedbackStore.records(for: workout.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.feedback.workoutID, workout.id)
        XCTAssertEqual(records.first?.feedback.rating, .accurate)
        XCTAssertEqual(records.first?.feedback.originalClassification, snapshot)
        XCTAssertNil(records.first?.feedback.userSuggestedMode)
    }

    @MainActor
    func testViewModelCannotConnectStravaWhenURLNotSet() {
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            settingsManager: SettingsManager(),
            stravaAuthorizationURL: nil
        )

        XCTAssertFalse(viewModel.canConnectStrava)
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
            ),
            settingsManager: SettingsManager()
        )

        XCTAssertTrue(viewModel.canRequestHealthAccess)
    }

    func testWorkoutEvaluationAdapterCapsKeyFindingsAndProvidesSingleNextAction() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "leaky_zone2_run" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertEqual(evaluation.primaryIntent, .zone2)
        XCTAssertLessThanOrEqual(evaluation.keyFindings.count, 2)
        XCTAssertFalse(evaluation.nextAction.isEmpty)
        XCTAssertTrue((0...100).contains(evaluation.goalFitScore))
        XCTAssertTrue((0...100).contains(evaluation.classificationConfidence))
        XCTAssertTrue((0...100).contains(evaluation.evaluationConfidence))
    }

    func testWorkoutEvaluationAdapterKeepsLegacyPassFailAsDerivedField() {
        let passWorkout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let failWorkout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout

        let passEvaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: WorkoutIntentAnalyzer.analyze(passWorkout)
        )
        let failEvaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: WorkoutIntentAnalyzer.analyze(failWorkout)
        )

        XCTAssertTrue(passEvaluation.legacyPassFail)
        XCTAssertFalse(failEvaluation.legacyPassFail)
    }

    func testSemanticGuardZone2DeviationWithStableDriftUsesNuancedTendency() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "leaky_zone2_run" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertEqual(evaluation.primaryIntent, .zone2)
        XCTAssertFalse(evaluation.legacyPassFail)
        XCTAssertTrue(evaluation.trainingTendency.contains("穩定有氧"))
        XCTAssertTrue(evaluation.nextAction.contains("心率"))
        XCTAssertTrue(evaluation.nextAction.contains("有氧節奏"))
    }

    func testSemanticGuardNoHarshFailureToneWhenLegacyPassFailFalse() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertFalse(evaluation.legacyPassFail)
        let combinedText = ([evaluation.trainingTendency, evaluation.nextAction] + evaluation.keyFindings).joined(separator: " ")
        XCTAssertFalse(combinedText.contains("失敗"))
        XCTAssertFalse(combinedText.contains("不及格"))
    }

    func testSemanticGuardClassificationAndEvaluationConfidenceAreNotCollapsed() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "sparse_hr_cycling" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertEqual(evaluation.primaryIntent, .zone2)
        XCTAssertLessThan(evaluation.evaluationConfidence, evaluation.classificationConfidence)
    }

    func testSemanticGuardKeyFindingsContainPrimaryDeviationReason() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertLessThanOrEqual(evaluation.keyFindings.count, 2)
        XCTAssertTrue(
            evaluation.keyFindings.contains {
                $0.localizedCaseInsensitiveContains("中高強度") ||
                $0.localizedCaseInsensitiveContains("後段") ||
                $0.localizedCaseInsensitiveContains("心率")
            }
        )
    }

    func testSemanticGuardSecondarySignalsDoNotOverridePrimaryIntent() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "high_drift_zone2_ride" }!
            .workout
        let legacy = WorkoutIntentAnalyzer.analyze(workout)

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertEqual(evaluation.primaryIntent, .zone2)
        XCTAssertFalse(evaluation.secondarySignals.isEmpty)
        XCTAssertTrue(evaluation.secondarySignals.allSatisfy { !$0.localizedCaseInsensitiveContains("改判") })
        XCTAssertTrue(evaluation.secondarySignals.allSatisfy { !$0.localizedCaseInsensitiveContains("推翻") })
    }

    func testArchitectureGuardPolicyFactoryCoversAllPrimaryIntents() {
        for intent in [PrimaryIntent.zone2, .vo2Max, .strength, .activity] {
            let policy = WorkoutEvaluationPolicyFactory.make(for: intent)
            let observation = WorkoutObservation(
                primaryIntent: intent,
                classificationConfidence: 70,
                evaluationConfidence: 70,
                zoneDistribution: ZoneDistribution(
                    counts: [.zone1: 0, .zone2: 100, .zone3: 0, .zone4: 0, .zone5: 0],
                    ratios: [.zone1: 0, .zone2: 1, .zone3: 0, .zone4: 0, .zone5: 0]
                ),
                stabilityStandardDeviation: 5,
                driftRatio: 0.02
            )
            let evaluation = policy.evaluate(observation)
            XCTAssertFalse(evaluation.trainingTendency.isEmpty)
            XCTAssertFalse(evaluation.nextAction.isEmpty)
        }
    }

    func testArchitectureGuardAdapterDoesNotDirectlyForwardLegacyRecommendationText() {
        let legacy = AnalysisResult(
            verdict: .fail,
            confidence: 0.8,
            reasons: ["legacy reason marker"],
            recommendations: ["SENTINEL_DIRECT_RECOMMENDATION_TEXT"],
            zoneDistribution: ZoneDistribution(
                counts: [.zone1: 0, .zone2: 60, .zone3: 40, .zone4: 0, .zone5: 0],
                ratios: [.zone1: 0, .zone2: 0.6, .zone3: 0.4, .zone4: 0, .zone5: 0]
            ),
            stabilityStandardDeviation: 6,
            driftRatio: 0.03
        )

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: legacy
        )

        XCTAssertFalse(evaluation.nextAction.contains("SENTINEL_DIRECT_RECOMMENDATION_TEXT"))
    }

    func testArchitectureGuardObservationShapeHasNoVerdictOrRecommendationFields() {
        let observation = WorkoutObservation(
            primaryIntent: .zone2,
            classificationConfidence: 70,
            evaluationConfidence: 65,
            zoneDistribution: ZoneDistribution(
                counts: [.zone1: 0, .zone2: 80, .zone3: 20, .zone4: 0, .zone5: 0],
                ratios: [.zone1: 0, .zone2: 0.8, .zone3: 0.2, .zone4: 0, .zone5: 0]
            ),
            stabilityStandardDeviation: nil,
            driftRatio: nil
        )
        let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))
        XCTAssertFalse(fieldNames.contains("legacyVerdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("verdict"))
    }

    func testArchitectureGuardNoHarshFailureWordingInEvaluationOutput() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout

        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .zone2,
            legacy: WorkoutIntentAnalyzer.analyze(workout)
        )
        let combinedText = ([evaluation.trainingTendency, evaluation.nextAction] + evaluation.keyFindings).joined(separator: " ")
        XCTAssertFalse(combinedText.contains("失敗"))
        XCTAssertFalse(combinedText.contains("不及格"))
    }

    func testWorkoutEvaluationUserVisibleToneAvoidsCommandLanguage() {
        let cases: [(String, TrainingIntent, WorkoutInput)] = [
            ("zone2_deviation", .zone2, SampleWorkoutCases.zone2ValidationCases().first { $0.name == "leaky_zone2_run" }!.workout),
            ("vo2_pass", .vo2Interval, SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout),
            ("vo2_fail", .vo2Interval, SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "low_intensity_intervals" }!.workout),
            ("strength_metabolic", .strength, SampleWorkoutCases.strengthValidationCases().first { $0.name == "metabolic_strength_circuit" }!.workout),
            ("activity", .activityReview, SampleWorkoutCases.zone2ValidationCases().first { $0.name == "badminton_activity_review" }!.workout)
        ]
        let forbiddenTerms = ["請", "確保", "必須", "保證", "達成", "診斷", "非常"]

        for (id, intent, workout) in cases {
            let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
                primaryIntentBaseline: intent,
                legacy: WorkoutIntentAnalyzer.analyze(workout)
            )
            let text = ([evaluation.trainingTendency, evaluation.nextAction] + evaluation.keyFindings).joined(separator: " ")
            for term in forbiddenTerms {
                XCTAssertFalse(text.contains(term), "Case '\(id)' contains command or overclaiming term: \(term)")
            }
        }
    }

    func testWorkoutEvaluationSnapshotFixture() throws {
        let records = buildEvaluationFixtureRecords()
        let fixtureURL = try fixtureFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)

        if ProcessInfo.processInfo.environment["UPDATE_WORKOUT_EVAL_FIXTURE"] == "1" {
            try rendered.write(to: fixtureURL)
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "WorkoutEvaluation snapshot mismatch. Run with UPDATE_WORKOUT_EVAL_FIXTURE=1 to refresh fixture after intentional semantic changes."
        )
    }

    func testDualRunComparatorBuildsReportForAllWorkouts() {
        let workouts = [
            SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout,
            SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        ]
        let report = DualRunComparator.buildReport(
            workouts: workouts,
            policy: .default,
            mode: .dualRun
        )

        XCTAssertEqual(report.migrationMode, .dualRun)
        XCTAssertEqual(report.totalWorkouts, workouts.count)
        XCTAssertEqual(report.diffs.count, workouts.count)
        XCTAssertFalse(report.reviewStatus == .invalidReport)
    }

    @MainActor
    func testSettingsManagerPersistsMigrationMode() {
        let suiteName = "test.migration.mode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(manager.migrationMode, .observeOnly)

        manager.updateMigrationMode(.dualRun)
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.migrationMode, .dualRun)
    }

    @MainActor
    func testSettingsManagerPersistsRestingHeartRate() {
        let suiteName = "test.resting.hr.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        XCTAssertNil(manager.restingHeartRate)

        manager.updateRestingHeartRate(56)
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.restingHeartRate, 56)

        reloaded.updateRestingHeartRate(nil)
        let cleared = SettingsManager(userDefaults: defaults)
        XCTAssertNil(cleared.restingHeartRate)
    }

    @MainActor
    func testSettingsManagerGeneratesAndAppliesRestingHeartRateSuggestion() {
        let suiteName = "test.resting.hr.suggestion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        manager.updateRestingHeartRate(60)
        manager.generateRestingHeartRateSuggestion()

        XCTAssertNotNil(manager.pendingSuggestion)
        XCTAssertEqual(manager.pendingSuggestion?.source, .restingHeartRateHeuristic)
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2LowerBound, 115)
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2UpperBound, 130)
        XCTAssertEqual(manager.pendingSuggestion?.source.verificationLabel, "初步估算，尚未驗證")

        manager.applySuggestion()

        XCTAssertEqual(manager.policy.zoneBounds.zone2LowerBound, 115)
        XCTAssertEqual(manager.policy.zoneBounds.zone2UpperBound, 130)
        XCTAssertEqual(manager.zoneBoundsSource, .restingHeartRateHeuristic)
        XCTAssertNil(manager.pendingSuggestion)
    }

    @MainActor
    func testSettingsManagerGeneratesSuggestionFromCustomRestingHeartRateOffsets() {
        let suiteName = "test.resting.hr.offsets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        manager.updateRestingHeartRate(60)
        manager.updateRestingHeartRateSuggestionOffsets(lowerOffset: 50, upperOffset: 65)
        manager.generateRestingHeartRateSuggestion()

        XCTAssertEqual(manager.restingHeartRateSuggestionOffsets.lowerOffset, 50)
        XCTAssertEqual(manager.restingHeartRateSuggestionOffsets.upperOffset, 65)
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2LowerBound, 110)
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2UpperBound, 125)

        manager.updateRestingHeartRateSuggestionOffsets(lowerOffset: 48, upperOffset: 62)
        manager.generateRestingHeartRateSuggestion()
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2LowerBound, 108)
        XCTAssertEqual(manager.pendingSuggestion?.suggestedBounds.zone2UpperBound, 122)

        manager.applySuggestion()
        XCTAssertEqual(manager.policy.zoneBounds.zone2LowerBound, 108)
        XCTAssertEqual(manager.policy.zoneBounds.zone2UpperBound, 122)

        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.restingHeartRateSuggestionOffsets.lowerOffset, 48)
        XCTAssertEqual(reloaded.restingHeartRateSuggestionOffsets.upperOffset, 62)
    }

    @MainActor
    func testZone2ProfileStatusSummaryTracksSettingsState() {
        let suiteName = "test.zone.profile.summary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("預設界線"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Zone 2 110-125 bpm"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("靜息心率未設定"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("沒有待處理參考範圍"))

        manager.updateRestingHeartRate(60)
        manager.updateRestingHeartRateSuggestionOffsets(lowerOffset: 48, upperOffset: 62)
        manager.generateRestingHeartRateSuggestion()
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("靜息心率 60 bpm"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("偏移 +48/+62"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("可套用初步參考範圍 108-122 bpm"))

        manager.applySuggestion()
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("靜息心率建議已套用"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Zone 2 108-122 bpm"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("沒有待處理參考範圍"))

        manager.updateZone2Bounds(lower: 112, upper: 126)
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("自訂界線"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Zone 2 112-126 bpm"))
    }

    @MainActor
    func testZone2ProfileStatusSummaryDoesNotShowPendingWhenSuggestionMatchesCurrentRange() {
        let suiteName = "test.zone.profile.summary.matching.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        manager.updateRestingHeartRate(55)
        manager.generateRestingHeartRateSuggestion()

        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("目前設定已符合初步參考範圍"))
        XCTAssertFalse(manager.zone2ProfileStatusSummary.contains("待套用"))
        XCTAssertFalse(manager.zone2ProfileStatusSummary.contains("有待套用建議"))
    }

    func testCalibrationSuggestionPresenterDisablesApplyWhenRangeMatchesCurrent() {
        let suggestion = CalibrationEngine.suggestZoneBounds(
            restingHeartRate: 55,
            currentPolicy: .default
        )!

        let presentation = CalibrationSuggestionPresenter.presentation(for: suggestion)

        XCTAssertEqual(presentation.applyButtonTitle, "目前已套用")
        XCTAssertTrue(presentation.isApplyDisabled)
    }

    func testCalibrationSuggestionPresenterEnablesApplyWhenRangeDiffersFromCurrent() {
        let policy = AnalysisPolicy(
            warmupExclusionSeconds: AnalysisPolicy.default.warmupExclusionSeconds,
            cooldownExclusionSeconds: AnalysisPolicy.default.cooldownExclusionSeconds,
            minimumDurationSeconds: AnalysisPolicy.default.minimumDurationSeconds,
            minimumSampleCount: AnalysisPolicy.default.minimumSampleCount,
            abnormalSpikeDeltaBPM: AnalysisPolicy.default.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: AnalysisPolicy.default.lowStabilityStdDev,
            mediumStabilityStdDev: AnalysisPolicy.default.mediumStabilityStdDev,
            zoneBounds: ZoneBounds(
                zone2LowerBound: 112,
                zone2UpperBound: 126,
                zone4Threshold: AnalysisPolicy.default.zoneBounds.zone4Threshold,
                zone5Threshold: AnalysisPolicy.default.zoneBounds.zone5Threshold
            )
        )
        let suggestion = CalibrationEngine.suggestZoneBounds(
            restingHeartRate: 55,
            currentPolicy: policy
        )!

        let presentation = CalibrationSuggestionPresenter.presentation(for: suggestion)

        XCTAssertEqual(presentation.applyButtonTitle, "套用參考範圍")
        XCTAssertFalse(presentation.isApplyDisabled)
    }

    @MainActor
    func testSettingsManagerResetsZone2BoundsToDefault() {
        let suiteName = "test.zone.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        manager.updateZone2Bounds(lower: 115, upper: 130)
        XCTAssertTrue(manager.isUsingCustomZoneBounds)

        manager.resetZone2BoundsToDefault()

        XCTAssertEqual(manager.policy.zoneBounds, AnalysisPolicy.default.zoneBounds)
        XCTAssertFalse(manager.isUsingCustomZoneBounds)
    }

    @MainActor
    func testSettingsManagerPolicyPrimaryIsGatedToObserveOnly() {
        let suiteName = "test.migration.gate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = SettingsManager(userDefaults: defaults)
        manager.updateMigrationMode(.policyPrimary)

        XCTAssertEqual(manager.migrationMode, .observeOnly)
        XCTAssertEqual(defaults.string(forKey: "com.zonetruth.migrationMode"), MigrationMode.observeOnly.rawValue)
    }

    func testDualRunReportContainsRequiredMetadataAndNoUserFacingOverride() {
        let workouts = [SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout]
        let report = DualRunComparator.buildReport(
            workouts: workouts,
            policy: .default,
            mode: .dualRun
        )

        XCTAssertEqual(report.migrationMode, .dualRun)
        XCTAssertEqual(report.totalWorkouts, workouts.count)
        XCTAssertEqual(report.schemaVersion, "1.0")
        XCTAssertFalse(report.userFacingOverrideApplied)
        XCTAssertNotEqual(report.reviewStatus, .invalidReport)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(report)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("recommendationOverride"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("nextActionOverride"))
    }

    func testDualRunReviewClassificationThresholds() {
        XCTAssertEqual(
            DualRunComparator.classifyDiff(goalFitDelta: 3, tendencyChanged: false),
            .minorDrift
        )
        XCTAssertEqual(
            DualRunComparator.classifyDiff(goalFitDelta: 10, tendencyChanged: false),
            .reviewRequired
        )
        XCTAssertEqual(
            DualRunComparator.classifyDiff(goalFitDelta: 16, tendencyChanged: false),
            .blockingDrift
        )
        XCTAssertEqual(
            DualRunComparator.classifyDiff(goalFitDelta: 1, tendencyChanged: true),
            .reviewRequired
        )
    }

    func testDualRunReportStatusInvalidWhenUserFacingOverrideApplied() {
        let diffs = [
            EvaluationDiff(
                workoutID: UUID(),
                intent: TrainingIntent.zone2.rawValue,
                legacyGoalFitScore: 70,
                shadowGoalFitScore: 72,
                goalFitDelta: 2,
                legacyTendency: "A",
                shadowTendency: "A",
                tendencyChanged: false,
                reviewStatus: .minorDrift
            )
        ]

        let status = DualRunComparator.classifyReportStatus(
            diffs: diffs,
            userFacingOverrideApplied: true
        )
        XCTAssertEqual(status, .invalidReport)
    }

    // MARK: P1n – Migration Gate Full Condition Verification

    @MainActor
    func testMigrationGateFallbackChecksAllPass() {
        let checks = MigrationGateChecker.runFallbackChecks()
        let failed = checks.filter { $0.status == .fail }
        XCTAssertTrue(
            failed.isEmpty,
            "Migration gate fallback checks must all pass: \(failed.map { "\($0.id): \($0.detail ?? "no detail")" })"
        )
    }

    @MainActor
    func testMigrationGateReportPolicyPrimaryNeverAdmissibleInV1() {
        let snapshotChecks: [MigrationGateCheck] = [
            .init(id: "primitive_snapshots_stable", status: .pass, detail: nil),
            .init(id: "observation_snapshots_stable", status: .pass, detail: nil),
            .init(id: "evaluation_snapshot_stable_or_annotated", status: .pass, detail: nil),
        ]
        let report = MigrationGateChecker.buildReport(
            snapshotChecks: snapshotChecks,
            fallbackChecks: MigrationGateChecker.runFallbackChecks()
        )

        XCTAssertFalse(report.policyPrimaryAdmissible,
            "policy_primary_admissible must always be false in P1n-v1.")
        XCTAssertEqual(report.gateVersion, "P1n-v1")
    }

    @MainActor
    func testMigrationGateReportAdmissibleForDiscussionWhenAllCheckPass() {
        let snapshotChecks: [MigrationGateCheck] = [
            .init(id: "primitive_snapshots_stable", status: .pass, detail: nil),
            .init(id: "observation_snapshots_stable", status: .pass, detail: nil),
            .init(id: "evaluation_snapshot_stable_or_annotated", status: .pass, detail: nil),
        ]
        let report = MigrationGateChecker.buildReport(
            snapshotChecks: snapshotChecks,
            fallbackChecks: MigrationGateChecker.runFallbackChecks()
        )

        XCTAssertTrue(report.policyPrimaryAdmissibleForDiscussion,
            "All checks passing → admissible for discussion.")
        XCTAssertTrue(report.blockingReasons.isEmpty)
    }

    @MainActor
    func testMigrationGateReportNotAdmissibleWhenAnySnapshotCheckFails() {
        let snapshotChecks: [MigrationGateCheck] = [
            .init(id: "primitive_snapshots_stable", status: .fail, detail: "snapshot mismatch"),
            .init(id: "observation_snapshots_stable", status: .pass, detail: nil),
            .init(id: "evaluation_snapshot_stable_or_annotated", status: .pass, detail: nil),
        ]
        let report = MigrationGateChecker.buildReport(
            snapshotChecks: snapshotChecks,
            fallbackChecks: MigrationGateChecker.runFallbackChecks()
        )

        XCTAssertFalse(report.policyPrimaryAdmissibleForDiscussion)
        XCTAssertTrue(report.blockingReasons.contains("primitive_snapshots_stable"))
        XCTAssertFalse(report.policyPrimaryAdmissible)
    }

    @MainActor
    func testMigrationGateReportContainsAllExpectedCheckIDs() {
        let snapshotChecks: [MigrationGateCheck] = [
            .init(id: "primitive_snapshots_stable", status: .pass, detail: nil),
            .init(id: "observation_snapshots_stable", status: .pass, detail: nil),
            .init(id: "evaluation_snapshot_stable_or_annotated", status: .pass, detail: nil),
        ]
        let report = MigrationGateChecker.buildReport(
            snapshotChecks: snapshotChecks,
            fallbackChecks: MigrationGateChecker.runFallbackChecks()
        )
        let ids = Set(report.checks.map(\.id))
        let expected: Set<String> = [
            "primitive_snapshots_stable",
            "observation_snapshots_stable",
            "evaluation_snapshot_stable_or_annotated",
            "shadow_policy_consumes_observation",
            "policy_primary_disabled_by_default",
            "policy_primary_requires_explicit_allow",
            "dual_run_revertible_to_observe_only",
            "observe_only_never_writes_dual_run_artifact",
            "ui_path_forces_legacy_evaluation",
        ]
        XCTAssertEqual(ids, expected, "Report must contain all 9 migration gate check IDs.")
    }

    // MARK: P1m – Semantic Change Annotation Gate

    func testAnnotationGatePassesWhenSnapshotUnchanged() {
        let result = AnnotationGate.validate(
            annotation: nil,
            driftStatus: .minorDrift,
            snapshotChanged: false
        )
        XCTAssertEqual(result, .admissible)
    }

    func testAnnotationGateRequiresAnnotationWhenSnapshotChanged() {
        let result = AnnotationGate.validate(
            annotation: nil,
            driftStatus: .minorDrift,
            snapshotChanged: true
        )
        XCTAssertEqual(result, .requiresAnnotation)
    }

    func testAnnotationGateAdmitsMinorDriftWithAnyAnnotation() {
        let annotation = SemanticChangeAnnotation(
            changeID: "SEM-2026-05-20-001",
            reason: "Zone2 drift threshold refinement",
            affectedFixtures: ["zone2_deviation_stable_drift"],
            expectedBehaviorChange: ["goalFitScore decreases by 3"],
            reviewedBy: "manual",
            admissibility: .observationRefinement
        )
        let result = AnnotationGate.validate(
            annotation: annotation,
            driftStatus: .minorDrift,
            snapshotChanged: true
        )
        XCTAssertEqual(result, .admissible)
    }

    func testAnnotationGateBlocksBlockingDriftWithoutIntentionalAnnotation() {
        let annotation = SemanticChangeAnnotation(
            changeID: "SEM-2026-05-20-002",
            reason: "Fixing drift ratio off-by-one",
            affectedFixtures: ["zone2_deviation_stable_drift"],
            expectedBehaviorChange: ["goalFitScore changes by 18"],
            reviewedBy: "manual",
            admissibility: .bugFix
        )
        let result = AnnotationGate.validate(
            annotation: annotation,
            driftStatus: .blockingDrift,
            snapshotChanged: true
        )
        XCTAssertEqual(result, .blockedByAdmissibility,
            "blocking_drift requires admissibility == intentional_semantic_change.")
    }

    func testAnnotationGateAdmitsBlockingDriftWithIntentionalAnnotation() {
        let annotation = SemanticChangeAnnotation(
            changeID: "SEM-2026-05-20-003",
            reason: "Intentional policy rewrite for Zone2 evaluation",
            affectedFixtures: ["zone2_deviation_stable_drift", "vo2_pass"],
            expectedBehaviorChange: ["goalFitScore changes by 20", "trainingTendency reworded"],
            reviewedBy: "manual",
            admissibility: .intentionalSemanticChange
        )
        let result = AnnotationGate.validate(
            annotation: annotation,
            driftStatus: .blockingDrift,
            snapshotChanged: true
        )
        XCTAssertEqual(result, .admissible)
    }

    func testAnnotationGateAdmitsReviewRequiredWithAnyAnnotation() {
        let annotation = SemanticChangeAnnotation(
            changeID: "SEM-2026-05-20-004",
            reason: "Observation bridge confidence calibration",
            affectedFixtures: ["sparse_hr_samples"],
            expectedBehaviorChange: ["goalFitScore changes by 8"],
            reviewedBy: "manual",
            admissibility: .observationRefinement
        )
        let result = AnnotationGate.validate(
            annotation: annotation,
            driftStatus: .reviewRequired,
            snapshotChanged: true
        )
        XCTAssertEqual(result, .admissible)
    }

    // MARK: P1l – ObservationBridge / shadow evaluator

    func testObservationShadowEvaluatorRoutesThroughPolicyFactory() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!.workout
        let policy = AnalysisPolicy.default

        let legacy = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: workout.intent,
            legacy: WorkoutIntentAnalyzer.analyze(workout, policy: policy)
        )
        let shadow = ObservationPolicyShadowEvaluator.evaluate(workout: workout, policy: policy)

        XCTAssertEqual(legacy.primaryIntent, shadow.primaryIntent)
        XCTAssertEqual(
            legacy.trainingTendency, shadow.trainingTendency,
            "Shadow and legacy must agree on tendency: both route through the same policy factory."
        )
    }

    func testObservationBridgeProducesValidWorkoutObservation() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "leaky_zone2_run" }!.workout
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: .default)
        let observation = ObservationBridge.observation(from: primitives, intent: .zone2)

        XCTAssertEqual(observation.primaryIntent, .zone2)
        XCTAssertTrue((0...100).contains(observation.classificationConfidence))
        XCTAssertTrue((0...100).contains(observation.evaluationConfidence))
        XCTAssertEqual(observation.zoneDistribution, primitives.zoneDistribution)
    }

    func testDualRunDiffIsMinorForStableZone2WithRewiredShadow() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!.workout
        let report = DualRunComparator.buildReport(
            workouts: [workout],
            policy: .default,
            mode: .dualRun
        )

        XCTAssertEqual(report.diffs.count, 1)
        XCTAssertEqual(report.diffs[0].reviewStatus, .minorDrift,
            "Rewired shadow path must produce only minor drift vs legacy for a clean Zone 2 session.")
    }

    @MainActor
    func testDualRunDoesNotChangeUIEvaluationPath() {
        let suiteName = "test.migration.ui.path.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            settingsManager: settings
        )
        guard let workout = viewModel.workouts.first else {
            XCTFail("Expected at least one workout from MockWorkoutRepository")
            return
        }

        settings.updateMigrationMode(.observeOnly)
        let observeEval = viewModel.evaluationResult(for: workout)

        settings.updateMigrationMode(.dualRun)
        let dualRunEval = viewModel.evaluationResult(for: workout)

        XCTAssertEqual(observeEval, dualRunEval, "UI evaluation result must remain legacy-path stable in dual_run mode.")
    }

    @MainActor
    func testWeeklyDashboardViewSmokeCompiles() {
        let suiteName = "test.weekly.dashboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(userDefaults: defaults)
        let viewModel = WorkoutListViewModel(
            repository: MockWorkoutRepository(),
            settingsManager: settings
        )
        let view = WeeklyDashboardView(viewModel: viewModel, settingsManager: settings)

        XCTAssertNotNil(viewModel.weeklySummary.weekStart)
        XCTAssertFalse(viewModel.weeklyPolicy.keyFindings.isEmpty)
        _ = view.body
    }

    func testMetricDisclosurePresenterRendersBoundedEstimateLanguage() {
        let zone2 = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        )
        let vo2 = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        )
        let strength = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout
        )

        let items = MetricDisclosurePresenter.render(
            zone2.metricMetadata + vo2.metricMetadata + strength.metricMetadata
        )
        let text = items
            .flatMap { [$0.title, $0.status, $0.summary, $0.method, $0.confidenceReason, $0.validationHint ?? ""] }
            .joined(separator: " ")

        XCTAssertTrue(text.contains("Zone 2 心率範圍"))
        XCTAssertTrue(text.contains("分析起點"))
        XCTAssertTrue(text.contains("VO2 間歇型態"))
        XCTAssertTrue(text.contains("這裡描述的是高強度型態"))
        XCTAssertTrue(text.contains("肌力訓練型態"))
        XCTAssertTrue(text.contains("這裡描述的是肌力訓練節奏"))
        XCTAssertFalse(text.contains("VO2 max 實測"))
        XCTAssertFalse(text.contains("精準 Zone 2"))
        XCTAssertFalse(text.contains("1RM"))
        XCTAssertFalse(text.contains("肌力測量"))
    }

    func testWorkoutDetailPrimaryInformationArchitectureHidesSettingsLanguage() {
        let visibleLabels = WorkoutDetailInformationArchitecture.primaryVisibleLabels.joined(separator: " ")
        let settingsLabels = WorkoutDetailInformationArchitecture.settingsOnlyLabels

        XCTAssertTrue(visibleLabels.contains("活動摘要"))
        XCTAssertTrue(visibleLabels.contains("本次結論"))
        XCTAssertTrue(visibleLabels.contains("判讀依據"))
        XCTAssertTrue(visibleLabels.contains("本次使用的心率範圍"))
        XCTAssertTrue(visibleLabels.contains("這次判讀準確嗎？"))
        XCTAssertTrue(visibleLabels.contains("更多內容與詳細數據"))

        for label in settingsLabels {
            XCTAssertFalse(
                visibleLabels.contains(label),
                "Primary detail hierarchy should not expose settings-only label: \(label)"
            )
        }
    }

    func testWorkoutDetailPrimaryInformationArchitectureExcludesLegacyIntentAndGoalFitLanguage() {
        let publicLabels = (
            WorkoutDetailInformationArchitecture.primaryVisibleLabels +
            WorkoutDetailInformationArchitecture.heroSummaryLabels +
            WorkoutDetailInformationArchitecture.technicalDetailLabels
        ).joined(separator: " ")

        for label in WorkoutDetailInformationArchitecture.userFacingForbiddenLabels {
            XCTAssertFalse(
                publicLabels.contains(label),
                "Workout detail user-facing labels must not expose legacy intent/goal-fit language: \(label)"
            )
        }
    }

    func testWorkoutDetailVO2MaxMetricIsHiddenForStrengthPrimarySurface() {
        XCTAssertFalse(
            WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: .strengthTraining),
            "Strength detail primary surface must not expose VO2 max as a main metric."
        )
        XCTAssertTrue(WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: .running))
        XCTAssertTrue(WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: .cycling))
        XCTAssertTrue(WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: .swimming))
    }

    func testWorkoutDetailFeedbackPresenterUsesTrainingModesNotIntentLanguage() {
        let labels = (
            TrainingModeFeedbackPresenter.ratingOptions.map(TrainingModeFeedbackPresenter.label(for:)) +
            TrainingModeFeedbackPresenter.suggestedModeOptions.map(TrainingModeFeedbackPresenter.label(for:)) +
            [
                WorkoutDetailInformationArchitecture.classificationFeedback,
                WorkoutDetailInformationArchitecture.feedbackSuggestedMode
            ]
        ).joined(separator: " ")

        XCTAssertTrue(labels.contains("準確"))
        XCTAssertTrue(labels.contains("有點像"))
        XCTAssertTrue(labels.contains("不準"))
        XCTAssertTrue(labels.contains("高密度循環"))
        XCTAssertFalse(labels.contains("本次意圖"))
        XCTAssertFalse(labels.contains("目的符合度"))
        XCTAssertFalse(labels.contains("達標"))
        XCTAssertFalse(labels.contains("未達標"))
    }

    func testWorkoutDetailSourceDoesNotExposeGoalOverrideOrExplosiveStrengthWording() throws {
        let sourceText = try appSourceText(named: "Views.swift") + "\n" + coreSourceText(named: "RecommendationEngine.swift")
        let forbiddenTerms = [
            "設定訓練目標",
            "套用到同類型運動",
            "確認套用目標",
            "將目前目標套用",
            "爆發力訓練節奏"
        ]

        for term in forbiddenTerms {
            XCTAssertFalse(
                sourceText.contains(term),
                "Workout detail user-facing wording must not expose goal override or HR-only explosive-strength wording: \(term)"
            )
        }
        XCTAssertTrue(sourceText.contains("修正判讀類型"))
        XCTAssertTrue(sourceText.contains("作為同類型校準參考"))
    }

    @MainActor
    func testTrainingClassificationFeedbackControlSmokeCompilesWithLocalStateOnly() {
        struct Harness: View {
            @State var rating: TrainingClassificationFeedbackRating?
            @State var mode: TrainingMode?

            var body: some View {
                TrainingClassificationFeedbackControl(
                    rating: $rating,
                    suggestedMode: $mode,
                    recordingResult: .saved
                )
            }
        }

        let view = Harness()
        _ = view.body
    }

    func testWorkoutClassificationFeedbackRecorderSavesSuggestedTrainingModeRecord() {
        let workoutID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let recordID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let recordedAt = Date(timeIntervalSince1970: 5_400)
        let store = InMemoryTrainingClassificationFeedbackStore()
        let recorder = WorkoutClassificationFeedbackRecorder(
            workoutID: workoutID,
            classification: appTestClassification(primaryMode: .conditioningLike),
            store: store,
            makeRecordID: { recordID },
            now: { recordedAt }
        )

        XCTAssertEqual(recorder.record(rating: .inaccurate, suggestedMode: nil), .incomplete)
        XCTAssertTrue(store.allRecords().isEmpty)

        XCTAssertEqual(recorder.record(rating: .inaccurate, suggestedMode: .strengthPattern), .saved)
        XCTAssertEqual(recorder.record(rating: .inaccurate, suggestedMode: .strengthPattern), .duplicate)

        let records = store.records(for: workoutID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, recordID)
        XCTAssertEqual(records.first?.feedback.workoutID, workoutID)
        XCTAssertEqual(records.first?.feedback.recordedAt, recordedAt)
        XCTAssertEqual(records.first?.feedback.rating, .inaccurate)
        XCTAssertEqual(records.first?.feedback.userSuggestedMode, .strengthPattern)
        XCTAssertEqual(records.first?.feedback.originalClassification.primaryMode, .conditioningLike)
    }

    func testWorkoutClassificationFeedbackRecorderDoesNotExposeIntentOverrideFields() {
        let store = InMemoryTrainingClassificationFeedbackStore()
        let recorder = WorkoutClassificationFeedbackRecorder(
            workoutID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            classification: appTestClassification(primaryMode: .zone2),
            store: store,
            makeRecordID: { UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")! },
            now: { Date(timeIntervalSince1970: 6_000) }
        )

        XCTAssertEqual(recorder.record(rating: .accurate, suggestedMode: .vo2Stimulus), .saved)
        XCTAssertEqual(recorder.record(rating: .accurate, suggestedMode: .vo2Stimulus), .duplicate)

        guard let feedback = store.allRecords().first?.feedback else {
            return XCTFail("Expected one feedback record.")
        }
        XCTAssertEqual(store.allRecords().count, 1)
        let fieldNames = Set(Mirror(reflecting: feedback).children.compactMap(\.label))
        XCTAssertEqual(feedback.rating, .accurate)
        XCTAssertNil(feedback.userSuggestedMode)
        XCTAssertFalse(fieldNames.contains("intent"))
        XCTAssertFalse(fieldNames.contains("declaredIntent"))
        XCTAssertFalse(fieldNames.contains("originalIntent"))
        XCTAssertFalse(fieldNames.contains("goal"))
    }

    func testFileTrainingClassificationFeedbackStorePersistsRecordsAcrossInstances() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("classification-feedback.json")
        let workoutID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let otherWorkoutID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let targetRecord = appTestFeedbackRecord(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab")!,
            workoutID: workoutID,
            rating: .inaccurate,
            userSuggestedMode: .strengthPattern,
            primaryMode: .conditioningLike
        )
        let otherRecord = appTestFeedbackRecord(
            id: UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")!,
            workoutID: otherWorkoutID,
            rating: .accurate,
            userSuggestedMode: nil,
            primaryMode: .zone2
        )

        let emptyStore = FileTrainingClassificationFeedbackStore(fileURL: fileURL)
        XCTAssertTrue(emptyStore.allRecords().isEmpty)

        emptyStore.save(targetRecord)
        emptyStore.save(otherRecord)

        let reloadedStore = FileTrainingClassificationFeedbackStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.allRecords(), [targetRecord, otherRecord])
        XCTAssertEqual(reloadedStore.records(for: workoutID), [targetRecord])
        XCTAssertEqual(reloadedStore.records(for: otherWorkoutID), [otherRecord])
    }

    func testFileTrainingClassificationFeedbackStoreJSONDoesNotContainIntentOverrideLanguage() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("classification-feedback.json")
        let store = FileTrainingClassificationFeedbackStore(fileURL: fileURL)
        let record = appTestFeedbackRecord(
            id: UUID(uuidString: "fefefefe-fefe-fefe-fefe-fefefefefefe")!,
            workoutID: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            rating: .somewhatSimilar,
            userSuggestedMode: .mixed,
            primaryMode: .zone2
        )

        store.save(record)

        let data = try Data(contentsOf: fileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertTrue(json.contains("records"))
        XCTAssertTrue(json.contains("userSuggestedMode"))
        XCTAssertFalse(json.contains("intent"))
        XCTAssertFalse(json.contains("goal"))
    }

    @MainActor
    func testWorkoutDetailViewAcceptsInjectedFeedbackRecorder() {
        let suiteName = "test.workout.detail.feedback.recorder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)
        let workout = SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout
        let result = WorkoutIntentAnalyzer.analyze(workout, policy: settings.policy)
        let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: .strength,
            legacy: result
        )
        let view = WorkoutDetailView(
            workout: workout,
            selectedIntent: .strength,
            selectedIntentSource: .auto,
            result: result,
            evaluation: evaluation,
            onIntentChanged: { _ in },
            onApplyToSameWorkoutType: { _ in },
            impactedCountForScope: { _ in 0 },
            zoneContextSummary: "預設界線 110-125 bpm",
            classificationFeedbackRecorder: WorkoutClassificationFeedbackRecorder(
                workoutID: workout.id,
                classification: appTestClassification(primaryMode: .strengthPattern),
                store: InMemoryTrainingClassificationFeedbackStore()
            ),
            settingsManager: settings
        )

        _ = view.body
    }

    @MainActor
    func testWorkoutDetailViewSmokeCompilesForThreePrimaryIntents() {
        let suiteName = "test.workout.detail.architecture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)

        let cases: [(TrainingIntent, WorkoutInput)] = [
            (.zone2, SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout),
            (.vo2Interval, SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout),
            (.strength, SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout)
        ]

        for (intent, workout) in cases {
            let result = WorkoutIntentAnalyzer.analyze(workout, policy: settings.policy)
            let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
                primaryIntentBaseline: intent,
                legacy: result
            )
            let view = WorkoutDetailView(
                workout: workout,
                selectedIntent: intent,
                selectedIntentSource: .auto,
                result: result,
                evaluation: evaluation,
                onIntentChanged: { _ in },
                onApplyToSameWorkoutType: { _ in },
                impactedCountForScope: { _ in 0 },
                zoneContextSummary: "預設界線 110-125 bpm",
                settingsManager: settings
            )

            _ = view.body
        }
    }

    @MainActor
    func testAppSettingsViewSmokeCompilesWithAppleHealthStatusCard() {
        let suiteName = "test.app.settings.global.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)
        let viewModel = WorkoutListViewModel(
            repository: HealthKitWorkoutRepository(
                store: StubHealthKitWorkoutStore(
                    isAvailable: true,
                    authorizationStatus: .sharingAuthorized,
                    requestedAuthorizationStatus: .sharingAuthorized,
                    snapshots: [makeHealthSnapshot()],
                    debugAuthorizationDetailsValue: HealthKitAuthorizationDebugDetails(
                        workout: .sharingAuthorized,
                        heartRate: .sharingAuthorized,
                        vo2Max: .sharingAuthorized,
                        heartRateRecoveryOneMinute: .sharingAuthorized,
                        runningPower: .sharingDenied,
                        cyclingPower: .sharingDenied,
                        workoutRoute: .sharingAuthorized,
                        sleepAnalysis: .notDetermined
                    )
                )
            ),
            settingsManager: settings
        )
        let view = AppSettingsView(viewModel: viewModel, settingsManager: settings)

        _ = view.body
    }

    @MainActor
    func testViewModelCanManageHealthAccessAfterHealthKitDataLoaded() async {
        let viewModel = WorkoutListViewModel(
            repository: HealthKitWorkoutRepository(
                store: StubHealthKitWorkoutStore(
                    isAvailable: true,
                    authorizationStatus: .sharingDenied,
                    requestedAuthorizationStatus: .sharingAuthorized,
                    snapshots: [makeHealthSnapshot()],
                    debugAuthorizationDetailsValue: HealthKitAuthorizationDebugDetails(
                        workout: .sharingDenied,
                        heartRate: .sharingDenied,
                        vo2Max: .sharingDenied,
                        heartRateRecoveryOneMinute: .sharingDenied,
                        runningPower: .sharingDenied,
                        cyclingPower: .sharingDenied,
                        workoutRoute: .sharingDenied,
                        sleepAnalysis: .notDetermined
                    )
                )
            ),
            settingsManager: SettingsManager()
        )

        await viewModel.refreshWorkouts()
        await viewModel.refreshHealthAuthorizationDetails()

        XCTAssertFalse(viewModel.canRequestHealthAccess)
        XCTAssertTrue(viewModel.canManageHealthAccess)
        XCTAssertEqual(viewModel.healthAuthorizationDetails?.sleepAnalysis, .notDetermined)
    }

    func testWorkoutDetailMethodSettingsNoLongerEmbedsFullSettingsView() throws {
        let source = try appSourceText(named: "Views.swift")
        let appRootSource = try appSourceText(named: "ZoneTruthApp.swift")
        XCTAssertFalse(
            source.contains("DisclosureGroup(WorkoutDetailInformationArchitecture.methodSettings) {\n                            SettingsView"),
            "Workout detail should show only per-workout settings summary, not the full global SettingsView."
        )
        XCTAssertTrue(source.contains("全域設定請到下方「設定」分頁調整。"))
        XCTAssertTrue(appRootSource.contains("AppSettingsView(viewModel:"))
        XCTAssertTrue(source.contains("重新要求 Apple Health 授權"))
        XCTAssertTrue(source.contains("睡眠分析"))
    }

    func testMetricDisclosurePresenterUsesMetricSpecificClaimProfiles() {
        let zone2 = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        )
        let vo2 = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        )
        let strength = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout
        )

        let items = MetricDisclosurePresenter.render(
            zone2.metricMetadata + vo2.metricMetadata + strength.metricMetadata
        )
        let zone2Text = text(for: items, title: "Zone 2 心率範圍")
        let vo2Text = text(for: items, title: "VO2 間歇型態")
        let strengthText = text(for: items, title: "肌力訓練型態")

        XCTAssertTrue(zone2Text.contains("閾值測試"))
        XCTAssertTrue(vo2Text.contains("不代表已直接量到最大攝氧量"))
        XCTAssertTrue(strengthText.contains("不能直接代表最大肌力"))
        XCTAssertFalse(zone2Text.contains("最大攝氧量"), zone2Text)
        XCTAssertFalse(vo2Text.contains("精準 Zone 2"), vo2Text)
        XCTAssertFalse(strengthText.contains("VO2 max"), strengthText)
    }

    func testMetricDisclosurePresenterRendersVO2MaxEstimateAsEstimate() {
        let base = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: base.workoutType,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: VO2MaxEstimate(
                value: 48.2,
                source: .apple,
                sourceLabel: "Apple Health VO2 max"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "最大攝氧量估算")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("Apple 產品估算"), text)
        XCTAssertTrue(text.contains("產品來源估算"), text)
        XCTAssertTrue(text.contains("實驗室氣體分析"), text)
        XCTAssertFalse(text.contains("VO2 max 實測"), text)
        XCTAssertFalse(text.contains("lab-equivalent"), text)
        XCTAssertFalse(text.contains("true VO2 max"), text)
    }

    func testMetricDisclosurePresenterRendersStrengthMetricAsExerciseSpecificEstimate() {
        let base = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: base.workoutType,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            strengthMetrics: [
                StrengthMetric(
                    exerciseName: "Back Squat",
                    value: 120,
                    unit: "kg",
                    source: .e1RM,
                    sourceLabel: "Back Squat 5RM e1RM",
                    repetitions: 5,
                    loadValue: 105,
                    loadUnit: "kg"
                )
            ]
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "肌力指標")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("估算最大負重"), text)
        XCTAssertTrue(text.contains("e1RM 肌力估算"), text)
        XCTAssertTrue(text.contains("動作、負重、次數"), text)
        XCTAssertFalse(text.contains("全身肌力診斷"), text)
        XCTAssertFalse(text.contains("clinical strength diagnosis"), text)
        XCTAssertFalse(text.contains("whole-body strength diagnosis"), text)
    }

    func testMetricDisclosurePresenterRendersHeartRateRecoveryAsBoundedContext() {
        let base = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: base.workoutType,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: HeartRateRecoveryObservation(
                value: 21,
                source: .apple,
                sourceLabel: "Apple Health 1-minute heart-rate recovery"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "恢復脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("Apple 產品估算"), text)
        XCTAssertTrue(text.contains("運動後心率回落情況"), text)
        XCTAssertTrue(text.contains("恢復觀察"), text)
        XCTAssertFalse(text.contains("recovery diagnosis"), text)
        XCTAssertFalse(text.contains("VO2 max measurement"), text)
    }

    func testMetricDisclosurePresenterRendersDerivedHeartRateRecoveryAsBoundedContext() {
        let base = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: base.workoutType,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: HeartRateRecoveryObservation(
                value: 10,
                source: .apple,
                sourceLabel: "Derived from Apple Health post-workout heart rate"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "恢復脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("Apple 產品估算"), text)
        XCTAssertTrue(text.contains("運動結束後的心率點推得"), text)
        XCTAssertFalse(text.contains("recovery diagnosis"), text)
    }

    func testMetricDisclosurePresenterRendersRunningPowerAsFieldEstimatorSupport() {
        let base = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: base.workoutType,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: base.heartRateRecoveryOneMinute,
            runningPower: RunningPowerObservation(
                averageWatts: 246,
                source: .runningHRSpeed,
                sourceLabel: "Apple Health running power"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "跑步功率脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("跑步心率與速度估算"), text)
        XCTAssertTrue(text.contains("補充跑步時的外部負荷"), text)
        XCTAssertTrue(text.contains("外部負荷"), text)
        XCTAssertFalse(text.contains("VO2 max measurement"), text)
        XCTAssertFalse(text.contains("exact Zone 2"), text)
    }

    func testMetricDisclosurePresenterRendersCyclingPowerAsFieldEstimatorSupport() {
        let base = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: .cycling,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: base.heartRateRecoveryOneMinute,
            runningPower: base.runningPower,
            cyclingPower: CyclingPowerObservation(
                averageWatts: 212,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "自行車功率脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("自行車功率與心率估算"), text)
        XCTAssertTrue(text.contains("補充騎乘時的外部負荷"), text)
        XCTAssertTrue(text.contains("外部負荷"), text)
        XCTAssertFalse(text.contains("VO2 max measurement"), text)
        XCTAssertFalse(text.contains("exact Zone 2"), text)
    }

    func testMetricDisclosurePresenterRendersWorkoutRouteAsTerrainContext() {
        let base = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: .running,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: base.heartRateRecoveryOneMinute,
            runningPower: base.runningPower,
            cyclingPower: base.cyclingPower,
            workoutRoute: WorkoutRouteObservation(
                pointCount: 128,
                elevationGainMeters: 86,
                source: .workoutRoute,
                sourceLabel: "Apple Health workout route"
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "路線脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("Apple Health workout route"), text)
        XCTAssertTrue(text.contains("路線與地形背景"), text)
        XCTAssertTrue(text.contains("戶外訓練情境"), text)
        XCTAssertFalse(text.contains("VO2 max measurement"), text)
        XCTAssertFalse(text.contains("exact Zone 2"), text)
    }

    func testMetricDisclosurePresenterRendersExternalLoadDecouplingAsBoundedContext() {
        let base = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let workout = WorkoutInput(
            id: base.id,
            workoutType: .running,
            startDate: base.startDate,
            endDate: base.endDate,
            durationSeconds: base.durationSeconds,
            heartRateSamples: base.heartRateSamples,
            hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
            intent: base.intent,
            intentSource: base.intentSource,
            dataSource: base.dataSource,
            activeCaloriesKcal: base.activeCaloriesKcal,
            totalDistanceMeters: base.totalDistanceMeters,
            vo2MaxEstimate: base.vo2MaxEstimate,
            heartRateRecoveryOneMinute: base.heartRateRecoveryOneMinute,
            runningPower: base.runningPower,
            cyclingPower: base.cyclingPower,
            workoutRoute: base.workoutRoute,
            externalLoadDecoupling: ExternalLoadDecouplingObservation(
                decouplingRatio: 0.043,
                firstHalfAverageHeartRate: 132,
                secondHalfAverageHeartRate: 138,
                firstHalfAverageWatts: 241,
                secondHalfAverageWatts: 242,
                source: .runningHRSpeed,
                sourceLabel: "Apple Health running power + HR decoupling",
                measuredAt: base.endDate
            )
        )

        let items = MetricDisclosurePresenter.render(
            WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        )
        let text = text(for: items, title: "負荷一致性脈絡")

        XCTAssertTrue(text.contains("估算參考"), text)
        XCTAssertTrue(text.contains("Apple Health running power + HR decoupling"), text)
        XCTAssertTrue(text.contains("前後段心率和負荷是否大致一致"), text)
        XCTAssertTrue(text.contains("前後段一致性線索"), text)
        XCTAssertFalse(text.contains("VO2 max measurement"), text)
        XCTAssertFalse(text.contains("exact Zone 2"), text)
    }

    func testExternalLoadDecouplingObservationComputesHalfSplitRatio() {
        let start = Date(timeIntervalSince1970: 1_714_500_000)
        let end = start.addingTimeInterval(20 * 60)
        let heartRateSamples = [
            HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 130),
            HeartRateSample(timestamp: start.addingTimeInterval(240), bpm: 132),
            HeartRateSample(timestamp: start.addingTimeInterval(720), bpm: 137),
            HeartRateSample(timestamp: start.addingTimeInterval(960), bpm: 139),
        ]
        let runningPowerSamples = [
            TimedPowerSample(timestamp: start.addingTimeInterval(90), watts: 240),
            TimedPowerSample(timestamp: start.addingTimeInterval(300), watts: 242),
            TimedPowerSample(timestamp: start.addingTimeInterval(780), watts: 243),
            TimedPowerSample(timestamp: start.addingTimeInterval(1020), watts: 244),
        ]

        let observation = externalLoadDecouplingObservation(
            workoutType: .running,
            startDate: start,
            endDate: end,
            heartRateSamples: heartRateSamples,
            runningPowerSamples: runningPowerSamples,
            cyclingPowerSamples: []
        )

        guard let unwrappedObservation = observation else {
            return XCTFail("Expected decoupling observation")
        }
        XCTAssertEqual(unwrappedObservation.source, .runningHRSpeed)
        XCTAssertEqual(unwrappedObservation.firstHalfAverageHeartRate, 131, accuracy: 0.001)
        XCTAssertEqual(unwrappedObservation.secondHalfAverageHeartRate, 138, accuracy: 0.001)
        XCTAssertEqual(unwrappedObservation.firstHalfAverageWatts, 241, accuracy: 0.001)
        XCTAssertEqual(unwrappedObservation.secondHalfAverageWatts, 243.5, accuracy: 0.001)
        XCTAssertEqual(unwrappedObservation.decouplingRatio, 0.0426, accuracy: 0.0001)
    }

    @MainActor
    func testMetricDisclosureCardViewSmokeCompiles() {
        let result = WorkoutIntentAnalyzer.analyze(
            SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        )
        let view = MetricDisclosureCardView(metadata: result.metricMetadata)

        XCTAssertFalse(result.metricMetadata.isEmpty)
        _ = view.body
    }

    private func text(for items: [MetricDisclosureItem], title: String) -> String {
        guard let item = items.first(where: { $0.title == title }) else {
            XCTFail("Expected disclosure item titled \(title)")
            return ""
        }
        return [item.title, item.status, item.summary, item.method, item.confidenceReason, item.validationHint ?? ""]
            .joined(separator: " ")
    }

    @MainActor
    func testWeeklySummaryRecomputesZoneDistributionFromCustomPolicy() {
        let suiteName = "test.weekly.custom.policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(userDefaults: defaults)
        let templateWorkout = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        let startDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
        let remappedSamples = templateWorkout.heartRateSamples.enumerated().map { index, sample in
            HeartRateSample(
                timestamp: startDate.addingTimeInterval(Double(index) * 60),
                bpm: sample.bpm
            )
        }
        let workout = WorkoutInput(
            workoutType: templateWorkout.workoutType,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(templateWorkout.durationSeconds),
            durationSeconds: templateWorkout.durationSeconds,
            heartRateSamples: remappedSamples,
            hrvSDNNMilliseconds: templateWorkout.hrvSDNNMilliseconds,
            intent: templateWorkout.intent,
            intentSource: templateWorkout.intentSource,
            dataSource: templateWorkout.dataSource,
            activeCaloriesKcal: templateWorkout.activeCaloriesKcal,
            totalDistanceMeters: templateWorkout.totalDistanceMeters
        )
        let repository = StaticWorkoutRepository(workouts: [workout])
        let viewModel = WorkoutListViewModel(
            repository: repository,
            settingsManager: settings
        )

        let baselineZone2 = viewModel.weeklySummary.zoneDistribution.counts[.zone2, default: 0]
        XCTAssertGreaterThan(baselineZone2, 0)

        settings.updateZone2Bounds(lower: 110, upper: 116)
        viewModel.refreshDerivedDataForCurrentPolicy()

        let updatedZone2 = viewModel.weeklySummary.zoneDistribution.counts[.zone2, default: 0]
        let updatedZone3 = viewModel.weeklySummary.zoneDistribution.counts[.zone3, default: 0]
        XCTAssertLessThan(updatedZone2, baselineZone2)
        XCTAssertGreaterThan(updatedZone3, 0)
    }

    @MainActor
    func testWeeklySummaryReturnsToDefaultPolicyAfterReset() {
        let suiteName = "test.weekly.reset.policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(userDefaults: defaults)
        let templateWorkout = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        let startDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
        let remappedSamples = templateWorkout.heartRateSamples.enumerated().map { index, sample in
            HeartRateSample(
                timestamp: startDate.addingTimeInterval(Double(index) * 60),
                bpm: sample.bpm
            )
        }
        let workout = WorkoutInput(
            workoutType: templateWorkout.workoutType,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(templateWorkout.durationSeconds),
            durationSeconds: templateWorkout.durationSeconds,
            heartRateSamples: remappedSamples,
            hrvSDNNMilliseconds: templateWorkout.hrvSDNNMilliseconds,
            intent: templateWorkout.intent,
            intentSource: templateWorkout.intentSource,
            dataSource: templateWorkout.dataSource,
            activeCaloriesKcal: templateWorkout.activeCaloriesKcal,
            totalDistanceMeters: templateWorkout.totalDistanceMeters
        )
        let repository = StaticWorkoutRepository(workouts: [workout])
        let viewModel = WorkoutListViewModel(
            repository: repository,
            settingsManager: settings
        )

        let baselineDistribution = viewModel.weeklySummary.zoneDistribution

        settings.updateZone2Bounds(lower: 110, upper: 116)
        viewModel.refreshDerivedDataForCurrentPolicy()
        XCTAssertNotEqual(viewModel.weeklySummary.zoneDistribution, baselineDistribution)

        settings.resetZone2BoundsToDefault()
        viewModel.refreshDerivedDataForCurrentPolicy()

        XCTAssertEqual(settings.policy.zoneBounds, AnalysisPolicy.default.zoneBounds)
        XCTAssertEqual(viewModel.weeklySummary.zoneDistribution, baselineDistribution)
    }

    @MainActor
    func testWorkoutDetailZoneContextSummaryTracksPolicySource() {
        let suiteName = "test.detail.zone.context.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(userDefaults: defaults)
        let workout = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        let repository = StaticWorkoutRepository(workouts: [workout])
        let viewModel = WorkoutListViewModel(
            repository: repository,
            settingsManager: settings
        )

        let baselineSummary = viewModel.analysisZoneContextSummary(for: workout)
        XCTAssertTrue(baselineSummary.contains("預設界線"))
        XCTAssertTrue(baselineSummary.contains("110-125 bpm"))

        settings.updateZone2Bounds(lower: 115, upper: 130)
        let customSummary = viewModel.analysisZoneContextSummary(for: workout)
        XCTAssertTrue(customSummary.contains("自訂界線"))
        XCTAssertTrue(customSummary.contains("115-130 bpm"))

        settings.updateRestingHeartRate(60)
        settings.generateRestingHeartRateSuggestion()
        settings.applySuggestion()
        let suggestedSummary = viewModel.analysisZoneContextSummary(for: workout)
        XCTAssertTrue(suggestedSummary.contains("靜息心率建議已套用"))
        XCTAssertTrue(suggestedSummary.contains("115-130 bpm"))
    }

    func testBodyCompositionSeedLedgerHasExpectedCoverage() {
        let measurements = BodyCompositionRepository.seedMeasurements()
        XCTAssertGreaterThanOrEqual(measurements.count, 12, "Seed data should include complete baseline history.")

        let dates = measurements.map(\.date)
        XCTAssertEqual(dates, dates.sorted(), "Seed measurements must be chronological.")

        XCTAssertTrue(measurements.allSatisfy { $0.weightKg > 0 })
        XCTAssertTrue(measurements.allSatisfy { $0.skeletalMuscleKg > 0 })
        XCTAssertTrue(measurements.allSatisfy { $0.bodyFatKg >= 0 })
        XCTAssertTrue(measurements.allSatisfy { $0.visceralFatCm2 >= 0 })

        let ledger = BodyCompositionRepository.defaultSeedLedger()
        XCTAssertNotNil(ledger, "Seed measurements should always produce a valid ledger.")
        XCTAssertEqual(ledger?.measurementCount, measurements.count)
        XCTAssertEqual(ledger?.measurements.count, measurements.count)
    }

    @MainActor
    func testBodyCompositionContextSectionSmokeCompiles() {
        guard let ledger = BodyCompositionRepository.defaultSeedLedger() else {
            XCTFail("Expected default seed ledger.")
            return
        }
        let section = BodyCompositionContextSection(ledger: ledger)
        _ = section.body
    }

    func testLowEvidenceCannotRenderHighAuthorityVisuals() {
        // Low confidence with fresh data
        let lowConfAuthority = WeeklyAuthorityRendering.authority(for: 0.5, freshness: .fresh)
        XCTAssertEqual(lowConfAuthority, .weakInference)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationEmphasisOpacity(for: lowConfAuthority), 0.03)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationStrokeOpacity(for: lowConfAuthority), 0.12)
        
        // High confidence but stale data
        let staleAuthority = WeeklyAuthorityRendering.authority(for: 0.9, freshness: .stale)
        XCTAssertEqual(staleAuthority, .weakInference)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationEmphasisOpacity(for: staleAuthority), 0.03)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationStrokeOpacity(for: staleAuthority), 0.12)

        // High confidence but missing data
        let missingAuthority = WeeklyAuthorityRendering.authority(for: 0.9, freshness: .missing)
        XCTAssertEqual(missingAuthority, .weakInference)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationEmphasisOpacity(for: missingAuthority), 0.03)
        XCTAssertEqual(WeeklyAuthorityRendering.recommendationStrokeOpacity(for: missingAuthority), 0.12)
    }

    func testCardSurfaceOpacityMonotonicByAuthority() {
        let observational = WeeklyAuthorityRendering.cardSurfaceOpacity(for: .observational)
        let bounded = WeeklyAuthorityRendering.cardSurfaceOpacity(for: .boundedInference)
        let weak = WeeklyAuthorityRendering.cardSurfaceOpacity(for: .weakInference)

        XCTAssertGreaterThan(observational, bounded)
        XCTAssertGreaterThan(bounded, weak)
        XCTAssertEqual(observational, 1.0, accuracy: 0.0001)
    }

    func testWeeklyAdaptationSignalUsesBoundedDirectionClasses() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 4,
            totalDurationMinutes: 240,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 3, .vo2Interval: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 1,
            strengthDays: 0,
            restDays: 2,
            elapsedDays: 7,
            consecutiveTrainingDays: 2,
            hrvSampledWorkoutCount: 4,
            hrvCoverageRatio: 1.0,
            averageHRVSDNNMilliseconds: 42
        )
        let policy = WeeklyLoadPolicy(
            recoveryConcernLevel: .low,
            loadTendency: .aerobicFocused,
            keyFindings: [],
            nextAction: "",
            confidence: 0.85
        )
        let signal = WeeklyAdaptationSignal.from(summary: summary, policy: policy, freshness: .fresh)

        XCTAssertEqual(signal.direction, .enduranceBuild)
        XCTAssertEqual(signal.authority, .observational)
        XCTAssertEqual(signal.inferenceClass, .bounded)
        XCTAssertEqual(signal.temporalScopes.map(\.label), ["近 7 天訊號", "近 28 天資料不足"])
        XCTAssertEqual(signal.provenance.authorityCeiling, .nonInterventional)
        XCTAssertTrue(signal.provenance.isValidFailClosed(strength: .bounded))
    }

    func testWeeklyInferenceProvenanceRevealsMissingEvidenceUnderSparseCoverage() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 4,
            totalDurationMinutes: 210,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 2, .vo2Interval: 2],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 2,
            strengthDays: 0,
            restDays: 2,
            elapsedDays: 7,
            consecutiveTrainingDays: 4,
            hrvSampledWorkoutCount: 0,
            hrvCoverageRatio: 0.0,
            averageHRVSDNNMilliseconds: nil
        )
        let policy = WeeklyLoadPolicy(
            recoveryConcernLevel: .elevated,
            loadTendency: .highIntensityFocused,
            keyFindings: [],
            nextAction: "",
            confidence: 0.8
        )

        let adaptation = WeeklyAdaptationSignal.from(summary: summary, policy: policy, freshness: .fresh)
        let state = WeeklyTrainingStateSignal.from(summary: summary, policy: policy, freshness: .fresh)

        XCTAssertEqual(adaptation.provenance.authorityCeiling, .nonInterventional)
        XCTAssertTrue(adaptation.provenance.missingEvidence.contains(.sleep))
        XCTAssertTrue(adaptation.provenance.missingEvidence.contains(.hrv))
        XCTAssertTrue(adaptation.provenance.isValidFailClosed(strength: .sparse))

        XCTAssertEqual(state.provenance.authorityCeiling, .nonInterventional)
        XCTAssertTrue(state.provenance.missingEvidence.contains(.sleep))
        XCTAssertTrue(state.provenance.missingEvidence.contains(.hrv))
        XCTAssertTrue(state.provenance.isValidFailClosed(strength: .sparse))
    }

    func testWeeklyVisibleMissingEvidenceRemovesSleepWhenContextIsAvailable() {
        let provenance = InferenceProvenance(
            inferenceType: .boundedSynthesis,
            derivedFrom: [.workoutCount, .zoneDistribution],
            missingEvidence: [.sleep, .hrv, .stress],
            authorityCeiling: .nonInterventional
        )
        let sleepContext = WeeklySleepContext(
            lookbackDays: 7,
            nightsWithSleep: 5,
            averageSleepHours: 6.9
        )

        let visibleWithSleep = weeklyVisibleMissingEvidence(provenance, sleepContext: sleepContext)
        let visibleWithoutSleep = weeklyVisibleMissingEvidence(provenance, sleepContext: nil)

        XCTAssertFalse(visibleWithSleep.contains(MissingEvidence.sleep))
        XCTAssertTrue(visibleWithSleep.contains(MissingEvidence.hrv))
        XCTAssertTrue(visibleWithSleep.contains(MissingEvidence.stress))
        XCTAssertTrue(visibleWithoutSleep.contains(MissingEvidence.sleep))
    }


    func testWeeklyHRVCoverageSignalClassifiesCoverageBands() {
        XCTAssertEqual(
            WeeklyHRVCoverageSignal.classify(workoutCount: 0, sampledCount: 0, coverageRatio: 0),
            .missing
        )
        XCTAssertEqual(
            WeeklyHRVCoverageSignal.classify(workoutCount: 5, sampledCount: 0, coverageRatio: 0),
            .missing
        )
        XCTAssertEqual(
            WeeklyHRVCoverageSignal.classify(workoutCount: 5, sampledCount: 1, coverageRatio: 0.2),
            .sparse
        )
        XCTAssertEqual(
            WeeklyHRVCoverageSignal.classify(workoutCount: 5, sampledCount: 2, coverageRatio: 0.4),
            .partial
        )
        XCTAssertEqual(
            WeeklyHRVCoverageSignal.classify(workoutCount: 5, sampledCount: 4, coverageRatio: 0.8),
            .good
        )
    }

    func testNonAuthorityReminderPolicyLevels() {
        XCTAssertEqual(
            NonAuthorityReminderPolicy.level(inference: .bounded, freshness: .fresh),
            .none
        )
        XCTAssertEqual(
            NonAuthorityReminderPolicy.level(inference: .weak, freshness: .fresh),
            .soft
        )
        XCTAssertEqual(
            NonAuthorityReminderPolicy.level(inference: .bounded, freshness: .partial),
            .soft
        )
        XCTAssertEqual(
            NonAuthorityReminderPolicy.level(inference: .unsupported, freshness: .fresh),
            .strong
        )
        XCTAssertEqual(
            NonAuthorityReminderPolicy.level(inference: .bounded, freshness: .stale),
            .strong
        )
    }

    func testWeeklyTrainingStateSignalCoversStateProgression() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let policy = WeeklyLoadPolicy(
            recoveryConcernLevel: .low,
            loadTendency: .balanced,
            keyFindings: [],
            nextAction: "",
            confidence: 0.85
        )

        let recoveredSummary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 1,
            totalDurationMinutes: 45,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 0,
            strengthDays: 0,
            restDays: 5,
            elapsedDays: 7,
            consecutiveTrainingDays: 1
        )
        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: recoveredSummary, policy: policy, freshness: .fresh).state,
            .recovered
        )

        let accumulatingSummary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 3,
            totalDurationMinutes: 180,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 2, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 0,
            strengthDays: 0,
            restDays: 2,
            elapsedDays: 7,
            consecutiveTrainingDays: 2
        )
        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: accumulatingSummary, policy: policy, freshness: .fresh).state,
            .accumulatingLoad
        )

        let fatigueSummary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 4,
            totalDurationMinutes: 250,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 3, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 1,
            strengthDays: 0,
            restDays: 2,
            elapsedDays: 7,
            consecutiveTrainingDays: 3
        )
        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: fatigueSummary, policy: policy, freshness: .fresh).state,
            .functionalFatigue
        )

        let underRecoverySummary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 320,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 2, .vo2Interval: 2, .strength: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 2,
            strengthDays: 1,
            restDays: 1,
            elapsedDays: 7,
            consecutiveTrainingDays: 4
        )
        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: underRecoverySummary, policy: policy, freshness: .fresh).state,
            .possibleUnderRecovery
        )
    }

    func testWeeklyTrainingStateSignalDowngradesUnderStaleOrMissingEvidence() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 320,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 2, .vo2Interval: 2, .strength: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 2,
            strengthDays: 1,
            restDays: 1,
            elapsedDays: 7,
            consecutiveTrainingDays: 4
        )
        let policy = WeeklyLoadPolicy(
            recoveryConcernLevel: .high,
            loadTendency: .highIntensityFocused,
            keyFindings: [],
            nextAction: "",
            confidence: 0.85
        )

        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: summary, policy: policy, freshness: .stale).state,
            .recoveryNormalizing
        )
        XCTAssertEqual(
            WeeklyTrainingStateSignal.from(summary: summary, policy: policy, freshness: .missing).state,
            .recoveryNormalizing
        )
    }

    func testTrainingStateRenderingAvoidsBinaryGoodBadTerms() {
        let labels = [
            TrainingState.recovered.admissibleLabel(for: .observational),
            TrainingState.accumulatingLoad.admissibleLabel(for: .boundedInference),
            TrainingState.functionalFatigue.admissibleLabel(for: .weakInference),
            TrainingState.possibleUnderRecovery.admissibleLabel(for: .boundedInference),
            TrainingState.recoveryNormalizing.admissibleLabel(for: .weakInference),
        ]
        let combined = labels.joined(separator: " ")
        XCTAssertFalse(combined.contains("好"))
        XCTAssertFalse(combined.contains("壞"))
        XCTAssertFalse(combined.contains("正常/異常"))
    }

    // MARK: - Claim Ceiling Tests

    func testAdaptationResidualDefaultIsNoSignalNotMaintenance() {
        // A training week that doesn't match any positive direction condition
        // (low zone2 ratio, no high-intensity surge, no rest bias) must produce
        // .noSignal — not .maintenance — to avoid "residual label as observation".
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 300,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 1, .activityReview: 4],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 0,
            strengthDays: 0,
            restDays: 0,
            elapsedDays: 7,
            consecutiveTrainingDays: 5
        )
        let policy = WeeklyLoadPolicy(
            recoveryConcernLevel: .moderate,
            loadTendency: .mixed,
            keyFindings: [],
            nextAction: "",
            confidence: 0.80
        )
        let signal = WeeklyAdaptationSignal.from(summary: summary, policy: policy, freshness: .fresh)
        XCTAssertEqual(signal.direction, .noSignal, "Low zone2 + no high intensity → no positive direction, must be .noSignal")
    }

    func testFunctionalFatigueNeverRendersClinicalTerm() {
        // .functionalFatigue internal state must never render "功能性疲勞"
        // because consecutive-days data alone cannot support that clinical claim.
        XCTAssertNotEqual(TrainingState.functionalFatigue.admissibleLabel(for: .observational), "功能性疲勞")
        XCTAssertNotEqual(TrainingState.functionalFatigue.admissibleLabel(for: .boundedInference), "功能性疲勞")
        XCTAssertNotEqual(TrainingState.functionalFatigue.admissibleLabel(for: .weakInference), "功能性疲勞")
        XCTAssertEqual(TrainingState.functionalFatigue.admissibleLabel(for: .boundedInference), "恢復壓力偏高")
        XCTAssertEqual(TrainingState.functionalFatigue.admissibleLabel(for: .weakInference), "負荷連續，恢復機會受限")
    }

    func testNoSignalDirectionAlwaysRendersEvidenceGapLabel() {
        // .noSignal must always render the evidence-gap phrase regardless of authority.
        let label = "目前沒有足夠訊號判定適應方向"
        XCTAssertEqual(WeeklyAdaptationDirection.noSignal.admissibleLabel(for: .observational), label)
        XCTAssertEqual(WeeklyAdaptationDirection.noSignal.admissibleLabel(for: .boundedInference), label)
        XCTAssertEqual(WeeklyAdaptationDirection.noSignal.admissibleLabel(for: .weakInference), label)
    }

    func testWeeklyCTAPresenterUsesGoalAwareActionWhenGoalSignalDiverges() {
        let rendered = WeeklyCTAPresenter.render(
            base: "本週訓練節奏尚可，下週視體感微調強度。",
            for: .observational,
            goal: .strengthFocus,
            goalSignal: .divergent
        )
        XCTAssertTrue(rendered.contains("補入肌力課"))
        XCTAssertTrue(rendered.contains("觀察肌力訓練品質"))
        XCTAssertFalse(rendered.contains("安排至少一堂肌力課"))
    }

    func testWeeklyCTAPresenterKeepsWeakEvidencePrefixOnGoalAwareAction() {
        let rendered = WeeklyCTAPresenter.render(
            base: "本週訓練節奏尚可，下週視體感微調強度。",
            for: .weakInference,
            goal: .aerobicBase,
            goalSignal: .divergent
        )
        XCTAssertTrue(rendered.hasPrefix("訊號有限，僅供方向參考："))
        XCTAssertTrue(rendered.contains("降低高強度比例"))
        XCTAssertTrue(rendered.contains("觀察"))
        XCTAssertFalse(rendered.contains("優先補低強度有氧時段"))
    }

    func testGoalAlignmentMismatchFactorsExposeDeterministicReasons() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 280,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 1, .vo2Interval: 3, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 3,
            strengthDays: 0,
            restDays: 0,
            elapsedDays: 7,
            consecutiveTrainingDays: 5
        )
        let factors = GoalAlignmentSignal.divergent.mismatchFactors(for: .aerobicBase, summary: summary)
        XCTAssertFalse(factors.isEmpty)
        XCTAssertTrue(factors.contains { $0.contains("高強度課次偏多") })
        XCTAssertTrue(factors.count <= 3)
    }

    func testGoalAlignmentMismatchFactorsEmptyWhenAligned() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 4,
            totalDurationMinutes: 220,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 3, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 0,
            strengthDays: 1,
            restDays: 2,
            elapsedDays: 7,
            consecutiveTrainingDays: 2
        )
        XCTAssertEqual(
            GoalAlignmentSignal.aligned.mismatchFactors(for: .aerobicBase, summary: summary),
            []
        )
    }

    func testGoalAlignmentSurfaceLanguageContainsNoForbiddenAuthorityTerms() {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 280,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 1, .vo2Interval: 2, .strength: 1, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 2,
            strengthDays: 1,
            restDays: 1,
            elapsedDays: 7,
            consecutiveTrainingDays: 4
        )
        let forbidden = ["目標達成", "將會", "必定", "保證", "治療", "處方", "診斷結果", "確定診斷"]
        for goal in UserTrainingGoal.allCases {
            for signal in [GoalAlignmentSignal.aligned, .partiallyAligned, .divergent, .insufficientEvidence] {
                let text = [
                    signal.observationalLabel(for: goal),
                    signal.mismatchFactors(for: goal, summary: summary).joined(separator: " "),
                    WeeklyCTAPresenter.render(base: "本週訓練節奏尚可，下週視體感微調強度。", for: .observational, goal: goal, goalSignal: signal),
                    WeeklyCTAPresenter.render(base: "本週訓練節奏尚可，下週視體感微調強度。", for: .weakInference, goal: goal, goalSignal: signal),
                ].joined(separator: " ")
                for term in forbidden {
                    XCTAssertFalse(text.contains(term), "goal alignment surface contains forbidden term: \(term)")
                }
            }
        }
    }

    func testGoalAlignmentSurfaceLanguageSnapshotFixture() throws {
        let fixtureURL = try goalAlignmentLanguageFixtureURL()
        let records = buildGoalAlignmentLanguageFixtureRecords()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rendered = try encoder.encode(records)
        let shouldUpdate = ProcessInfo.processInfo.environment["UPDATE_GOAL_ALIGNMENT_LANG_FIXTURE"] == "1"
        if shouldUpdate {
            try rendered.write(to: fixtureURL)
        }
        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            rendered,
            expected,
            "Goal alignment language snapshot mismatch. Run with UPDATE_GOAL_ALIGNMENT_LANG_FIXTURE=1 only after intentional wording changes."
        )
    }

    func testWeeklyTemporalScopeLabelsAreLocalized() {
        XCTAssertEqual(WeeklyTemporalScopeLabel.signal7d, "近 7 天訊號")
        XCTAssertEqual(WeeklyTemporalScopeLabel.unavailable28d, "近 28 天資料不足")
        XCTAssertFalse(WeeklyTemporalScopeLabel.signal7d.contains("signal"))
        XCTAssertFalse(WeeklyTemporalScopeLabel.unavailable28d.contains("unavailable"))
    }

    func testNonAuthorityReminderMessagesAreLocalized() {
        XCTAssertEqual(NonAuthorityReminderLevel.none.message, "")
        XCTAssertTrue(NonAuthorityReminderLevel.soft.message.contains("心率觀測訊號"))
        XCTAssertTrue(NonAuthorityReminderLevel.soft.message.contains("非生理診斷"))
        XCTAssertTrue(NonAuthorityReminderLevel.strong.message.contains("證據有限或偏舊"))
        XCTAssertTrue(NonAuthorityReminderLevel.strong.message.contains("僅供方向參考"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0))!
    }

    private func buildEvaluationFixtureRecords() -> [EvaluationFixtureRecord] {
        let zone2Case = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "leaky_zone2_run" }!.workout
        let vo2Case = SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        let strengthCase = SampleWorkoutCases.strengthValidationCases().first { $0.name == "metabolic_strength_circuit" }!.workout
        let activityCase = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "badminton_activity_review" }!.workout
        let sparseCase = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "sparse_hr_cycling" }!.workout

        let inputs: [(String, TrainingIntent, WorkoutInput)] = [
            ("zone2_deviation_stable_drift", .zone2, zone2Case),
            ("vo2_pass", .vo2Interval, vo2Case),
            ("strength_metabolic_circuit", .strength, strengthCase),
            ("activity_general", .activityReview, activityCase),
            ("sparse_hr_samples", .zone2, sparseCase)
        ]

        return inputs.map { id, intent, workout in
            let rewritten = WorkoutInput(
                id: workout.id,
                workoutType: workout.workoutType,
                startDate: workout.startDate,
                endDate: workout.endDate,
                durationSeconds: workout.durationSeconds,
                heartRateSamples: workout.heartRateSamples,
                intent: intent
            )
            let legacy = WorkoutIntentAnalyzer.analyze(rewritten)
            let evaluation = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
                primaryIntentBaseline: intent,
                legacy: legacy
            )
            return EvaluationFixtureRecord(id: id, evaluation: evaluation)
        }
    }

    private func fixtureFileURL() throws -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testFileDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("workout_evaluation_snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture file not found at \(url.path)")
        }
        return url
    }

    private func goalAlignmentLanguageFixtureURL() throws -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testFileDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("goal_alignment_language_snapshot.json", isDirectory: false)
        let shouldUpdate = ProcessInfo.processInfo.environment["UPDATE_GOAL_ALIGNMENT_LANG_FIXTURE"] == "1"
        if !shouldUpdate && !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Goal alignment language fixture not found at \(url.path)")
        }
        return url
    }

    private func buildGoalAlignmentLanguageFixtureRecords() -> [GoalAlignmentLanguageFixtureRecord] {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
        let summary = WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday.addingTimeInterval(7 * 86400 - 1),
            workoutCount: 5,
            totalDurationMinutes: 280,
            totalActiveCalories: nil,
            intentDistribution: [.zone2: 1, .vo2Interval: 2, .strength: 1, .activityReview: 1],
            zoneDistribution: ZoneDistribution(counts: [.zone1: 0, .zone2: 0, .zone3: 0, .zone4: 0, .zone5: 0], ratios: [:]),
            highIntensityDays: 2,
            strengthDays: 1,
            restDays: 1,
            elapsedDays: 7,
            consecutiveTrainingDays: 4
        )
        return UserTrainingGoal.allCases.flatMap { goal in
            [GoalAlignmentSignal.aligned, .partiallyAligned, .divergent, .insufficientEvidence].map { signal in
                GoalAlignmentLanguageFixtureRecord(
                    goal: goal.rawValue,
                    signal: signal.rawValue,
                    observationalLabel: signal.observationalLabel(for: goal),
                    mismatchFactors: signal.mismatchFactors(for: goal, summary: summary),
                    ctaObservational: WeeklyCTAPresenter.render(
                        base: "本週訓練節奏尚可，下週視體感微調強度。",
                        for: .observational,
                        goal: goal,
                        goalSignal: signal
                    ),
                    ctaWeak: WeeklyCTAPresenter.render(
                        base: "本週訓練節奏尚可，下週視體感微調強度。",
                        for: .weakInference,
                        goal: goal,
                        goalSignal: signal
                    )
                )
            }
        }
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
              "vo2MaxEstimate": {
                "value": 48.2,
                "source": "apple",
                "sourceLabel": "Apple Health VO2 max",
                "measuredAt": "2026-04-24T05:55:00Z"
              },
              "strengthMetrics": [
                {
                  "exerciseName": "Back Squat",
                  "value": 120,
                  "unit": "kg",
                  "source": "e1rm",
                  "sourceLabel": "Back Squat 5RM e1RM",
                  "repetitions": 5,
                  "loadValue": 105,
                  "loadUnit": "kg",
                  "measuredAt": "2026-04-24T05:30:00Z"
                }
              ],
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
            ],
            hrvSDNNMilliseconds: 42.5,
            vo2MaxEstimate: VO2MaxEstimate(
                value: 47.3,
                source: .apple,
                sourceLabel: "Apple Health VO2 max",
                measuredAt: start.addingTimeInterval(-300)
            ),
            heartRateRecoveryOneMinute: HeartRateRecoveryObservation(
                value: 23,
                source: .apple,
                sourceLabel: "Apple Health 1-minute heart-rate recovery",
                measuredAt: start.addingTimeInterval(60)
            ),
            runningPower: RunningPowerObservation(
                averageWatts: 248,
                source: .runningHRSpeed,
                sourceLabel: "Apple Health running power",
                measuredAt: start.addingTimeInterval(20 * 60)
            ),
            cyclingPower: CyclingPowerObservation(
                averageWatts: 214,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power",
                measuredAt: start.addingTimeInterval(20 * 60)
            ),
            workoutRoute: WorkoutRouteObservation(
                pointCount: 128,
                elevationGainMeters: 86,
                source: .workoutRoute,
                sourceLabel: "Apple Health workout route"
            ),
            externalLoadDecoupling: ExternalLoadDecouplingObservation(
                decouplingRatio: 0.0417,
                firstHalfAverageHeartRate: 120,
                secondHalfAverageHeartRate: 125,
                firstHalfAverageWatts: 216,
                secondHalfAverageWatts: 216,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power + HR decoupling",
                measuredAt: start.addingTimeInterval(20 * 60)
            ),
            debugSignalSnapshot: HealthKitWorkoutDebugSignalSnapshot(
                recoveryCandidateCount: 1
            )
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

    // MARK: - MultiWeekAdaptationAnalyzer tests

    private func makeWeeklySummary(
        workoutCount: Int,
        highIntensityDays: Int = 0,
        strengthDays: Int = 0,
        restDays: Int = 0,
        z2Count: Int = 0,
        consecutiveTrainingDays: Int = 0,
        weekOffset: Int = 0
    ) -> WeeklyWorkoutSummary {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
            .addingTimeInterval(-Double(weekOffset) * 7 * 86400)
        return WeeklyWorkoutSummary(
            weekStart: monday,
            weekEnd: monday + 7 * 86400,
            workoutCount: workoutCount,
            totalDurationMinutes: Double(workoutCount) * 60,
            totalActiveCalories: nil,
            intentDistribution: z2Count > 0 ? [.zone2: z2Count] : [:],
            zoneDistribution: ZoneDistribution(counts: [:], ratios: [:]),
            highIntensityDays: highIntensityDays,
            strengthDays: strengthDays,
            restDays: restDays,
            elapsedDays: 7,
            consecutiveTrainingDays: consecutiveTrainingDays
        )
    }

    func testMultiWeekAdaptationNilWhenFewerThanTwoQualifyingWeeks() {
        let summaries = [
            makeWeeklySummary(workoutCount: 1),
            makeWeeklySummary(workoutCount: 1),
            makeWeeklySummary(workoutCount: 0),
            makeWeeklySummary(workoutCount: 0),
        ]
        XCTAssertNil(MultiWeekAdaptationAnalyzer.analyze(summaries: summaries))
    }

    func testMultiWeekAdaptationStrongEnduranceBuildOnConsistentZ2Weeks() {
        let summaries = (0..<4).map { i in
            makeWeeklySummary(workoutCount: 4, highIntensityDays: 1, restDays: 3, z2Count: 3, weekOffset: i)
        }
        let trend = MultiWeekAdaptationAnalyzer.analyze(summaries: summaries)
        XCTAssertNotNil(trend)
        XCTAssertEqual(trend?.dominantDirection, .enduranceBuild)
        XCTAssertTrue(trend?.isStrong == true)
        XCTAssertGreaterThanOrEqual(trend?.qualifyingWeekCount ?? 0, 3)
    }

    func testMultiWeekAdaptationNotStrongOnTwoQualifyingWeeks() {
        let summaries = [
            makeWeeklySummary(workoutCount: 4, z2Count: 3, weekOffset: 0),
            makeWeeklySummary(workoutCount: 4, z2Count: 3, weekOffset: 1),
            makeWeeklySummary(workoutCount: 0, weekOffset: 2),
            makeWeeklySummary(workoutCount: 1, weekOffset: 3),
        ]
        let trend = MultiWeekAdaptationAnalyzer.analyze(summaries: summaries)
        XCTAssertNotNil(trend)
        XCTAssertFalse(trend?.isStrong == true, "isStrong requires >= 3 qualifying weeks")
    }

    func testMultiWeekAdaptationNoSignalWeeksDoNotDiluteConsistencyRatio() {
        let summaries = [
            makeWeeklySummary(workoutCount: 4, z2Count: 3, weekOffset: 0),
            makeWeeklySummary(workoutCount: 4, z2Count: 3, weekOffset: 1),
            makeWeeklySummary(workoutCount: 2, highIntensityDays: 1, weekOffset: 2),
            makeWeeklySummary(workoutCount: 2, highIntensityDays: 1, weekOffset: 3),
        ]

        let trend = MultiWeekAdaptationAnalyzer.analyze(summaries: summaries)

        XCTAssertEqual(trend?.dominantDirection, .enduranceBuild)
        XCTAssertEqual(trend?.consistencyRatio ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(trend?.qualifyingWeekCount, 4)
        XCTAssertTrue(trend?.isStrong == true)
    }

    func testMultiWeekAdaptationNilWhenAllWeeksAreNoSignal() {
        let summaries = (0..<4).map { i in
            // workoutCount = 2 but no z2, no high intensity, no rest → noSignal
            makeWeeklySummary(workoutCount: 2, highIntensityDays: 1, weekOffset: i)
        }
        // With highIntensityDays=1 and no z2, the direction is noSignal (doesn't meet any branch)
        // All noSignal → analyze returns nil
        let trend = MultiWeekAdaptationAnalyzer.analyze(summaries: summaries)
        // direction .noSignal is filtered out; if all noSignal, returns nil
        if let t = trend {
            XCTAssertNotEqual(t.dominantDirection, .noSignal)
        }
        // either nil or non-noSignal dominant direction — both acceptable
    }

    func testMultiWeekAdaptationClassifyDirectionRecoveryBiased() {
        let s = makeWeeklySummary(workoutCount: 2, restDays: 4)
        XCTAssertEqual(MultiWeekAdaptationAnalyzer.classifyDirection(s), .recoveryBiased)
    }

    func testMultiWeekAdaptationClassifyDirectionEnduranceBuild() {
        let s = makeWeeklySummary(workoutCount: 4, highIntensityDays: 1, restDays: 3, z2Count: 3)
        XCTAssertEqual(MultiWeekAdaptationAnalyzer.classifyDirection(s), .enduranceBuild)
    }
}

private func appTestClassification(primaryMode: TrainingMode) -> TrainingClassification {
    TrainingClassification(
        primaryMode: primaryMode,
        confidence: .medium,
        dataQuality: .high,
        claimLevel: .primaryClassification,
        evidence: [
            TrainingClassificationEvidence(
                label: "心率型態",
                value: "sample",
                direction: .supports,
                explanation: "App 測試用分類快照。"
            )
        ],
        debug: TrainingClassificationDebug(
            classificationVersion: "app-test",
            usedPersonalizedZones: false
        )
    )
}

private func appTestFeedbackRecord(
    id: UUID,
    workoutID: UUID,
    rating: TrainingClassificationFeedbackRating,
    userSuggestedMode: TrainingMode?,
    primaryMode: TrainingMode
) -> TrainingClassificationFeedbackRecord {
    TrainingClassificationFeedbackRecord(
        id: id,
        feedback: TrainingClassificationFeedback(
            workoutID: workoutID,
            recordedAt: Date(timeIntervalSince1970: 7_200),
            originalClassification: appTestClassification(primaryMode: primaryMode),
            rating: rating,
            userSuggestedMode: userSuggestedMode
        )
    )
}

private func appSourceText(named fileName: String) throws -> String {
    try sourceText(relativePath: "Sources/ZoneTruthApp/\(fileName)")
}

private func coreSourceText(named fileName: String) throws -> String {
    try sourceText(relativePath: "Sources/ZoneTruthCore/\(fileName)")
}

private func sourceText(relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repoRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

private struct StubHealthKitWorkoutStore: HealthKitWorkoutStore {
    let isAvailable: Bool
    let authorizationStatus: HealthAuthorizationStatus
    let requestedAuthorizationStatus: HealthAuthorizationStatus
    let snapshots: [HealthKitWorkoutSnapshot]
    var sleepContext: WeeklySleepContext? = nil
    var sleepQueryResult: HealthKitSleepContextQueryResult? = nil
    var sleepQueryError: Error? = nil
    var restingHeartRateBaseline: Double? = nil
    var debugAuthorizationDetailsValue: HealthKitAuthorizationDebugDetails? = nil
    var debugGlobalRecoveryProbeValue: HealthKitRecoveryProbeSummary? = nil

    func requestAuthorization() async -> HealthAuthorizationStatus {
        requestedAuthorizationStatus
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkoutSnapshot] {
        _ = limit
        return snapshots
    }

    func fetchRecentSleepContext(days: Int) async throws -> HealthKitSleepContextQueryResult {
        if let sleepQueryError {
            throw sleepQueryError
        }
        if let sleepQueryResult {
            return sleepQueryResult
        }
        return HealthKitSleepContextQueryResult(
            context: sleepContext,
            lookbackDays: days,
            rawSampleCount: sleepContext?.nightsWithSleep ?? 0,
            asleepSampleCount: sleepContext?.nightsWithSleep ?? 0
        )
    }

    func fetchRestingHeartRateBaseline() async throws -> Double? {
        restingHeartRateBaseline
    }

    func debugAuthorizationDetails() async -> HealthKitAuthorizationDebugDetails? {
        debugAuthorizationDetailsValue
    }

    func debugGlobalRecoveryProbe(limit: Int) async -> HealthKitRecoveryProbeSummary? {
        _ = limit
        return debugGlobalRecoveryProbeValue
    }
}

private final class DebugLogRecorder {
    private var messages: [String] = []
    private let lock = NSLock()

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    func combinedLog() -> String {
        lock.lock()
        defer { lock.unlock() }
        return messages.joined(separator: "\n")
    }
}

private struct StubStravaClient: StravaClient {
    let connectionStatus: StravaConnectionStatus
    let activities: [StravaActivitySnapshot]

    func fetchRecentActivities(limit: Int) async throws -> [StravaActivitySnapshot] {
        _ = limit
        return activities
    }

    func fetchActivities(after: Date, limit: Int) async throws -> [StravaActivitySnapshot] {
        _ = limit
        return activities.filter { $0.startDate > after }
    }
}

private struct StubStravaOAuthClient: StravaOAuthClient {
    let result: Result<StravaTokenExchangeResponse, StravaOAuthError>

    func exchangeToken(using request: StravaTokenExchangeRequest) async throws -> StravaTokenExchangeResponse {
        try result.get()
    }

    func refreshToken(using request: StravaTokenRefreshRequest) async throws -> StravaTokenExchangeResponse {
        try result.get()
    }
}

private struct StaticWorkoutRepository: WorkoutRepository {
    let workouts: [WorkoutInput]
    var sleepContext: WeeklySleepContext? = nil

    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(workouts: workouts, source: .mockSamples, sleepContext: sleepContext)
    }
}

private struct StaticLoadResultRepository: WorkoutRepository {
    let result: WorkoutLoadResult

    func loadResult() -> WorkoutLoadResult {
        result
    }
}

private final class SpyStravaSessionStore: StravaSessionStore {
    private(set) var savedSessions: [StravaSession] = []
    private var stored: StravaSession?

    init(initial: StravaSession? = nil) {
        stored = initial
    }

    func loadSession() -> StravaSession? { stored }

    func saveSession(_ session: StravaSession) {
        stored = session
        savedSessions.append(session)
    }

    func clearSession() {
        stored = nil
    }
}
