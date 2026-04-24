import Foundation
import XCTest
@testable import ZoneTruthCore

final class ZoneTruthCoreTests: XCTestCase {
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

    func testValidationDatasetMatchesExpectedVerdicts() {
        for testCase in SampleWorkoutCases.zone2ValidationCases() {
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

    func testSanitizerRemovesWarmupCooldownAndSpikes() {
        let policy = AnalysisPolicy.default
        let samples = makeSamples([90, 92, 95, 100, 108, 116, 118, 160, 119, 120, 121, 118, 112, 100])

        let sanitized = HeartRateSampleSanitizer.sanitize(samples, policy: policy)

        XCTAssertFalse(sanitized.isEmpty)
        XCTAssertFalse(sanitized.contains { $0.bpm == 160 })
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
}
