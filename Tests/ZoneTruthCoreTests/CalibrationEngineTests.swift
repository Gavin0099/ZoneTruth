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
        XCTAssertEqual(suggestion?.source.displayLabel, "依據：靜息心率 + 產品預設偏移規則")
        XCTAssertEqual(suggestion?.source.verificationLabel, "初步估算，尚未驗證")
        XCTAssertTrue(suggestion?.reason.contains("靜息心率") == true)
        XCTAssertTrue(suggestion?.reason.contains("初步 Zone 2 參考範圍") == true)
        XCTAssertTrue(suggestion?.reason.contains("尚未經足夠訓練資料驗證") == true)
        XCTAssertFalse(suggestion?.reason.contains("個人化 Zone 2 起始建議") == true)
        XCTAssertFalse(suggestion?.reason.contains("校正完成") == true)
        XCTAssertFalse(suggestion?.reason.contains("已驗證 Zone 2") == true)
        XCTAssertFalse(suggestion?.reason.contains("個人化閾值已確立") == true)
        XCTAssertEqual(suggestion?.confidence, 0.55)
        XCTAssertEqual(suggestion?.zone2RangeMatchesCurrent, true)
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
        XCTAssertTrue(suggestion?.reason.contains("產品預設偏移規則") == true)
        XCTAssertFalse(suggestion?.reason.contains("+50/+64") == true)
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
