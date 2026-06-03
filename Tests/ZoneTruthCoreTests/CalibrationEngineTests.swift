import XCTest
@testable import ZoneTruthCore

final class CalibrationEngineTests: XCTestCase {
    func testNoSuggestionWithInsufficientData() {
        let policy = AnalysisPolicy.default
        let analyses: [(WorkoutInput, AnalysisResult)] = [
            (createWorkout(drift: 0.01), createResult(drift: 0.01, verdict: .pass)),
            (createWorkout(drift: 0.01), createResult(drift: 0.01, verdict: .pass))
        ]
        
        let suggestion = CalibrationEngine.analyzeDriftTrend(analyses: analyses, currentPolicy: policy)
        XCTAssertNil(suggestion)
    }
    
    func testSuggestRaisingUpperBoundForLowDrift() {
        let policy = AnalysisPolicy.default
        let analyses: [(WorkoutInput, AnalysisResult)] = [
            (createWorkout(drift: 0.01), createResult(drift: 0.01, verdict: .pass)),
            (createWorkout(drift: 0.015), createResult(drift: 0.015, verdict: .pass)),
            (createWorkout(drift: 0.01), createResult(drift: 0.01, verdict: .pass))
        ]
        
        let suggestion = CalibrationEngine.analyzeDriftTrend(analyses: analyses, currentPolicy: policy)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2UpperBound, policy.zoneBounds.zone2UpperBound + 3)
        XCTAssertEqual(suggestion?.source, .driftTrend)
        XCTAssertTrue(suggestion?.reason.contains("心率飄移持續偏低") == true)
    }
    
    func testSuggestLoweringUpperBoundForHighDrift() {
        let policy = AnalysisPolicy.default
        let analyses: [(WorkoutInput, AnalysisResult)] = [
            (createWorkout(drift: 0.07), createResult(drift: 0.07, verdict: .pass)),
            (createWorkout(drift: 0.065), createResult(drift: 0.065, verdict: .pass)),
            (createWorkout(drift: 0.08), createResult(drift: 0.08, verdict: .pass))
        ]
        
        let suggestion = CalibrationEngine.analyzeDriftTrend(analyses: analyses, currentPolicy: policy)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2UpperBound, policy.zoneBounds.zone2UpperBound - 3)
        XCTAssertEqual(suggestion?.source, .driftTrend)
        XCTAssertTrue(suggestion?.reason.contains("心率飄移持續偏高") == true)
    }

    func testSuggestZoneBoundsFromRestingHeartRateUsesDefaultAnchors() {
        let suggestion = CalibrationEngine.suggestZoneBounds(
            restingHeartRate: 55,
            currentPolicy: .default
        )

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2LowerBound, 110)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2UpperBound, 125)
        XCTAssertEqual(suggestion?.suggestedBounds.zone4Threshold, 141)
        XCTAssertEqual(suggestion?.suggestedBounds.zone5Threshold, 156)
        XCTAssertEqual(suggestion?.source, .restingHeartRateHeuristic)
        XCTAssertEqual(suggestion?.source.displayLabel, "來源：Resting HR 起始建議")
        XCTAssertEqual(suggestion?.source.verificationLabel, "非驗證閾值")
        XCTAssertTrue(suggestion?.reason.contains("Resting HR") == true)
    }

    func testSuggestZoneBoundsFromRestingHeartRateUsesCustomOffsets() {
        let suggestion = CalibrationEngine.suggestZoneBounds(
            restingHeartRate: 58,
            currentPolicy: .default,
            offsets: RestingHeartRateSuggestionOffsets(lowerOffset: 50, upperOffset: 64)
        )

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2LowerBound, 108)
        XCTAssertEqual(suggestion?.suggestedBounds.zone2UpperBound, 122)
        XCTAssertTrue(suggestion?.reason.contains("+50/+64") == true)
    }

    func testSuggestZoneBoundsFromRestingHeartRateRejectsOutOfRangeInput() {
        XCTAssertNil(CalibrationEngine.suggestZoneBounds(restingHeartRate: 20, currentPolicy: .default))
        XCTAssertNil(CalibrationEngine.suggestZoneBounds(restingHeartRate: 120, currentPolicy: .default))
    }
    
    // Helpers
    private func createWorkout(drift: Double) -> WorkoutInput {
        return WorkoutInput(
            workoutType: .running,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            heartRateSamples: [],
            intent: .zone2
        )
    }
    
    private func createResult(drift: Double, verdict: AnalysisVerdict) -> AnalysisResult {
        return AnalysisResult(
            verdict: verdict,
            confidence: 0.9,
            reasons: [],
            recommendations: [],
            zoneDistribution: ZoneDistribution(counts: [:], ratios: [:]),
            stabilityStandardDeviation: 2.0,
            driftRatio: drift
        )
    }
}
