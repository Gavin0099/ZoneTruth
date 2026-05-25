import Foundation
import XCTest
@testable import ZoneTruthCore

final class WeeklySignalsCoreTests: XCTestCase {
    func testWeeklyFreshnessSignalClassifiesFreshPartialStaleMissing() {
        let weekStart = makeUTCDate(year: 2026, month: 5, day: 18)
        let now = weekStart.addingTimeInterval(6 * 86400 + 20 * 3600)

        let freshWorkouts = [makeWorkoutForFreshness(startDate: now.addingTimeInterval(-6 * 3600))]
        let partialWorkouts = [makeWorkoutForFreshness(startDate: now.addingTimeInterval(-40 * 3600))]
        let staleWorkouts = [makeWorkoutForFreshness(startDate: weekStart.addingTimeInterval(36 * 3600))]

        XCTAssertEqual(WeeklyFreshnessSignal.classify(workouts: freshWorkouts, weekStart: weekStart, now: now), .fresh)
        XCTAssertEqual(WeeklyFreshnessSignal.classify(workouts: partialWorkouts, weekStart: weekStart, now: now), .partial)
        XCTAssertEqual(WeeklyFreshnessSignal.classify(workouts: staleWorkouts, weekStart: weekStart, now: now), .stale)
        XCTAssertEqual(WeeklyFreshnessSignal.classify(workouts: [], weekStart: weekStart, now: now), .missing)
    }

    func testWeeklyConfidenceSemanticsDowngradesWithSparseHRVAndStaleFreshness() {
        let sparseHRV = WeeklyConfidenceSemantics.calibrated(
            baseConfidence: 0.85,
            freshness: .fresh,
            workoutCount: 5,
            hrvSampledWorkoutCount: 1,
            hrvCoverageRatio: 0.2
        )
        XCTAssertEqual(sparseHRV, 0.60, accuracy: 0.001)

        let stale = WeeklyConfidenceSemantics.calibrated(
            baseConfidence: 0.9,
            freshness: .stale,
            workoutCount: 5,
            hrvSampledWorkoutCount: 5,
            hrvCoverageRatio: 1.0
        )
        XCTAssertEqual(stale, 0.55, accuracy: 0.001)
    }

    func testWeeklyInferenceClassifierDowngradesForMissingAndSparseEvidence() {
        XCTAssertEqual(
            WeeklyInferenceClassifier.classify(
                confidence: 0.9,
                freshness: .missing,
                workoutCount: 0,
                elapsedDays: 7
            ),
            .unsupported
        )
        XCTAssertEqual(
            WeeklyInferenceClassifier.classify(
                confidence: 0.85,
                freshness: .fresh,
                workoutCount: 4,
                elapsedDays: 7,
                hrvSampledWorkoutCount: 0,
                hrvCoverageRatio: 0.0
            ),
            .weak
        )
        XCTAssertEqual(
            WeeklyInferenceClassifier.classify(
                confidence: 0.85,
                freshness: .fresh,
                workoutCount: 4,
                elapsedDays: 7,
                hrvSampledWorkoutCount: 4,
                hrvCoverageRatio: 1.0
            ),
            .bounded
        )
    }

    func testWeeklyAuthorityRenderingDowngradesUnderLowConfidenceAndStaleData() {
        XCTAssertEqual(WeeklyAuthorityRendering.authority(for: 0.85, freshness: .fresh), .observational)
        XCTAssertEqual(WeeklyAuthorityRendering.authority(for: 0.7, freshness: .fresh), .boundedInference)
        XCTAssertEqual(WeeklyAuthorityRendering.authority(for: 0.5, freshness: .fresh), .weakInference)
        XCTAssertEqual(WeeklyAuthorityRendering.authority(for: 0.85, freshness: .stale), .weakInference)
        XCTAssertEqual(WeeklyAuthorityRendering.authority(for: 0.85, freshness: .missing), .weakInference)
    }

    private func makeWorkoutForFreshness(startDate: Date) -> WorkoutInput {
        let duration: TimeInterval = 30 * 60
        let endDate = startDate.addingTimeInterval(duration)
        return WorkoutInput(
            workoutType: .running,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: [
                HeartRateSample(timestamp: startDate, bpm: 118),
                HeartRateSample(timestamp: endDate, bpm: 120),
            ]
        )
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0))!
    }
}
