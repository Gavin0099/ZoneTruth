import Foundation
import XCTest
@testable import ZoneTruthCore

final class WeeklyLoadPolicyTests: XCTestCase {

    // 2026-05-18 is a Monday
    private var weekMonday: Date { makeUTCDate(year: 2026, month: 5, day: 18) }

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var weekEndAsOf: Date { weekMonday + (7 * 86400) - 1 }

    // MARK: - Forbidden language guard

    func testPolicyNeverOutputsForbiddenLanguageAcrossAllConcernLevels() {
        let monday = weekMonday
        let cal = utcCalendar

        let scenarios: [WeeklyWorkoutSummary] = [
            // low
            buildSummary(workouts: [
                makeWorkout(.zone2, monday,             3600),
                makeWorkout(.zone2, monday + 2 * 86400, 3600),
                makeWorkout(.strength, monday + 4 * 86400, 2700),
            ], monday: monday, cal: cal),
            // moderate – 2 high intensity days
            buildSummary(workouts: [
                makeWorkout(.vo2Interval, monday, 2700),
                makeWorkout(.vo2Interval, monday + 2 * 86400, 2700),
                makeWorkout(.zone2, monday + 4 * 86400, 3600),
            ], monday: monday, cal: cal),
            // elevated – no rest days (7 workouts)
            buildSummary(workouts: (0..<7).map { makeWorkout(.zone2, monday + TimeInterval($0) * 86400, 3600) },
                         monday: monday, cal: cal),
            // high – 3 vo2 days, 1 rest day
            buildSummary(workouts: [
                makeWorkout(.vo2Interval, monday,             2700),
                makeWorkout(.vo2Interval, monday + 86400,     2700),
                makeWorkout(.vo2Interval, monday + 2 * 86400, 2700),
                makeWorkout(.zone2,       monday + 3 * 86400, 3600),
                makeWorkout(.zone2,       monday + 4 * 86400, 3600),
                makeWorkout(.strength,    monday + 5 * 86400, 2700),
            ], monday: monday, cal: cal),
        ]

        let forbidden = ["過度訓練", "overtraining", "身體恢復不良", "休息不足", "not enough rest"]

        for summary in scenarios {
            let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)
            let allText = (policy.keyFindings + [policy.nextAction]).joined(separator: " ")
            for term in forbidden {
                XCTAssertFalse(
                    allText.contains(term),
                    "Policy output contains forbidden term '\(term)' for concern=\(policy.recoveryConcernLevel.rawValue)"
                )
            }
        }
    }

    // MARK: - Confidence

    func testSparseDataWeekHasReducedConfidence() {
        // Workouts with only 3 HR samples each → sparse → zoneDistribution total = 0
        let monday = weekMonday
        let cal = utcCalendar
        let workouts = [
            makeWorkout(.zone2, monday,             3600, sampleCount: 3),
            makeWorkout(.zone2, monday + 2 * 86400, 3600, sampleCount: 3),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)

        XCTAssertLessThan(policy.confidence, 0.6)
        XCTAssertEqual(policy.recoveryConcernLevel, .low)  // sparse data must not inflate concern
    }

    // MARK: - No rest days

    func testNoRestDaysIsElevatedWithConservativeLanguage() {
        let monday = weekMonday
        let cal = utcCalendar
        let workouts = (0..<7).map { day in
            makeWorkout(.zone2, monday + TimeInterval(day) * 86400, 3600)
        }
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)

        XCTAssertEqual(policy.recoveryConcernLevel, .elevated)

        let allText = (policy.keyFindings + [policy.nextAction]).joined(separator: " ")
        XCTAssertFalse(allText.contains("休息不足"))
        XCTAssertFalse(allText.contains("過度訓練"))
        // Should describe the situation factually
        XCTAssertTrue(policy.keyFindings.contains { $0.contains("7") || $0.contains("0") })
    }

    // MARK: - High intensity cluster

    func testHighIntensityClusterIsHigh() {
        // 3 VO2 days + 2 zone2 + 1 strength = 6 training days, 1 rest day
        let monday = weekMonday
        let cal = utcCalendar
        let workouts = [
            makeWorkout(.vo2Interval, monday,             2700),
            makeWorkout(.vo2Interval, monday + 86400,     2700),
            makeWorkout(.vo2Interval, monday + 2 * 86400, 2700),
            makeWorkout(.zone2,       monday + 3 * 86400, 3600),
            makeWorkout(.zone2,       monday + 4 * 86400, 3600),
            makeWorkout(.strength,    monday + 5 * 86400, 2700),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)

        XCTAssertEqual(policy.recoveryConcernLevel, .high)
        XCTAssertEqual(policy.loadTendency, .highIntensityFocused)
        // keyFindings should note high-intensity days
        XCTAssertTrue(policy.keyFindings.contains { $0.contains("VO2") || $0.contains("高強度") })
    }

    func testSingleVO2WorkoutIsHighIntensityFocusedNotUnderloaded() {
        let monday = weekMonday
        let cal = utcCalendar
        let workouts = [
            makeWorkout(.vo2Interval, monday, 2700),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)

        XCTAssertEqual(policy.loadTendency, .highIntensityFocused)
    }

    // MARK: - Balanced week

    func testBalancedWeekIsLow() {
        // 2 zone2 + 1 vo2 + 1 strength, 3 rest days
        let monday = weekMonday
        let cal = utcCalendar
        let workouts = [
            makeWorkout(.zone2,       monday,             3600),
            makeWorkout(.vo2Interval, monday + 86400,     2700),
            makeWorkout(.strength,    monday + 2 * 86400, 2700),
            makeWorkout(.zone2,       monday + 4 * 86400, 3600),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)

        XCTAssertEqual(policy.recoveryConcernLevel, .low)
        XCTAssertGreaterThan(policy.confidence, 0.7)
        XCTAssertFalse(policy.nextAction.isEmpty)
    }

    // MARK: - Struct field guard

    func testWeeklyLoadPolicyExcludesForbiddenSemanticFields() {
        let monday = weekMonday
        let cal = utcCalendar
        let summary = WeeklyObservationBuilder.build(workouts: [], weekStart: monday, calendar: cal, asOf: weekEndAsOf)
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)
        let fieldNames = Set(Mirror(reflecting: policy).children.compactMap(\.label))

        XCTAssertFalse(fieldNames.contains("verdict"))
        XCTAssertFalse(fieldNames.contains("reasons"))
        XCTAssertFalse(fieldNames.contains("recommendations"))
        XCTAssertFalse(fieldNames.contains("tooMuch"))
        XCTAssertFalse(fieldNames.contains("notEnoughRest"))
        XCTAssertFalse(fieldNames.contains("recoveryRisk"))

        XCTAssertTrue(fieldNames.contains("recoveryConcernLevel"))
        XCTAssertTrue(fieldNames.contains("loadTendency"))
        XCTAssertTrue(fieldNames.contains("keyFindings"))
        XCTAssertTrue(fieldNames.contains("nextAction"))
        XCTAssertTrue(fieldNames.contains("confidence"))
    }

    // MARK: - Helpers

    private func buildSummary(workouts: [WorkoutInput], monday: Date, cal: Calendar) -> WeeklyWorkoutSummary {
        WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
    }

    private func makeWorkout(
        _ intent: TrainingIntent,
        _ startDate: Date,
        _ duration: TimeInterval,
        sampleCount: Int = 30
    ) -> WorkoutInput {
        let endDate = startDate.addingTimeInterval(duration)
        let bpm: Double
        switch intent {
        case .zone2:          bpm = 118
        case .vo2Interval:    bpm = 150
        case .strength:       bpm = 100
        case .activityReview: bpm = 130
        }
        let spacing = sampleCount > 1 ? duration / Double(sampleCount - 1) : 0
        let samples = (0..<sampleCount).map { i in
            HeartRateSample(timestamp: startDate.addingTimeInterval(Double(i) * spacing), bpm: bpm)
        }
        return WorkoutInput(workoutType: .running, startDate: startDate, endDate: endDate, heartRateSamples: samples, intent: intent)
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0))!
    }
}
