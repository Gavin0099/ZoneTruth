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
        let workout = makeWorkout(
            intent: .zone2,
            samples: repeatingSequence(24, value: 118)
        )

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertGreaterThan(result.confidence, 0.7)
        XCTAssertFalse(result.reasons.isEmpty)
    }

    func testZone2AnalyzerWarnsForModerateLeakageAndDrift() {
        let workout = makeWorkout(
            intent: .zone2,
            samples: [116, 117, 118, 120, 121, 122, 123, 124, 126, 128, 129, 130, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]
        )

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .warning)
        XCTAssertTrue(result.reasons.contains { $0.contains("10% and 20%") || $0.contains("5% and 8%") })
    }

    func testZone2AnalyzerFailsForHeavyLeakageAndHighDrift() {
        let workout = makeWorkout(
            intent: .zone2,
            samples: [116, 117, 118, 119, 120, 121, 122, 123, 126, 128, 130, 133, 136, 138, 140, 142, 144, 145, 146, 147, 148, 149, 150, 151]
        )

        let result = Zone2QualityAnalyzer.analyze(workout: workout)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.reasons.contains { $0.contains("exceeded 20%") || $0.contains("exceeded 8%") })
    }

    func testActivityReviewReturnsDescriptivePass() {
        let workout = makeWorkout(
            intent: .activityReview,
            samples: [92, 98, 104, 110, 112, 108, 105, 101, 98, 96, 94, 92, 95, 97, 99, 101, 100, 98, 96, 95, 94, 93, 92, 91]
        )

        let result = WorkoutIntentAnalyzer.analyze(workout)

        XCTAssertEqual(result.verdict, .pass)
        XCTAssertTrue(result.reasons.contains { $0.contains("general activity") })
    }

    func testSanitizerRemovesWarmupCooldownAndSpikes() {
        let policy = AnalysisPolicy.default
        let samples = makeSamples([90, 92, 118, 119, 160, 120, 121, 122, 100])

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

    private func repeatingSequence(_ count: Int, value: Double) -> [Double] {
        Array(repeating: value, count: count)
    }
}
