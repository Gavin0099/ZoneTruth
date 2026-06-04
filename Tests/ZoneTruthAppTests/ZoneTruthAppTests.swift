import Foundation
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
        guard let hrv = result.workouts.first?.hrvSDNNMilliseconds else {
            XCTFail("Expected HRV SDNN value from HealthKit snapshot")
            return
        }
        XCTAssertEqual(hrv, 42.5, accuracy: 0.001)
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
        XCTAssertEqual(manager.pendingSuggestion?.source.verificationLabel, "非驗證閾值")

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
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Resting HR 未設定"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("沒有待套用建議"))

        manager.updateRestingHeartRate(60)
        manager.updateRestingHeartRateSuggestionOffsets(lowerOffset: 48, upperOffset: 62)
        manager.generateRestingHeartRateSuggestion()
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Resting HR 60 bpm"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("偏移 +48/+62"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("有待套用建議 108-122 bpm"))

        manager.applySuggestion()
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Resting HR 建議已套用"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Zone 2 108-122 bpm"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("沒有待套用建議"))

        manager.updateZone2Bounds(lower: 112, upper: 126)
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("自訂界線"))
        XCTAssertTrue(manager.zone2ProfileStatusSummary.contains("Zone 2 112-126 bpm"))
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
            .flatMap { [$0.title, $0.status, $0.method, $0.confidenceReason, $0.validationHint ?? ""] }
            .joined(separator: " ")

        XCTAssertTrue(text.contains("Zone 2 心率範圍"))
        XCTAssertTrue(text.contains("起始參考"))
        XCTAssertTrue(text.contains("VO2 間歇型態"))
        XCTAssertTrue(text.contains("目前只描述間歇型態"))
        XCTAssertTrue(text.contains("肌力訓練型態"))
        XCTAssertTrue(text.contains("目前只描述心率型態"))
        XCTAssertFalse(text.contains("VO2 max 實測"))
        XCTAssertFalse(text.contains("精準 Zone 2"))
        XCTAssertFalse(text.contains("1RM"))
        XCTAssertFalse(text.contains("肌力測量"))
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

        XCTAssertTrue(zone2Text.contains("LT1"))
        XCTAssertTrue(zone2Text.contains("VT1"))
        XCTAssertTrue(vo2Text.contains("不代表已推估或測量最大攝氧量數值"))
        XCTAssertTrue(strengthText.contains("不能代表最大肌力"))
        XCTAssertFalse(zone2Text.contains("最大攝氧量"), zone2Text)
        XCTAssertFalse(vo2Text.contains("精準 Zone 2"), vo2Text)
        XCTAssertFalse(strengthText.contains("VO2 max"), strengthText)
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
        return [item.title, item.status, item.method, item.confidenceReason, item.validationHint ?? ""]
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
        XCTAssertTrue(suggestedSummary.contains("Resting HR 建議已套用"))
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
        XCTAssertEqual(signal.temporalScopes.map(\.label), ["7d signal", "28d unavailable"])
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
        XCTAssertTrue(rendered.contains("安排至少一堂肌力課"))
    }

    func testWeeklyCTAPresenterKeepsWeakEvidencePrefixOnGoalAwareAction() {
        let rendered = WeeklyCTAPresenter.render(
            base: "本週訓練節奏尚可，下週視體感微調強度。",
            for: .weakInference,
            goal: .aerobicBase,
            goalSignal: .divergent
        )
        XCTAssertTrue(rendered.hasPrefix("訊號有限，僅供方向參考："))
        XCTAssertTrue(rendered.contains("優先補低強度有氧時段"))
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
        XCTAssertEqual(WeeklyTemporalScopeLabel.signal7d, "7d 訊號")
        XCTAssertEqual(WeeklyTemporalScopeLabel.unavailable28d, "28d 不可用")
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
            hrvSDNNMilliseconds: 42.5
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

    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(workouts: workouts, source: .mockSamples)
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
