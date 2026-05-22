import Foundation
import XCTest
@testable import ZoneTruthCore

final class GoalAlignmentEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(identifier: "UTC")
        return comps.date!
    }

    private func makeSummary(
        workoutCount: Int,
        highIntensityDays: Int = 0,
        strengthDays: Int = 0,
        restDays: Int = 0,
        z2Count: Int = 0
    ) -> WeeklyWorkoutSummary {
        let monday = makeUTCDate(year: 2026, month: 5, day: 18)
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
            consecutiveTrainingDays: workoutCount
        )
    }

    // MARK: - insufficientEvidence guard

    func testSingleWorkoutAlwaysInsufficientEvidence() {
        let summary = makeSummary(workoutCount: 1)
        for goal in UserTrainingGoal.allCases {
            XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: goal, summary: summary), .insufficientEvidence,
                "goal \(goal.rawValue) should return insufficientEvidence with only 1 workout")
        }
    }

    func testZeroWorkoutsAlwaysInsufficientEvidence() {
        let summary = makeSummary(workoutCount: 0)
        for goal in UserTrainingGoal.allCases {
            XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: goal, summary: summary), .insufficientEvidence)
        }
    }

    // MARK: - aerobicBase

    func testAerobicBaseAlignedOnHighZ2RatioLowIntensity() {
        let summary = makeSummary(workoutCount: 4, highIntensityDays: 1, z2Count: 3)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .aerobicBase, summary: summary), .aligned)
    }

    func testAerobicBaseDivergentOnHighIntensity() {
        let summary = makeSummary(workoutCount: 4, highIntensityDays: 3, z2Count: 1)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .aerobicBase, summary: summary), .divergent)
    }

    func testAerobicBasePartiallyAlignedOnLowZ2LowIntensity() {
        let summary = makeSummary(workoutCount: 2, highIntensityDays: 0, z2Count: 1)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .aerobicBase, summary: summary), .partiallyAligned)
    }

    // MARK: - strengthFocus

    func testStrengthFocusAlignedOnMultipleStrengthDays() {
        let summary = makeSummary(workoutCount: 4, strengthDays: 3)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .strengthFocus, summary: summary), .aligned)
    }

    func testStrengthFocusDivergentOnZeroStrengthDays() {
        let summary = makeSummary(workoutCount: 3, strengthDays: 0, z2Count: 3)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .strengthFocus, summary: summary), .divergent)
    }

    func testStrengthFocusPartiallyAlignedOnOneStrengthDay() {
        let summary = makeSummary(workoutCount: 3, strengthDays: 1)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .strengthFocus, summary: summary), .partiallyAligned)
    }

    // MARK: - fatLossRecomp

    func testFatLossRecompAlignedOnMixedWeek() {
        let summary = makeSummary(workoutCount: 4, highIntensityDays: 1, strengthDays: 1, restDays: 3)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .fatLossRecomp, summary: summary), .aligned)
    }

    func testFatLossRecompDivergentOnInactiveWeek() {
        // restDays: 6 exceeds the partiallyAligned ceiling (restDays <= 5)
        let summary = makeSummary(workoutCount: 2, highIntensityDays: 0, strengthDays: 0, restDays: 6)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .fatLossRecomp, summary: summary), .divergent)
    }

    // MARK: - performancePeak

    func testPerformancePeakAlignedOnHighVolumeWithIntensity() {
        let summary = makeSummary(workoutCount: 5, highIntensityDays: 2, restDays: 2)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .performancePeak, summary: summary), .aligned)
    }

    func testPerformancePeakDivergentOnHighRestLowVolume() {
        let summary = makeSummary(workoutCount: 2, restDays: 5)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .performancePeak, summary: summary), .divergent)
    }

    // MARK: - activeRecovery

    func testActiveRecoveryAlignedOnRestHeavyWeek() {
        let summary = makeSummary(workoutCount: 2, highIntensityDays: 0, restDays: 5)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .activeRecovery, summary: summary), .aligned)
    }

    func testActiveRecoveryDivergentOnHighFrequencyAndIntensity() {
        let summary = makeSummary(workoutCount: 5, highIntensityDays: 3, restDays: 2)
        XCTAssertEqual(GoalAlignmentEngine.evaluate(goal: .activeRecovery, summary: summary), .divergent)
    }

    // MARK: - Forbidden language guard

    // Goal alignment signals must never assert achievement, prediction, or causal attribution.
    // We test that GoalAlignmentSignal rawValues do not contain forbidden terms.
    func testGoalAlignmentSignalRawValuesContainNoForbiddenLanguage() {
        let forbidden = ["achieved", "will", "cause", "progress", "optimal", "必須", "最佳", "診斷", "確定"]
        for signal in [GoalAlignmentSignal.aligned, .partiallyAligned, .divergent, .insufficientEvidence] {
            for term in forbidden {
                XCTAssertFalse(signal.rawValue.lowercased().contains(term.lowercased()),
                    "GoalAlignmentSignal.\(signal.rawValue) contains forbidden term '\(term)'")
            }
        }
    }
}
