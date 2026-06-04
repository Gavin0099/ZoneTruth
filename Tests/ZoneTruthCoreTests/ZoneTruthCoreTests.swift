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
        XCTAssertFalse(scalarVO2?.claim.allowedTerms.contains("lab-equivalent") == true)
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
