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
        XCTAssertTrue(result.reasons.contains { $0.contains("10% and 20%") || $0.contains("5% and 8%") })
    }

    func testZone2AnalyzerFailsForHeavyLeakageAndHighDrift() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "drifting_swim" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.reasons.contains { $0.contains("exceeded 20%") || $0.contains("exceeded 8%") })
    }

    func testActivityReviewReturnsDescriptivePass() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "badminton_activity_review" }!
            .workout

        let result = WorkoutIntentAnalyzer.analyze(workout)

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertTrue(result.reasons.contains { $0.contains("general activity") })
    }

    func testVO2IntervalAnalysis() {
        for testCase in SampleWorkoutCases.vo2IntervalValidationCases() {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)
            XCTAssertEqual(result.verdict, testCase.expectedVerdict, "Case \(testCase.name) failed")
        }
    }

    func testStrengthAnalysis() {
        for testCase in SampleWorkoutCases.strengthValidationCases() {
            let result = WorkoutIntentAnalyzer.analyze(testCase.workout)
            XCTAssertEqual(result.verdict, testCase.expectedVerdict, "Case \(testCase.name) failed")
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
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("too low") })
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
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("exceeded 8%") })
    }

    func testZone2AnalyzerWarnsForHighVariabilityWithGoodZones() {
        let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first { $0.name == "unstable_zone2_run" }!
            .workout

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .warning)
        XCTAssertEqual(result.zoneDistribution.ratio(for: .zone3), 0.0)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("variability was moderate") })
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.escapeSlashes = false
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

    func testVO2ObservationSnapshotFixture() throws {
        let records = buildVO2ObservationFixtureRecords()
        let fixtureURL = try vo2ObservationFixtureURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.escapeSlashes = false
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
}
