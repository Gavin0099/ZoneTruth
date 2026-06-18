import Foundation
import XCTest
@testable import ZoneTruthCore

final class ZoneTruthCoreTests: XCTestCase {
    private struct Zone2ObservationFixtureRecord: Codable, Equatable {
        let id: String
        let observation: Zone2ObservationSnapshot
    }

    private struct Zone2ObservationSnapshot: Codable, Equatable {
        let zoneDistribution: ZoneDistributionSnapshot
        let driftRatio: Double?
        let stabilityStandardDeviation: Double?
        let sampleQuality: String
    }

    private struct ZoneDistributionSnapshot: Codable, Equatable {
        let counts: [String: Int]
        let ratios: [String: Double]
    }

    private struct VO2ObservationFixtureRecord: Codable, Equatable {
        let id: String
        let observation: VO2ObservationSnapshot
    }

    private struct VO2ObservationSnapshot: Codable, Equatable {
        let zoneDistribution: ZoneDistributionSnapshot
        let highIntensityRatio: Double
        let peakZoneRatio: Double
        let intervalPatternHint: String
        let sampleQuality: String
    }

    private struct StrengthObservationFixtureRecord: Codable, Equatable {
        let id: String
        let observation: StrengthObservationSnapshot
    }

    private struct StrengthObservationSnapshot: Codable, Equatable {
        let avgHeartRate: Double?
        let highHrSustainedRatio: Double
        let recoveryDropHint: String
        let sampleQuality: String
    }

    private struct ActivityObservationFixtureRecord: Codable, Equatable {
        let id: String
        let observation: ActivityObservationSnapshot
    }

    private struct ActivityObservationSnapshot: Codable, Equatable {
        let zoneDistribution: ZoneDistributionSnapshot
        let movementType: String
        let duration: Double
        let sampleQuality: String
    }

    private struct ObservationRegistryEntry: Equatable {
        let intent: TrainingIntent
        let analyzerName: String
        let fixtureFile: String
        let updateFlag: String
    }

    private struct AnalyzerMetadataEnvelope: Codable, Equatable {
        let id: String
        let specResolution: TrainingSpecResolution
    }

    private struct ImporterMetadataEnvelope: Codable, Equatable {
        let source: String
        let specResolution: TrainingSpecResolution
    }

    private struct DisplayMetadataEnvelope: Codable, Equatable {
        let surface: String
        let specResolution: TrainingSpecResolution
    }

    func testTrainingMetricMetadataCodableRoundTripsSpecValues() throws {
        let metadata = TrainingMetricMetadata(
            metric: .vo2Max,
            method: TrainingMetricMethod(
                tier: .productReference,
                source: .garmin,
                name: "Garmin VO2 max estimate",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .mediumLow,
                basis: "Exercise-based wearable estimate, not lab CPET.",
                limitingFactors: ["No gas exchange data"]
            ),
            dataQualityFlags: ["outdoor_run", "stable_hr"],
            recommendedValidation: "CPET if used for clinical or high-performance decisions."
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingMetricMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
        XCTAssertTrue(json.contains("product_reference"))
        XCTAssertTrue(json.contains("two_or_more_levels_below"))
        XCTAssertTrue(json.contains("estimate_only"))
        XCTAssertTrue(json.contains("specResolution"))
        XCTAssertEqual(decoded.specResolution.evidenceLayer, .trainingEstimatorEvidenceMap)
        XCTAssertEqual(decoded.specResolution.sourceRoleLayer, .none)
    }

    func testTrainingMetricMetadataDecodesLegacyJSONWithoutSpecResolution() throws {
        let legacyJSON = """
        {
          "metric": "vo2max",
          "method": {
            "tier": "product_reference",
            "source": "apple",
            "name": "Apple Health VO2 max estimate",
            "referenceStandardDistance": "two_or_more_levels_below"
          },
          "confidence": {
            "level": "medium_low",
            "basis": "Apple product estimate.",
            "limitingFactors": ["No CPET data"]
          },
          "claim": {
            "ceiling": "estimate_only",
            "allowedTerms": ["Apple Health VO2 max estimate"],
            "forbiddenTerms": ["true VO2 max"]
          },
          "dataQualityFlags": ["apple_health"],
          "recommendedValidation": "CPET if precision matters."
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrainingMetricMetadata.self, from: legacyJSON)

        XCTAssertEqual(decoded.metric, .vo2Max)
        XCTAssertEqual(decoded.method.source, .apple)
        XCTAssertEqual(decoded.specResolution.evidenceLayer, .trainingEstimatorEvidenceMap)
        XCTAssertEqual(decoded.specResolution.sourceRoleLayer, .none)
        XCTAssertNil(decoded.specResolution.sourceRoleReason)
    }

    func testTrainingMetricMetadataCanCarryAppleHealthSourceRoleResolution() throws {
        let metadata = TrainingMetricMetadata(
            metric: .vo2Max,
            method: TrainingMetricMethod(
                tier: .productReference,
                source: .apple,
                name: "Apple Health VO2 max estimate",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .mediumLow,
                basis: "Apple-produced product estimate, not CPET."
            ),
            dataQualityFlags: ["apple_health"],
            recommendedValidation: "CPET if used for clinical or high-performance decisions.",
            specResolution: TrainingSpecResolution(
                sourceRoleLayer: .appleHealthTrainingDataRoleMatrix,
                sourceRoleReason: .appleHealthVO2MaxProductReference
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingMetricMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
        XCTAssertTrue(json.contains("APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX"))
        XCTAssertTrue(json.contains("apple_health_vo2max_product_reference"))
        XCTAssertEqual(decoded.specResolution.evidenceLayer, .trainingEstimatorEvidenceMap)
        XCTAssertEqual(decoded.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
    }

    func testTrainingSpecResolutionCodableRoundTripsContractValues() throws {
        let resolution = TrainingSpecResolution(
            evidenceLayer: .trainingEstimatorEvidenceMap,
            sourceRoleLayer: .appleHealthTrainingDataRoleMatrix,
            sourceRoleReason: .appleHealthRestingHRInitialZone2Range
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(resolution)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingSpecResolution.self, from: data)

        XCTAssertEqual(decoded, resolution)
        XCTAssertTrue(json.contains("TRAINING_ESTIMATOR_EVIDENCE_MAP"))
        XCTAssertTrue(json.contains("APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX"))
        XCTAssertTrue(json.contains("apple_health_resting_hr_initial_zone2_range"))
    }

    func testAnalyzerImporterAndDisplayMetadataCanCarrySpecResolution() throws {
        let analyzerMetadata = AnalyzerMetadataEnvelope(
            id: "core_vo2_interval_classifier",
            specResolution: TrainingSpecResolution(
                sourceRoleLayer: .none,
                sourceRoleReason: .analyzerGeneric
            )
        )
        let importerMetadata = ImporterMetadataEnvelope(
            source: "apple_health_vo2max",
            specResolution: TrainingSpecResolution(
                sourceRoleLayer: .appleHealthTrainingDataRoleMatrix,
                sourceRoleReason: .appleHealthVO2MaxProductReference
            )
        )
        let displayMetadata = DisplayMetadataEnvelope(
            surface: "workout_detail_zone2_reference",
            specResolution: TrainingSpecResolution(
                sourceRoleLayer: .appleHealthTrainingDataRoleMatrix,
                sourceRoleReason: .appleHealthRestingHRInitialZone2Range
            )
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(AnalyzerMetadataEnvelope.self, from: encoder.encode(analyzerMetadata)),
            analyzerMetadata
        )
        XCTAssertEqual(
            try decoder.decode(ImporterMetadataEnvelope.self, from: encoder.encode(importerMetadata)),
            importerMetadata
        )
        XCTAssertEqual(
            try decoder.decode(DisplayMetadataEnvelope.self, from: encoder.encode(displayMetadata)),
            displayMetadata
        )
    }

    func testTrainingClassificationCodableRoundTripsV31Shape() throws {
        let classification = TrainingClassification(
            primaryMode: .conditioningLike,
            confidence: .mediumHigh,
            dataQuality: .medium,
            claimLevel: .primaryClassification,
            evidence: [
                TrainingClassificationEvidence(
                    label: "Zone 4/5",
                    value: "28%",
                    direction: .supports,
                    explanation: "重訓活動中高心率比例偏高，較像高密度循環訓練。"
                ),
                TrainingClassificationEvidence(
                    label: "Apple Watch 活動類型",
                    value: "肌力訓練",
                    direction: .neutral,
                    explanation: "活動類型限制候選分類，但不是最終答案。",
                    visibility: .advancedUser
                )
            ],
            warnings: [
                TrainingClassificationWarning(
                    type: .missingPersonalZones,
                    message: "目前使用預設心率區間，分類可能較粗略。"
                )
            ],
            notApplicableReasons: [
                TrainingNotApplicableReason(
                    model: .zone2,
                    reason: .notSteadyStateActivity,
                    message: "重訓不以連續 Zone 2 作為主要判讀。"
                )
            ],
            debug: TrainingClassificationDebug(
                classificationVersion: "v3.1.0",
                zoneConfigVersion: "default-20260609",
                usedPersonalizedZones: false,
                ruleScores: [
                    "conditioning_like": 0.82,
                    "strength_pattern": 0.44
                ],
                notes: ["debug values are not user-facing"]
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(classification)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingClassification.self, from: data)

        XCTAssertEqual(decoded, classification)
        XCTAssertTrue(json.contains("conditioning_like"))
        XCTAssertTrue(json.contains("medium_high"))
        XCTAssertTrue(json.contains("primary_classification"))
        XCTAssertTrue(json.contains("missing_personal_zones"))
        XCTAssertTrue(json.contains("not_steady_state_activity"))
        XCTAssertTrue(json.contains("usedPersonalizedZones"))
    }

    func testTrainingClassificationKeepsClaimConfidenceAndDataQualityIndependent() {
        let classification = TrainingClassification(
            primaryMode: .zone2,
            confidence: .mediumHigh,
            dataQuality: .low,
            claimLevel: .secondaryReference,
            evidence: [
                TrainingClassificationEvidence(
                    label: "Zone 2 佔比",
                    value: "68%",
                    direction: .supports,
                    explanation: "心率分布偏向 Zone 2。"
                )
            ],
            warnings: [
                TrainingClassificationWarning(
                    type: .lowHeartRateQuality,
                    message: "心率資料品質偏低，判讀僅供參考。"
                )
            ]
        )

        XCTAssertEqual(classification.confidence, .mediumHigh)
        XCTAssertEqual(classification.dataQuality, .low)
        XCTAssertEqual(classification.claimLevel, .secondaryReference)
        XCTAssertEqual(classification.evidence.first?.visibility, .userVisible)
        XCTAssertEqual(classification.warnings.first?.visibility, .userVisible)
    }

    func testTrainingClassificationFeedbackCodableRoundTripsWithoutIntent() throws {
        let classification = sampleClassification(primaryMode: .conditioningLike)
        let feedback = TrainingClassificationFeedback(
            workoutID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            recordedAt: Date(timeIntervalSince1970: 1_800),
            originalClassification: classification,
            rating: .inaccurate,
            userSuggestedMode: .strengthPattern,
            note: "Felt more like separated sets."
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(feedback)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingClassificationFeedback.self, from: data)

        XCTAssertEqual(decoded, feedback)
        XCTAssertTrue(json.contains("userSuggestedMode"))
        XCTAssertTrue(json.contains("strength_pattern"))
        XCTAssertFalse(json.contains("intent"))
        XCTAssertFalse(json.contains("goal"))
    }

    func testTrainingClassificationFeedbackShapeDoesNotExposeIntentFields() {
        let feedback = TrainingClassificationFeedback(
            workoutID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            recordedAt: Date(timeIntervalSince1970: 2_400),
            originalClassification: sampleClassification(primaryMode: .zone2),
            rating: .somewhatSimilar,
            userSuggestedMode: .mixed
        )
        let fieldNames = Set(Mirror(reflecting: feedback).children.compactMap(\.label))

        XCTAssertTrue(fieldNames.contains("originalClassification"))
        XCTAssertTrue(fieldNames.contains("userSuggestedMode"))
        XCTAssertFalse(fieldNames.contains("intent"))
        XCTAssertFalse(fieldNames.contains("declaredIntent"))
        XCTAssertFalse(fieldNames.contains("originalIntent"))
        XCTAssertFalse(fieldNames.contains("goal"))
    }

    func testTrainingClassificationFeedbackDoesNotMutateClassifierOutput() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "metabolic_strength_circuit" }!
            .workout
        let before = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy()
        )
        _ = TrainingClassificationFeedback(
            workoutID: workout.id,
            recordedAt: Date(timeIntervalSince1970: 3_000),
            originalClassification: before,
            rating: .inaccurate,
            userSuggestedMode: .strengthPattern
        )
        let after = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy()
        )

        XCTAssertEqual(before, after)
        XCTAssertEqual(after.primaryMode, .conditioningLike)
    }

    func testTrainingClassificationFeedbackRecordCodableRoundTripsWithoutIntent() throws {
        let record = TrainingClassificationFeedbackRecord(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            feedback: TrainingClassificationFeedback(
                workoutID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                recordedAt: Date(timeIntervalSince1970: 3_600),
                originalClassification: sampleClassification(primaryMode: .vo2Stimulus),
                rating: .somewhatSimilar,
                userSuggestedMode: .zone2,
                source: .user,
                note: "Felt steadier than VO2."
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(TrainingClassificationFeedbackRecord.self, from: data)

        XCTAssertEqual(decoded, record)
        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertTrue(json.contains("feedback"))
        XCTAssertTrue(json.contains("userSuggestedMode"))
        XCTAssertFalse(json.contains("intent"))
        XCTAssertFalse(json.contains("goal"))
    }

    func testInMemoryTrainingClassificationFeedbackStoreSavesAndReadsRecords() {
        let workoutID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let otherWorkoutID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let targetRecord = TrainingClassificationFeedbackRecord(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            feedback: TrainingClassificationFeedback(
                workoutID: workoutID,
                recordedAt: Date(timeIntervalSince1970: 4_200),
                originalClassification: sampleClassification(primaryMode: .conditioningLike),
                rating: .inaccurate,
                userSuggestedMode: .strengthPattern
            )
        )
        let otherRecord = TrainingClassificationFeedbackRecord(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            feedback: TrainingClassificationFeedback(
                workoutID: otherWorkoutID,
                recordedAt: Date(timeIntervalSince1970: 4_800),
                originalClassification: sampleClassification(primaryMode: .zone2),
                rating: .accurate
            )
        )
        let store = InMemoryTrainingClassificationFeedbackStore()

        store.save(targetRecord)
        store.save(otherRecord)

        XCTAssertEqual(store.records(for: workoutID), [targetRecord])
        XCTAssertEqual(store.records(for: otherWorkoutID), [otherRecord])
        XCTAssertEqual(store.allRecords(), [targetRecord, otherRecord])
    }

    func testTrainingModeClassifierReturnsInsufficientDataBeforeModeGuessing() {
        let start = Date(timeIntervalSince1970: 31 * 86_400)
        let workout = WorkoutInput(
            workoutType: .strengthTraining,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            heartRateSamples: [
                HeartRateSample(timestamp: start, bpm: 96),
                HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 118)
            ],
            intent: .strength
        )

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy(minimumSampleCount: 5)
        )

        XCTAssertEqual(classification.primaryMode, .insufficientData)
        XCTAssertEqual(classification.confidence, .insufficient)
        XCTAssertEqual(classification.dataQuality, .insufficient)
        XCTAssertEqual(classification.claimLevel, .notApplicable)
        XCTAssertTrue(classification.warnings.contains { $0.type == .lowHeartRateQuality })
        XCTAssertTrue(classification.notApplicableReasons.contains { $0.model == .strengthPattern })
    }

    func testTrainingModeClassifierClassifiesStrengthHighHRAsConditioningLikeBeforeStrengthPattern() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "metabolic_strength_circuit" }!
            .workout

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy()
        )

        XCTAssertEqual(classification.primaryMode, .conditioningLike)
        XCTAssertEqual(classification.claimLevel, .primaryClassification)
        XCTAssertNotEqual(classification.primaryMode, .strengthPattern)
        XCTAssertTrue(classification.evidence.contains { $0.label == "高心率比例" && $0.direction == .supports })
        XCTAssertNotNil(classification.debug?.ruleScores["conditioning_like"])
    }

    func testTrainingModeClassifierClassifiesTypicalStrengthAsStrengthPattern() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy()
        )

        XCTAssertEqual(classification.primaryMode, .strengthPattern)
        XCTAssertEqual(classification.confidence, .mediumHigh)
        XCTAssertEqual(classification.dataQuality, .high)
        XCTAssertEqual(classification.claimLevel, .primaryClassification)
        XCTAssertTrue(classification.evidence.contains { $0.explanation.contains("未觸發高密度循環訓練例外") })
    }

    func testTrainingClassificationSnapshotProviderDelegatesToCoreClassifier() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout
        let policy = sprint3ClassificationPolicy()

        let direct = TrainingModeClassifier.classify(
            workout: workout,
            policy: policy,
            zoneConfigVersion: "test-zones",
            usedPersonalizedZones: true
        )
        let snapshot = TrainingClassificationSnapshotProvider.snapshot(
            for: workout,
            policy: policy,
            zoneConfigVersion: "test-zones",
            usedPersonalizedZones: true
        )

        XCTAssertEqual(snapshot, direct)
        XCTAssertEqual(snapshot.debug?.zoneConfigVersion, "test-zones")
        XCTAssertEqual(snapshot.debug?.usedPersonalizedZones, true)
    }

    func testTrainingModeClassifierDowngradesSwimmingZone2LikeClassification() {
        let workout = makeSwimmingWorkout(
            samples: Array(repeating: 118, count: 30),
            intent: .zone2
        )

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy(minimumSampleCount: 5)
        )

        XCTAssertEqual(classification.primaryMode, .zone2)
        XCTAssertEqual(classification.confidence, .low)
        XCTAssertEqual(classification.dataQuality, .low)
        XCTAssertEqual(classification.claimLevel, .secondaryReference)
        XCTAssertTrue(classification.warnings.contains { $0.type == .lowHeartRateQuality })
    }

    func testTrainingModeClassifierDowngradesSwimmingVO2LikeClassification() {
        let workout = makeSwimmingWorkout(
            samples: Array(repeating: 160, count: 30),
            intent: .vo2Interval
        )

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy(minimumSampleCount: 5)
        )

        XCTAssertEqual(classification.primaryMode, .vo2Stimulus)
        XCTAssertEqual(classification.confidence, .low)
        XCTAssertEqual(classification.dataQuality, .low)
        XCTAssertEqual(classification.claimLevel, .secondaryReference)
        XCTAssertTrue(classification.warnings.contains { $0.message.contains("游泳心率資料") })
    }

    func testTrainingModeClassifierKeepsSparseSwimmingAsInsufficientData() {
        let workout = makeSwimmingWorkout(
            samples: [118, 120],
            intent: .zone2,
            duration: 30 * 60
        )

        let classification = TrainingModeClassifier.classify(
            workout: workout,
            policy: sprint3ClassificationPolicy(minimumSampleCount: 5)
        )

        XCTAssertEqual(classification.primaryMode, .insufficientData)
        XCTAssertEqual(classification.confidence, .insufficient)
        XCTAssertEqual(classification.dataQuality, .insufficient)
        XCTAssertEqual(classification.claimLevel, .notApplicable)
        XCTAssertTrue(classification.notApplicableReasons.contains { $0.reason == .insufficientHeartRateData })
    }

    func testProductReferenceMetricCannotClaimMeasured() {
        let garminEstimate = TrainingMetricMetadata(
            metric: .vo2Max,
            method: TrainingMetricMethod(
                tier: .productReference,
                source: .garmin,
                name: "Garmin VO2 max estimate",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .medium,
                basis: "Product estimate."
            ),
            claim: TrainingMetricClaim(ceiling: .measuredIfDirect)
        )
        let cpetMeasurement = TrainingMetricMetadata(
            metric: .vo2Max,
            method: TrainingMetricMethod(
                tier: .goldStandardAnchor,
                source: .cpet,
                name: "CPET with gas exchange",
                referenceStandardDistance: .direct
            ),
            confidence: TrainingMetricConfidence(
                level: .high,
                basis: "Direct lab measurement with gas exchange."
            ),
            claim: TrainingMetricClaim(ceiling: .measuredIfDirect)
        )

        XCTAssertFalse(garminEstimate.isClaimCeilingAdmissible)
        XCTAssertTrue(cpetMeasurement.isClaimCeilingAdmissible)
    }

    func testPercentHRMaxZone2IsStartingPointOnlyLowConfidence() {
        let overclaimedPercentHRMax = TrainingMetricMetadata(
            metric: .zone2HeartRateRange,
            method: TrainingMetricMethod(
                tier: .weakHeuristic,
                source: .percentHRMax,
                name: "Percent HRmax zone heuristic",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .medium,
                basis: "Formula-based threshold estimate."
            ),
            claim: TrainingMetricClaim(ceiling: .estimateOnly)
        )
        let boundedPercentHRMax = TrainingMetricMetadata(
            metric: .zone2HeartRateRange,
            method: TrainingMetricMethod(
                tier: .weakHeuristic,
                source: .percentHRMax,
                name: "Percent HRmax zone heuristic",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .low,
                basis: "Formula-based starting point only.",
                limitingFactors: ["No LT1 or VT1 validation"]
            ),
            claim: TrainingMetricClaim(
                ceiling: .startingPointOnly,
                allowedTerms: ["starting range"],
                forbiddenTerms: ["validated threshold"]
            )
        )

        XCTAssertFalse(overclaimedPercentHRMax.isClaimCeilingAdmissible)
        XCTAssertTrue(boundedPercentHRMax.isClaimCeilingAdmissible)
    }

    func testTrainingMetricMetadataDefaultClaimCeilingMatchesMethodDistance() {
        let directCPET = TrainingMetricMethod(
            tier: .goldStandardAnchor,
            source: .cpet,
            name: "CPET with gas exchange",
            referenceStandardDistance: .direct
        )
        let runningEstimator = TrainingMetricMethod(
            tier: .fieldEstimator,
            source: .runningHRSpeed,
            name: "Running HR-speed model",
            referenceStandardDistance: .oneLevelBelow
        )
        let productReference = TrainingMetricMethod(
            tier: .productReference,
            source: .firstbeat,
            name: "Firstbeat public method reference",
            referenceStandardDistance: .twoOrMoreLevelsBelow
        )
        let weakHeuristic = TrainingMetricMethod(
            tier: .weakHeuristic,
            source: .percentHRMax,
            name: "Percent HRmax zone heuristic",
            referenceStandardDistance: .twoOrMoreLevelsBelow
        )

        XCTAssertEqual(TrainingMetricClaimCeiling.defaultCeiling(for: directCPET), .measuredIfDirect)
        XCTAssertEqual(TrainingMetricClaimCeiling.defaultCeiling(for: runningEstimator), .estimateOnly)
        XCTAssertEqual(TrainingMetricClaimCeiling.defaultCeiling(for: productReference), .estimateOnly)
        XCTAssertEqual(TrainingMetricClaimCeiling.defaultCeiling(for: weakHeuristic), .startingPointOnly)
    }

    func testMetricSpecificClaimProfilesPreserveDifferentEvidenceBoundaries() {
        let zone2 = Zone2QualityAnalyzer.analyze(
            workout: SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        ).metricMetadata.first { $0.metric == .zone2HeartRateRange }!
        let vo2 = VO2IntervalAnalyzer.analyze(
            workout: SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        ).metricMetadata.first { $0.metric == .vo2IntervalQuality }!
        let strength = StrengthAnalyzer.analyze(
            workout: SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout
        ).metricMetadata.first { $0.metric == .strength }!

        XCTAssertEqual(zone2.claimProfile.kind, .zone2ThresholdRange)
        XCTAssertEqual(vo2.claimProfile.kind, .vo2IntervalPattern)
        XCTAssertEqual(strength.claimProfile.kind, .strengthSessionPattern)
        XCTAssertTrue(zone2.claimProfile.forbiddenTerms.contains("精準 Zone 2"))
        XCTAssertTrue(vo2.claimProfile.forbiddenTerms.contains("VO2 max 實測"))
        XCTAssertTrue(strength.claimProfile.forbiddenTerms.contains("肌力測量"))
        XCTAssertNotEqual(zone2.claimProfile.disclosure, vo2.claimProfile.disclosure)
        XCTAssertNotEqual(vo2.claimProfile.disclosure, strength.claimProfile.disclosure)
    }

    func testImportedVO2MaxEstimateAddsScalarMetadataWithoutReplacingIntervalQuality() {
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

        let result = WorkoutIntentAnalyzer.analyze(workout)
        let scalarVO2 = result.metricMetadata.first { $0.metric == .vo2Max }
        let intervalQuality = result.metricMetadata.first { $0.metric == .vo2IntervalQuality }

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertNotNil(intervalQuality)
        XCTAssertEqual(scalarVO2?.claimProfile.kind, .vo2MaxEstimate)
        XCTAssertEqual(scalarVO2?.method.tier, .productReference)
        XCTAssertEqual(scalarVO2?.method.source, .apple)
        XCTAssertEqual(scalarVO2?.method.referenceStandardDistance, .twoOrMoreLevelsBelow)
        XCTAssertEqual(scalarVO2?.claim.ceiling, .estimateOnly)
        XCTAssertEqual(scalarVO2?.confidence.level, .mediumLow)
        XCTAssertEqual(scalarVO2?.isClaimCeilingAdmissible, true)
        XCTAssertEqual(scalarVO2?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(scalarVO2?.specResolution.sourceRoleReason, .appleHealthVO2MaxProductReference)
        XCTAssertFalse(scalarVO2?.claim.allowedTerms.contains("lab-equivalent") == true)
    }

    func testAppleHealthBackedMetricMetadataCarriesSourceRoleResolution() {
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
            vo2MaxEstimate: VO2MaxEstimate(
                value: 48.2,
                source: .apple,
                sourceLabel: "Apple Health VO2 max"
            ),
            heartRateRecoveryOneMinute: HeartRateRecoveryObservation(
                value: 21,
                source: .apple,
                sourceLabel: "Apple Health 1-minute heart-rate recovery"
            ),
            runningPower: RunningPowerObservation(
                averageWatts: 246,
                source: .runningHRSpeed,
                sourceLabel: "Apple Health running power"
            ),
            cyclingPower: CyclingPowerObservation(
                averageWatts: 212,
                source: .cyclingPowerHR,
                sourceLabel: "Apple Health cycling power"
            ),
            workoutRoute: WorkoutRouteObservation(
                pointCount: 128,
                elevationGainMeters: 86,
                source: .workoutRoute,
                sourceLabel: "Apple Health workout route"
            )
        )

        let metadata = WorkoutIntentAnalyzer.analyze(workout).metricMetadata
        let vo2 = metadata.first { $0.metric == .vo2Max }
        let recovery = metadata.first { $0.metric == .heartRateRecovery }
        let runningPower = metadata.first { $0.metric == .runningPower }
        let cyclingPower = metadata.first { $0.metric == .cyclingPower }
        let route = metadata.first { $0.metric == .workoutRoute }

        XCTAssertEqual(vo2?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(vo2?.specResolution.sourceRoleReason, .appleHealthVO2MaxProductReference)
        XCTAssertEqual(recovery?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(recovery?.specResolution.sourceRoleReason, .appleHealthHeartRateRecoveryContext)
        XCTAssertEqual(runningPower?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(runningPower?.specResolution.sourceRoleReason, .appleHealthPowerExternalLoadContext)
        XCTAssertEqual(cyclingPower?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(cyclingPower?.specResolution.sourceRoleReason, .appleHealthPowerExternalLoadContext)
        XCTAssertEqual(route?.specResolution.sourceRoleLayer, .appleHealthTrainingDataRoleMatrix)
        XCTAssertEqual(route?.specResolution.sourceRoleReason, .appleHealthRouteContext)
    }

    func testStructuredStrengthMetricAddsMeasurementMetadataWithoutReplacingHeartRatePattern() {
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

        let result = StrengthAnalyzer.analyze(workout: workout)
        let pattern = result.metricMetadata.first {
            $0.metric == .strength && $0.method.source == .heartRatePattern
        }
        let structuredMetric = result.metricMetadata.first {
            $0.metric == .strength && $0.method.source == .e1RM
        }

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(pattern?.claimProfile.kind, .strengthSessionPattern)
        XCTAssertEqual(structuredMetric?.claimProfile.kind, .strengthMeasurement)
        XCTAssertEqual(structuredMetric?.method.tier, .fieldEstimator)
        XCTAssertEqual(structuredMetric?.method.referenceStandardDistance, .oneLevelBelow)
        XCTAssertEqual(structuredMetric?.claim.ceiling, .estimateOnly)
        XCTAssertEqual(structuredMetric?.confidence.level, .medium)
        XCTAssertEqual(structuredMetric?.isClaimCeilingAdmissible, true)
        XCTAssertFalse(structuredMetric?.claim.forbiddenTerms.contains("1RM") == true)
        XCTAssertTrue(structuredMetric?.dataQualityFlags.contains("repetition_context_present") == true)
    }

    func testZone2AnalyzerAttachesStartingPointMetadataWithoutChangingVerdict() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)
        let metadata = result.metricMetadata.first { $0.metric == .zone2HeartRateRange }

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(metadata?.method.tier, .weakHeuristic)
        XCTAssertEqual(metadata?.method.source, .policyZoneBounds)
        XCTAssertEqual(metadata?.method.referenceStandardDistance, .twoOrMoreLevelsBelow)
        XCTAssertEqual(metadata?.claim.ceiling, .startingPointOnly)
        XCTAssertEqual(metadata?.confidence.level, .low)
        XCTAssertEqual(metadata?.isClaimCeilingAdmissible, true)
    }

    func testVO2AnalyzerAttachesIntervalQualityMetadataNotVO2MaxClaim() {
        let workout = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout

        let result = VO2IntervalAnalyzer.analyze(workout: workout)
        let metadata = result.metricMetadata.first { $0.metric == .vo2IntervalQuality }

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertFalse(result.metricMetadata.contains { $0.metric == .vo2Max })
        XCTAssertEqual(metadata?.method.source, .heartRatePattern)
        XCTAssertEqual(metadata?.claim.ceiling, .estimateOnly)
        XCTAssertTrue(metadata?.confidence.basis.contains("does not estimate VO2 max") == true)
        XCTAssertTrue(metadata?.claim.forbiddenTerms.contains("true VO2 max") == true)
        XCTAssertEqual(metadata?.isClaimCeilingAdmissible, true)
    }

    func testStrengthAnalyzerAttachesHeartRatePatternMetadataAsStartingPoint() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout

        let result = StrengthAnalyzer.analyze(workout: workout)
        let metadata = result.metricMetadata.first { $0.metric == .strength }

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(metadata?.method.tier, .weakHeuristic)
        XCTAssertEqual(metadata?.method.source, .heartRatePattern)
        XCTAssertEqual(metadata?.claim.ceiling, .startingPointOnly)
        XCTAssertEqual(metadata?.confidence.level, .low)
        XCTAssertTrue(metadata?.claim.forbiddenTerms.contains("1RM") == true)
        XCTAssertEqual(metadata?.isClaimCeilingAdmissible, true)
    }

    func testZoneDistributionCountsSamplesIntoExpectedZones() {
        let distribution = ZoneDistributionAnalyzer.analyze(
            samples: makeSamples([100, 115, 130, 145, 160]),
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        XCTAssertEqual(distribution.counts[.zone1], 1)
        XCTAssertEqual(distribution.counts[.zone2], 1)
        XCTAssertEqual(distribution.counts[.zone3], 1)
        XCTAssertEqual(distribution.counts[.zone4], 1)
        XCTAssertEqual(distribution.counts[.zone5], 1)
    }

    func testZoneDistributionRatiosAreTimeWeightedForIrregularSamples() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            HeartRateSample(timestamp: start, bpm: 115),
            HeartRateSample(timestamp: start.addingTimeInterval(60), bpm: 130),
            HeartRateSample(timestamp: start.addingTimeInterval(660), bpm: 130)
        ]

        let distribution = ZoneDistributionAnalyzer.analyze(
            samples: samples,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )
        let sampleCountDistribution = ZoneDistributionAnalyzer.analyzeBySampleCount(
            samples: samples,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        XCTAssertEqual(distribution.counts[.zone2], 1)
        XCTAssertEqual(distribution.counts[.zone3], 2)
        XCTAssertEqual(sampleCountDistribution.ratio(for: .zone2), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(sampleCountDistribution.ratio(for: .zone3), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(distribution.durationsByZone[.zone2] ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(distribution.durationsByZone[.zone3] ?? 0, 930, accuracy: 0.001)
        XCTAssertEqual(distribution.ratio(for: .zone2), 60.0 / 990.0, accuracy: 0.001)
        XCTAssertEqual(distribution.ratio(for: .zone3), 930.0 / 990.0, accuracy: 0.001)
    }

    func testZoneDistributionSampleCountAnalyzerPreservesLegacyRatios() {
        let distribution = ZoneDistributionAnalyzer.analyzeBySampleCount(
            samples: makeSamples([115, 115, 130]),
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        XCTAssertTrue(distribution.durationsByZone.isEmpty)
        XCTAssertEqual(distribution.counts[.zone2], 2)
        XCTAssertEqual(distribution.counts[.zone3], 1)
        XCTAssertEqual(distribution.ratio(for: .zone2), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(distribution.ratio(for: .zone3), 1.0 / 3.0, accuracy: 0.001)
    }

    func testZone2AnalyzerPassesForSteadyAerobicSession() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertGreaterThan(result.confidence, 0.7)
        XCTAssertFalse(result.reasons.isEmpty)
    }

    func testZone2AnalyzerWarnsForModerateLeakageAndDrift() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "leaky_zone2_run" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .warning)
        XCTAssertTrue(result.reasons.contains { $0.contains("10% 到 20%") || $0.contains("5% 到 8%") })
    }

    func testZone2AnalyzerFailsForHeavyLeakageAndHighDrift() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.reasons.contains { $0.contains("超過 20%") || $0.contains("超過 8%") })
    }

    func testActivityReviewReturnsDescriptivePass() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "badminton_activity_review" }!
            .workout

        let result = WorkoutIntentAnalyzer.analyze(workout)

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertTrue(result.reasons.contains { $0.contains("一般活動") })
    }

    func testVO2IntervalAnalysis() {
        for testCase in SampleWorkoutCases.vo2IntervalValidationCases() {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)
            XCTAssertEqual(result.verdict, testCase.expectedVerdict, "Case \(testCase.name) failed")
        }
    }

    func testVO2IntervalAnalysisIncludesPatternHintReasons() {
        let solid = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let low = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "low_intensity_intervals" }!
            .workout
        let policy = AnalysisPolicy(
            warmupExclusionSeconds: 0,
            cooldownExclusionSeconds: 0,
            minimumDurationSeconds: AnalysisPolicy.default.minimumDurationSeconds,
            minimumSampleCount: 1,
            abnormalSpikeDeltaBPM: AnalysisPolicy.default.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: AnalysisPolicy.default.lowStabilityStdDev,
            mediumStabilityStdDev: AnalysisPolicy.default.mediumStabilityStdDev,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        let solidResult = VO2IntervalAnalyzer.analyze(workout: solid, policy: policy)
        let lowResult = VO2IntervalAnalyzer.analyze(workout: low, policy: policy)

        XCTAssertTrue(solidResult.reasons.contains { $0.contains("多次高峰") })
        XCTAssertTrue(lowResult.reasons.contains { $0.contains("未呈現明顯重複高峰") })
    }

    func testStrengthAnalysis() {
        for testCase in SampleWorkoutCases.strengthValidationCases() {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)
            XCTAssertEqual(result.verdict, testCase.expectedVerdict, "Case \(testCase.name) failed")
        }
    }

    func testStrengthAnalysisIncludesRecoveryPatternReasons() {
        let traditional = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout
        let circuit = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "metabolic_strength_circuit" }!
            .workout
        let policy = AnalysisPolicy(
            warmupExclusionSeconds: 0,
            cooldownExclusionSeconds: 0,
            minimumDurationSeconds: AnalysisPolicy.default.minimumDurationSeconds,
            minimumSampleCount: 1,
            abnormalSpikeDeltaBPM: AnalysisPolicy.default.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: AnalysisPolicy.default.lowStabilityStdDev,
            mediumStabilityStdDev: AnalysisPolicy.default.mediumStabilityStdDev,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        let traditionalResult = StrengthAnalyzer.analyze(workout: traditional, policy: policy)
        let circuitResult = StrengthAnalyzer.analyze(workout: circuit, policy: policy)

        XCTAssertTrue(traditionalResult.reasons.contains { $0.contains("組間下降") })
        XCTAssertTrue(circuitResult.reasons.contains { $0.contains("代謝循環訓練型態") })
    }

    func testWorkoutAnalysisUserVisibleToneAvoidsOverclaimingOrCommandLanguage() {
        let cases = SampleWorkoutCases.zone2ValidationCases()
            + SampleWorkoutCases.vo2IntervalValidationCases()
            + SampleWorkoutCases.strengthValidationCases()
        let forbiddenTerms = ["表現優異", "耐力表現優秀", "達到", "必須", "確保", "請", "非常", "效果"]

        for testCase in cases {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)
            let text = (result.reasons + result.recommendations).joined(separator: " ")
            for term in forbiddenTerms {
                XCTAssertFalse(text.contains(term), "Case '\(testCase.name)' contains overclaiming or command term: \(term)")
            }
        }
    }

    func testValidationDatasetMatchesExpectedVerdicts() {
        let allCases = SampleWorkoutCases.zone2ValidationCases() +
                      SampleWorkoutCases.vo2IntervalValidationCases() +
                      SampleWorkoutCases.strengthValidationCases()

        for testCase in allCases {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)

            XCTAssertEqual(
                result.verdict,
                testCase.expectedVerdict,
                "Unexpected verdict for case '\(testCase.name)'"
            )

            for snippet in testCase.expectedReasonSnippets {
                XCTAssertTrue(
                    result.reasons.contains(where: { $0.localizedCaseInsensitiveContains(snippet) }),
                    "Missing reason snippet '\(snippet)' for case '\(testCase.name)'"
                )
            }
        }
    }

    func testZone2AnalyzerFailsForSparseHeartRateData() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "sparse_hr_cycling" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("過低") })
        XCTAssertNil(result.stabilityStandardDeviation)
        XCTAssertNil(result.driftRatio)
    }

    func testZone2AnalyzerFailsForHighDriftWithLowLeakage() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "high_drift_zone2_ride" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertEqual(result.zoneDistribution.ratio(for: .zone3), 0.0)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("超過 8%") })
    }

    func testZone2AnalyzerWarnsForHighVariabilityWithGoodZones() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "unstable_zone2_run" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .warning)
        XCTAssertEqual(result.zoneDistribution.ratio(for: .zone3), 0.0)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("變異度為中等") })
    }

    func testSanitizerRemovesWarmupCooldownAndSpikes() {
        let policy = AnalysisPolicy.default
        let samples = makeSamples([90, 92, 95, 100, 108, 116, 118, 160, 119, 120, 121, 118, 112, 100])

        let sanitized = HeartRateSampleSanitizer.sanitize(samples, policy: policy)

        XCTAssertFalse(sanitized.isEmpty)
        XCTAssertFalse(sanitized.contains { $0.bpm == 160 })
    }

    func testZone3LeakageBoundaryAt9PercentPasses() {
        let distribution = distributionWithZone3Ratio(0.09)
        XCTAssertEqual(Zone3LeakageAnalyzer.verdict(for: distribution), .pass)
    }

    func testZone3LeakageBoundaryAt10PercentWarns() {
        let distribution = distributionWithZone3Ratio(0.10)
        XCTAssertEqual(Zone3LeakageAnalyzer.verdict(for: distribution), .warning)
    }

    func testZone3LeakageBoundaryAt20PercentStillWarns() {
        let distribution = distributionWithZone3Ratio(0.20)
        XCTAssertEqual(Zone3LeakageAnalyzer.verdict(for: distribution), .warning)
    }

    func testZone3LeakageBoundaryAbove20PercentFails() {
        let distribution = distributionWithZone3Ratio(0.201)
        XCTAssertEqual(Zone3LeakageAnalyzer.verdict(for: distribution), .fail)
    }

    func testZone3LeakageBoundaryLabelsNearThresholds() {
        XCTAssertNil(Zone3LeakageAnalyzer.boundaryLabel(for: distributionWithZone3Ratio(0.05)))
        XCTAssertTrue(Zone3LeakageAnalyzer.boundaryLabel(for: distributionWithZone3Ratio(0.09))?.contains("接近 10%") == true)
        XCTAssertTrue(Zone3LeakageAnalyzer.boundaryLabel(for: distributionWithZone3Ratio(0.101))?.contains("剛超過 10%") == true)
        XCTAssertTrue(Zone3LeakageAnalyzer.boundaryLabel(for: distributionWithZone3Ratio(0.19))?.contains("接近 20%") == true)
        XCTAssertTrue(Zone3LeakageAnalyzer.boundaryLabel(for: distributionWithZone3Ratio(0.21))?.contains("剛超過 20%") == true)
    }

    func testDriftBoundaryAt4Point9PercentPasses() {
        let samples = driftSamples(firstHalfBPM: 100, secondHalfBPM: 104.9)
        XCTAssertNotNil(HeartRateDriftAnalyzer.driftRatio(for: samples))
        XCTAssertEqual(HeartRateDriftAnalyzer.verdict(for: samples), .pass)
    }

    func testDriftBoundaryAt5PercentWarns() {
        let samples = driftSamples(firstHalfBPM: 100, secondHalfBPM: 105)
        XCTAssertNotNil(HeartRateDriftAnalyzer.driftRatio(for: samples))
        XCTAssertEqual(HeartRateDriftAnalyzer.verdict(for: samples), .warning)
    }

    func testDriftBoundaryAt8PercentStillWarns() {
        let samples = driftSamples(firstHalfBPM: 100, secondHalfBPM: 108)
        XCTAssertNotNil(HeartRateDriftAnalyzer.driftRatio(for: samples))
        XCTAssertEqual(HeartRateDriftAnalyzer.verdict(for: samples), .warning)
    }

    func testDriftBoundaryAbove8PercentFails() {
        let samples = driftSamples(firstHalfBPM: 100, secondHalfBPM: 108.1)
        XCTAssertNotNil(HeartRateDriftAnalyzer.driftRatio(for: samples))
        XCTAssertEqual(HeartRateDriftAnalyzer.verdict(for: samples), .fail)
    }

    func testDriftBoundaryLabelsNearThresholds() {
        XCTAssertNil(HeartRateDriftAnalyzer.boundaryLabel(for: 0.03))
        XCTAssertTrue(HeartRateDriftAnalyzer.boundaryLabel(for: 0.049)?.contains("接近 5%") == true)
        XCTAssertTrue(HeartRateDriftAnalyzer.boundaryLabel(for: 0.052)?.contains("剛超過 5%") == true)
        XCTAssertTrue(HeartRateDriftAnalyzer.boundaryLabel(for: 0.079)?.contains("接近 8%") == true)
        XCTAssertTrue(HeartRateDriftAnalyzer.boundaryLabel(for: 0.082)?.contains("剛超過 8%") == true)
    }

    func testZone2AnalyzerIncludesNearThresholdLabelsInReasons() {
        let start = Date()
        let samples = (0..<100).map { index in
            HeartRateSample(
                timestamp: start.addingTimeInterval(Double(index) * 60),
                bpm: index < 50 ? 118 : (index < 90 ? 123 : 126)
            )
        }
        let workout = WorkoutInput(
            workoutType: .running,
            startDate: start,
            endDate: start.addingTimeInterval(99 * 60),
            heartRateSamples: samples,
            intent: .zone2
        )
        let policy = AnalysisPolicy(
            warmupExclusionSeconds: 0,
            cooldownExclusionSeconds: 0,
            minimumDurationSeconds: AnalysisPolicy.default.minimumDurationSeconds,
            minimumSampleCount: AnalysisPolicy.default.minimumSampleCount,
            abnormalSpikeDeltaBPM: AnalysisPolicy.default.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: AnalysisPolicy.default.lowStabilityStdDev,
            mediumStabilityStdDev: AnalysisPolicy.default.mediumStabilityStdDev,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )

        let result = Zone2QualityAnalyzer.analyze(workout: workout, policy: policy)

        XCTAssertEqual(result.verdict, .warning)
        XCTAssertTrue(result.reasons.contains { $0.contains("剛超過 10%") })
        XCTAssertTrue(result.reasons.contains { $0.contains("接近 5%") || $0.contains("剛超過 5%") })
    }

    func testZone2ObservationAnalyzerProducesObservationOnlyOutput() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout

        let observation = Zone2ObservationAnalyzer.analyze(workout: workout)
        let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))

        XCTAssertTrue(fieldNames.contains("zoneDistribution"))
        XCTAssertTrue(fieldNames.contains("driftRatio"))
        XCTAssertTrue(fieldNames.contains("stabilityStandardDeviation"))
        XCTAssertTrue(fieldNames.contains("sampleQuality"))

        XCTAssertFalse(fieldNames.contains("verdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("trainingTendency"))
    }

    func testZone2ObservationAnalyzerReportsSparseSampleQualityWithoutTrainingJudgment() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "sparse_hr_cycling" }!
            .workout

        let observation = Zone2ObservationAnalyzer.analyze(workout: workout)

        XCTAssertEqual(observation.sampleQuality, .sparse)
        XCTAssertNil(observation.driftRatio)
        XCTAssertNil(observation.stabilityStandardDeviation)
    }

    func testZone2ObservationSnapshotFixture() throws {
        let records = buildZone2ObservationFixtureRecords()
        let fixtureURL = try zone2ObservationFixtureURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)

        if ProcessInfo.processInfo.environment["UPDATE_ZONE2_OBSERVATION_FIXTURE"] == "1" {
            try rendered.write(to: fixtureURL)
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "Zone2 observation snapshot mismatch. Use UPDATE_ZONE2_OBSERVATION_FIXTURE=1 only after intentional observation-layer changes."
        )
    }

    func testVO2ObservationAnalyzerProducesObservationOnlyOutput() {
        let workout = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let observation = VO2ObservationAnalyzer.analyze(workout: workout)
        let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))

        XCTAssertTrue(fieldNames.contains("zoneDistribution"))
        XCTAssertTrue(fieldNames.contains("highIntensityRatio"))
        XCTAssertTrue(fieldNames.contains("peakZoneRatio"))
        XCTAssertTrue(fieldNames.contains("intervalPatternHint"))
        XCTAssertTrue(fieldNames.contains("sampleQuality"))

        XCTAssertFalse(fieldNames.contains("verdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("trainingTendency"))
        XCTAssertFalse(fieldNames.contains("goalFitScore"))
    }

    func testVO2ObservationAnalyzerUsesDescriptiveIntervalPatternEnum() {
        let workout = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let observation = VO2ObservationAnalyzer.analyze(workout: workout)

        XCTAssertTrue([IntervalPatternHint.none, .possible, .repeatedPeaks].contains(observation.intervalPatternHint))
        XCTAssertNotEqual(observation.intervalPatternHint.rawValue, "goodInterval")
        XCTAssertNotEqual(observation.intervalPatternHint.rawValue, "badInterval")
    }

    func testVO2ObservationRatiosRemainPureNumericSignals() {
        let workout = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "low_intensity_intervals" }!
            .workout
        let observation = VO2ObservationAnalyzer.analyze(workout: workout)

        XCTAssertGreaterThanOrEqual(observation.highIntensityRatio, 0)
        XCTAssertLessThanOrEqual(observation.highIntensityRatio, 1)
        XCTAssertGreaterThanOrEqual(observation.peakZoneRatio, 0)
        XCTAssertLessThanOrEqual(observation.peakZoneRatio, 1)
    }

    func testPrimitiveBuilderZoneDistributionMatchesDirectComputation() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "steady_zone2_run" }!
            .workout
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout)
        let sanitized = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: .default)
        let expected = ZoneDistributionAnalyzer.analyze(samples: sanitized, zoneBounds: AnalysisPolicy.default.zoneBounds)

        XCTAssertEqual(primitives.zoneDistribution, expected)
    }

    func testPrimitiveBuilderSampleQualityMatchesZone2ObservationOutput() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "sparse_hr_cycling" }!
            .workout
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout)
        let observation = Zone2ObservationAnalyzer.analyze(workout: workout)

        XCTAssertEqual(primitives.sampleQuality, observation.sampleQuality)
    }

    func testPrimitiveBuilderDriftRatioMatchesZone2ObservationOutput() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "leaky_zone2_run" }!
            .workout
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout)
        let observation = Zone2ObservationAnalyzer.analyze(workout: workout)

        XCTAssertEqual(primitives.driftRatio, observation.driftRatio)
    }

    func testPrimitiveBuilderVO2RatiosBounded() {
        let workout = SampleWorkoutCases
            .vo2IntervalValidationCases()
            .first { $0.name == "solid_vo2_max_intervals" }!
            .workout
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout)

        XCTAssertGreaterThanOrEqual(primitives.highIntensityRatio, 0)
        XCTAssertLessThanOrEqual(primitives.highIntensityRatio, 1)
        XCTAssertGreaterThanOrEqual(primitives.peakZoneRatio, 0)
        XCTAssertLessThanOrEqual(primitives.peakZoneRatio, 1)
    }

    func testObservationAnalyzersDoNotDirectlyComputeDistributionOrDrift() throws {
        let analyzersPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("ZoneTruthCore")
            .appendingPathComponent("Analyzers.swift")
        let source = try String(contentsOf: analyzersPath, encoding: .utf8)

        let zone2Block = extractSourceBlock(source: source, marker: "public enum Zone2ObservationAnalyzer")
        let vo2Block = extractSourceBlock(source: source, marker: "public enum VO2ObservationAnalyzer")

        for block in [zone2Block, vo2Block] {
            XCTAssertFalse(block.contains("ZoneDistributionAnalyzer.analyze("))
            XCTAssertFalse(block.contains("HeartRateDriftAnalyzer.driftRatio("))
            XCTAssertFalse(block.contains("HeartRateStabilityAnalyzer.standardDeviation("))
        }
    }

    func testVO2ObservationSnapshotFixture() throws {
        let records = buildVO2ObservationFixtureRecords()
        let fixtureURL = try vo2ObservationFixtureURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)

        if ProcessInfo.processInfo.environment["UPDATE_VO2_OBSERVATION_FIXTURE"] == "1" {
            try rendered.write(to: fixtureURL)
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "VO2 observation snapshot mismatch. Use UPDATE_VO2_OBSERVATION_FIXTURE=1 only after intentional observation-layer changes."
        )
    }

    func testStrengthObservationAnalyzerProducesObservationOnlyOutput() {
        let workout = SampleWorkoutCases
            .strengthValidationCases()
            .first { $0.name == "traditional_strength_training" }!
            .workout
        let observation = StrengthObservationAnalyzer.analyze(workout: workout)
        let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))

        XCTAssertTrue(fieldNames.contains("avgHeartRate"))
        XCTAssertTrue(fieldNames.contains("highHrSustainedRatio"))
        XCTAssertTrue(fieldNames.contains("recoveryDropHint"))
        XCTAssertTrue(fieldNames.contains("sampleQuality"))

        XCTAssertFalse(fieldNames.contains("verdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("trainingTendency"))
        XCTAssertFalse(fieldNames.contains("goalFitScore"))
    }

    func testStrengthObservationSnapshotFixture() throws {
        let records = buildStrengthObservationFixtureRecords()
        let fixtureURL = try strengthObservationFixtureURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)

        if ProcessInfo.processInfo.environment["UPDATE_STRENGTH_OBSERVATION_FIXTURE"] == "1" {
            try rendered.write(to: fixtureURL)
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "Strength observation snapshot mismatch. Use UPDATE_STRENGTH_OBSERVATION_FIXTURE=1 only after intentional observation-layer changes."
        )
    }

    func testActivityObservationAnalyzerProducesObservationOnlyOutput() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "badminton_activity_review" }!
            .workout
        let observation = ActivityObservationAnalyzer.analyze(workout: workout)
        let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))

        XCTAssertTrue(fieldNames.contains("zoneDistribution"))
        XCTAssertTrue(fieldNames.contains("movementType"))
        XCTAssertTrue(fieldNames.contains("duration"))
        XCTAssertTrue(fieldNames.contains("sampleQuality"))

        XCTAssertFalse(fieldNames.contains("verdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("trainingTendency"))
        XCTAssertFalse(fieldNames.contains("goalFitScore"))
    }

    func testActivityObservationSnapshotFixture() throws {
        let records = buildActivityObservationFixtureRecords()
        let fixtureURL = try activityObservationFixtureURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)

        if ProcessInfo.processInfo.environment["UPDATE_ACTIVITY_OBSERVATION_FIXTURE"] == "1" {
            try rendered.write(to: fixtureURL)
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "Activity observation snapshot mismatch. Use UPDATE_ACTIVITY_OBSERVATION_FIXTURE=1 only after intentional observation-layer changes."
        )
    }

    func testObservationRegistryCoversAllIntentsAndFixtures() {
        let registry = observationRegistryEntries()
        XCTAssertEqual(Set(registry.map(\.intent)), Set(TrainingIntent.allCases))

        let fixturesDir = fixturesDirectoryURL()
        for entry in registry {
            let fixture = fixturesDir.appendingPathComponent(entry.fixtureFile, isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path), "Missing fixture: \(entry.fixtureFile)")
            XCTAssertFalse(entry.analyzerName.isEmpty)
            XCTAssertFalse(entry.updateFlag.isEmpty)
        }
    }

    func testObservationRegistryUpdateFlagsAreReferencedInSnapshotTests() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        for entry in observationRegistryEntries() {
            XCTAssertTrue(
                source.contains(entry.updateFlag),
                "Snapshot tests should reference update flag \(entry.updateFlag)"
            )
        }
    }

    func testAllObservationOutputsExcludeUserFacingSemanticFields() {
        let zone2Workout = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "steady_zone2_run" }!.workout
        let vo2Workout = SampleWorkoutCases.vo2IntervalValidationCases().first { $0.name == "solid_vo2_max_intervals" }!.workout
        let strengthWorkout = SampleWorkoutCases.strengthValidationCases().first { $0.name == "traditional_strength_training" }!.workout
        let activityWorkout = SampleWorkoutCases.zone2ValidationCases().first { $0.name == "badminton_activity_review" }!.workout

        let observations: [Any] = [
            Zone2ObservationAnalyzer.analyze(workout: zone2Workout),
            VO2ObservationAnalyzer.analyze(workout: vo2Workout),
            StrengthObservationAnalyzer.analyze(workout: strengthWorkout),
            ActivityObservationAnalyzer.analyze(workout: activityWorkout),
        ]

        let forbidden = ["verdict", "reasons", "recommendations", "trainingTendency", "goalFitScore", "nextAction"]
        for observation in observations {
            let fieldNames = Set(Mirror(reflecting: observation).children.compactMap(\.label))
            for key in forbidden {
                XCTAssertFalse(fieldNames.contains(key), "Observation output contains forbidden semantic field: \(key)")
            }
        }
    }

    private func makeWorkout(intent: TrainingIntent, samples: [Double]) -> WorkoutInput {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(TimeInterval((samples.count - 1) * 60))
        return WorkoutInput(
            workoutType: .running,
            startDate: start,
            endDate: end,
            heartRateSamples: makeSamples(samples),
            intent: intent
        )
    }

    private func makeSwimmingWorkout(
        samples: [Double],
        intent: TrainingIntent,
        duration: TimeInterval? = nil
    ) -> WorkoutInput {
        let start = Date(timeIntervalSince1970: 0)
        let resolvedDuration = duration ?? TimeInterval((samples.count - 1) * 60)
        return WorkoutInput(
            workoutType: .swimming,
            startDate: start,
            endDate: start.addingTimeInterval(resolvedDuration),
            heartRateSamples: makeSamples(samples),
            intent: intent
        )
    }

    private func makeSamples(_ samples: [Double]) -> [HeartRateSample] {
        let start = Date(timeIntervalSince1970: 0)
        return samples.enumerated().map { index, bpm in
            HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(index * 60)), bpm: bpm)
        }
    }

    private func distributionWithZone3Ratio(_ zone3Ratio: Double) -> ZoneDistribution {
        let remaining = max(0.0, 1.0 - zone3Ratio)
        let counts: [TrainingZone: Int] = [
            .zone1: 0,
            .zone2: Int(remaining * 100),
            .zone3: Int(zone3Ratio * 100),
            .zone4: 0,
            .zone5: 0
        ]
        let ratios: [TrainingZone: Double] = [
            .zone1: 0.0,
            .zone2: remaining,
            .zone3: zone3Ratio,
            .zone4: 0.0,
            .zone5: 0.0
        ]
        return ZoneDistribution(counts: counts, ratios: ratios)
    }

    private func driftSamples(firstHalfBPM: Double, secondHalfBPM: Double) -> [HeartRateSample] {
        makeSamples([firstHalfBPM, firstHalfBPM, secondHalfBPM, secondHalfBPM])
    }

    private func buildZone2ObservationFixtureRecords() -> [Zone2ObservationFixtureRecord] {
        let ids = ["steady_zone2_run", "leaky_zone2_run", "sparse_hr_cycling"]
        return ids.compactMap { id in
            guard let workout = SampleWorkoutCases.zone2ValidationCases().first(where: { $0.name == id })?.workout else {
                return nil
            }
            let observation = Zone2ObservationAnalyzer.analyze(workout: workout)
            return Zone2ObservationFixtureRecord(
                id: id,
                observation: Zone2ObservationSnapshot(
                    zoneDistribution: snapshot(of: observation.zoneDistribution),
                    driftRatio: observation.driftRatio,
                    stabilityStandardDeviation: observation.stabilityStandardDeviation,
                    sampleQuality: observation.sampleQuality.rawValue
                )
            )
        }
    }

    private func snapshot(of distribution: ZoneDistribution) -> ZoneDistributionSnapshot {
        let counts = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map {
            ("zone\($0.rawValue)", distribution.counts[$0, default: 0])
        })
        let ratios = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.compactMap { zone -> (String, Double)? in
            guard let ratio = distribution.ratios[zone] else { return nil }
            return ("zone\(zone.rawValue)", ratio)
        })
        return ZoneDistributionSnapshot(counts: counts, ratios: ratios)
    }

    private func zone2ObservationFixtureURL() throws -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testFileDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("zone2_observation_snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture file not found at \(url.path)")
        }
        return url
    }

    private func buildVO2ObservationFixtureRecords() -> [VO2ObservationFixtureRecord] {
        let ids = ["solid_vo2_max_intervals", "low_intensity_intervals"]
        return ids.compactMap { id in
            guard let workout = SampleWorkoutCases.vo2IntervalValidationCases().first(where: { $0.name == id })?.workout else {
                return nil
            }
            let observation = VO2ObservationAnalyzer.analyze(workout: workout)
            return VO2ObservationFixtureRecord(
                id: id,
                observation: VO2ObservationSnapshot(
                    zoneDistribution: snapshot(of: observation.zoneDistribution),
                    highIntensityRatio: observation.highIntensityRatio,
                    peakZoneRatio: observation.peakZoneRatio,
                    intervalPatternHint: observation.intervalPatternHint.rawValue,
                    sampleQuality: observation.sampleQuality.rawValue
                )
            )
        }
    }

    private func vo2ObservationFixtureURL() throws -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testFileDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("vo2_observation_snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture file not found at \(url.path)")
        }
        return url
    }

    private func buildStrengthObservationFixtureRecords() -> [StrengthObservationFixtureRecord] {
        let ids = ["traditional_strength_training", "metabolic_strength_circuit"]
        return ids.compactMap { id in
            guard let workout = SampleWorkoutCases.strengthValidationCases().first(where: { $0.name == id })?.workout else {
                return nil
            }
            let observation = StrengthObservationAnalyzer.analyze(workout: workout)
            return StrengthObservationFixtureRecord(
                id: id,
                observation: StrengthObservationSnapshot(
                    avgHeartRate: observation.avgHeartRate,
                    highHrSustainedRatio: observation.highHrSustainedRatio,
                    recoveryDropHint: observation.recoveryDropHint.rawValue,
                    sampleQuality: observation.sampleQuality.rawValue
                )
            )
        }
    }

    private func strengthObservationFixtureURL() throws -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testFileDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("strength_observation_snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture file not found at \(url.path)")
        }
        return url
    }

    private func buildActivityObservationFixtureRecords() -> [ActivityObservationFixtureRecord] {
        let ids = ["badminton_activity_review"]
        return ids.compactMap { id in
            guard let workout = SampleWorkoutCases.zone2ValidationCases().first(where: { $0.name == id })?.workout else {
                return nil
            }
            let observation = ActivityObservationAnalyzer.analyze(workout: workout)
            return ActivityObservationFixtureRecord(
                id: id,
                observation: ActivityObservationSnapshot(
                    zoneDistribution: snapshot(of: observation.zoneDistribution),
                    movementType: observation.movementType.rawValue,
                    duration: observation.duration,
                    sampleQuality: observation.sampleQuality.rawValue
                )
            )
        }
    }

    private func activityObservationFixtureURL() throws -> URL {
        let url = fixturesDirectoryURL()
            .appendingPathComponent("activity_observation_snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture file not found at \(url.path)")
        }
        return url
    }

    private func fixturesDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func observationRegistryEntries() -> [ObservationRegistryEntry] {
        [
            ObservationRegistryEntry(
                intent: .zone2,
                analyzerName: "Zone2ObservationAnalyzer",
                fixtureFile: "zone2_observation_snapshot.json",
                updateFlag: "UPDATE_ZONE2_OBSERVATION_FIXTURE"
            ),
            ObservationRegistryEntry(
                intent: .vo2Interval,
                analyzerName: "VO2ObservationAnalyzer",
                fixtureFile: "vo2_observation_snapshot.json",
                updateFlag: "UPDATE_VO2_OBSERVATION_FIXTURE"
            ),
            ObservationRegistryEntry(
                intent: .strength,
                analyzerName: "StrengthObservationAnalyzer",
                fixtureFile: "strength_observation_snapshot.json",
                updateFlag: "UPDATE_STRENGTH_OBSERVATION_FIXTURE"
            ),
            ObservationRegistryEntry(
                intent: .activityReview,
                analyzerName: "ActivityObservationAnalyzer",
                fixtureFile: "activity_observation_snapshot.json",
                updateFlag: "UPDATE_ACTIVITY_OBSERVATION_FIXTURE"
            )
        ]
    }

    private func sprint3ClassificationPolicy(minimumSampleCount: Int = 1) -> AnalysisPolicy {
        AnalysisPolicy(
            warmupExclusionSeconds: 0,
            cooldownExclusionSeconds: 0,
            minimumDurationSeconds: 20 * 60,
            minimumSampleCount: minimumSampleCount,
            abnormalSpikeDeltaBPM: AnalysisPolicy.default.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: AnalysisPolicy.default.lowStabilityStdDev,
            mediumStabilityStdDev: AnalysisPolicy.default.mediumStabilityStdDev,
            zoneBounds: AnalysisPolicy.default.zoneBounds
        )
    }

    private func sampleClassification(primaryMode: TrainingMode) -> TrainingClassification {
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
                    explanation: "測試用分類快照。"
                )
            ],
            debug: TrainingClassificationDebug(
                classificationVersion: "test",
                usedPersonalizedZones: false
            )
        )
    }

    func testInferenceProvenanceFactoryProducesFailClosedWeeklyContract() {
        let provenance = InferenceProvenanceFactory.weekly(
            strength: .bounded,
            derivedFrom: [.workoutCount, .highIntensityDays],
            workoutCount: 4,
            hrvSampledWorkoutCount: 0
        )

        XCTAssertEqual(provenance.authorityCeiling, .nonInterventional)
        XCTAssertEqual(provenance.inferenceType, .boundedSynthesis)
        XCTAssertTrue(provenance.missingEvidence.contains(.sleep))
        XCTAssertTrue(provenance.missingEvidence.contains(.hrv))
        XCTAssertTrue(provenance.isValidFailClosed(strength: .bounded))
    }

    func testBoundedInferenceProvenanceFailsWithoutMissingEvidence() {
        let invalid = InferenceProvenance(
            inferenceType: .boundedSynthesis,
            derivedFrom: [.workoutCount],
            missingEvidence: [],
            authorityCeiling: .nonInterventional
        )
        XCTAssertFalse(invalid.isValidFailClosed(strength: .bounded))
    }

    private func extractSourceBlock(source: String, marker: String) -> String {
        guard let markerRange = source.range(of: marker) else { return "" }
        let tail = source[markerRange.lowerBound...]
        guard let nextEnumRange = tail.dropFirst(marker.count).range(of: "public enum ") else {
            return String(tail)
        }
        return String(tail[..<nextEnumRange.lowerBound])
    }
}
