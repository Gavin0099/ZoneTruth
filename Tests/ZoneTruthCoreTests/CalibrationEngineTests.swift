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
        XCTAssertTrue(suggestion?.reason.contains("low heart rate drift") == true)
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
        XCTAssertTrue(suggestion?.reason.contains("high heart rate drift") == true)
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
