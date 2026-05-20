import Foundation
import XCTest
@testable import ZoneTruthApp
@testable import ZoneTruthCore

final class ZoneTruthAppTests: XCTestCase {
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
        XCTAssertTrue(evaluation.trainingTendency.contains("Zone 2") || evaluation.trainingTendency.contains("混合有氧"))
        XCTAssertTrue(evaluation.nextAction.contains("降低") || evaluation.nextAction.contains("放慢") || evaluation.nextAction.contains("強度"))
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
                $0.localizedCaseInsensitiveContains("Zone 3") ||
                $0.localizedCaseInsensitiveContains("飄移")
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

    func testWorkoutEvaluationSnapshotFixture() throws {
        let records = buildEvaluationFixtureRecords()
        let fixtureURL = try fixtureFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.escapeSlashes = false
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

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
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

private struct StubStravaOAuthClient: StravaOAuthClient {
    let result: Result<StravaTokenExchangeResponse, StravaOAuthError>

    func exchangeToken(using request: StravaTokenExchangeRequest) async throws -> StravaTokenExchangeResponse {
        try result.get()
    }

    func refreshToken(using request: StravaTokenRefreshRequest) async throws -> StravaTokenExchangeResponse {
        try result.get()
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
}
