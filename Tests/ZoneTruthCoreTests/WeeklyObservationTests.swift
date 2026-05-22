import Foundation
import XCTest
@testable import ZoneTruthCore

final class WeeklyObservationTests: XCTestCase {

    // 2026-05-18 is a Monday
    private var weekMonday: Date { makeUTCDate(year: 2026, month: 5, day: 18) }

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var weekEndAsOf: Date { weekMonday + (7 * 86400) - 1 }

    // MARK: - WeeklyObservationBuilder cases

    func testBalancedWeek() {
        let monday = weekMonday
        let workouts = [
            makeWorkout(intent: .zone2,       startDate: monday,                   duration: 3600),
            makeWorkout(intent: .vo2Interval, startDate: monday + 86400,           duration: 2700),
            makeWorkout(intent: .strength,    startDate: monday + 2 * 86400,       duration: 2700),
            makeWorkout(intent: .zone2,       startDate: monday + 4 * 86400,       duration: 3600),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)

        XCTAssertEqual(summary.workoutCount, 4)
        XCTAssertEqual(summary.restDays, 3)
        XCTAssertEqual(summary.highIntensityDays, 1)
        XCTAssertEqual(summary.strengthDays, 1)
        XCTAssertEqual(summary.intentDistribution[.zone2], 2)
        XCTAssertEqual(summary.intentDistribution[.vo2Interval], 1)
        XCTAssertEqual(summary.intentDistribution[.strength], 1)
        XCTAssertEqual(summary.consecutiveTrainingDays, 3) // Mon–Tue–Wed
        XCTAssertNil(summary.totalActiveCalories)
        XCTAssertEqual(summary.totalDurationMinutes, (3600 + 2700 + 2700 + 3600) / 60.0, accuracy: 0.001)
    }

    func testNoRestDays() {
        let monday = weekMonday
        let workouts = (0..<7).map { day in
            makeWorkout(intent: .zone2, startDate: monday + TimeInterval(day) * 86400, duration: 2700)
        }
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)

        XCTAssertEqual(summary.workoutCount, 7)
        XCTAssertEqual(summary.restDays, 0)
        XCTAssertEqual(summary.consecutiveTrainingDays, 7)
    }

    func testMixedIntentsWeek() {
        let monday = weekMonday
        let workouts = [
            makeWorkout(intent: .zone2,         startDate: monday,             duration: 3600),
            makeWorkout(intent: .vo2Interval,   startDate: monday + 86400,     duration: 2700),
            makeWorkout(intent: .strength,      startDate: monday + 2 * 86400, duration: 2700),
            makeWorkout(intent: .activityReview,startDate: monday + 4 * 86400, duration: 3600),
            makeWorkout(intent: .zone2,         startDate: monday + 6 * 86400, duration: 3600),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)

        XCTAssertEqual(summary.workoutCount, 5)
        XCTAssertEqual(summary.intentDistribution[.zone2], 2)
        XCTAssertEqual(summary.intentDistribution[.vo2Interval], 1)
        XCTAssertEqual(summary.intentDistribution[.strength], 1)
        XCTAssertEqual(summary.intentDistribution[.activityReview], 1)
        XCTAssertEqual(summary.highIntensityDays, 1)
        XCTAssertEqual(summary.strengthDays, 1)
        XCTAssertEqual(summary.restDays, 2)
        // Streaks: Mon–Tue–Wed = 3, Fri = 1, Sun = 1
        XCTAssertEqual(summary.consecutiveTrainingDays, 3)
    }

    func testSparseDataWeek() {
        let monday = weekMonday
        // Only 3 HR samples each — below minimumSampleCount of 20 → sparse quality → empty zone distribution
        let workouts = [
            makeWorkout(intent: .zone2, startDate: monday,             duration: 3600, sampleCount: 3),
            makeWorkout(intent: .zone2, startDate: monday + 2 * 86400, duration: 3600, sampleCount: 3),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)

        XCTAssertEqual(summary.workoutCount, 2)
        XCTAssertEqual(summary.restDays, 5)
        XCTAssertEqual(summary.consecutiveTrainingDays, 1) // Mon and Wed — not consecutive
        XCTAssertEqual(summary.zoneDistribution.counts.values.reduce(0, +), 0)
        XCTAssertEqual(summary.totalDurationMinutes, 120.0, accuracy: 0.001)
    }

    func testWeekBoundaryMondayToSunday() {
        let monday = weekMonday
        let nextMonday = monday + 7 * 86400
        let lastSundayMoment = nextMonday - 1        // Sunday 23:59:59 UTC
        let previousSunday = monday - 86400          // Sunday before this week

        let workouts = [
            makeWorkout(intent: .zone2,    startDate: previousSunday,                 duration: 3600),
            makeWorkout(intent: .zone2,    startDate: monday,                         duration: 3600),
            makeWorkout(intent: .strength, startDate: lastSundayMoment - 3600,        duration: 3600),
            makeWorkout(intent: .zone2,    startDate: nextMonday,                     duration: 3600),
        ]
        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)

        XCTAssertEqual(summary.workoutCount, 2)
        XCTAssertEqual(summary.intentDistribution[.zone2], 1)
        XCTAssertEqual(summary.intentDistribution[.strength], 1)
        XCTAssertEqual(summary.restDays, 5)
        XCTAssertEqual(summary.consecutiveTrainingDays, 1) // Mon and Sun are 6 days apart
        XCTAssertEqual(summary.weekStart, monday)
        XCTAssertEqual(summary.weekEnd, lastSundayMoment)
    }

    func testWeeklySummaryIncludesHRVObservationCoverageAndAverage() {
        let monday = weekMonday
        let workouts = [
            WorkoutInput(
                workoutType: .running,
                startDate: monday,
                endDate: monday + 3600,
                heartRateSamples: makeSamples([118, 120, 121]),
                hrvSDNNMilliseconds: 40,
                intent: .zone2
            ),
            WorkoutInput(
                workoutType: .cycling,
                startDate: monday + 86400,
                endDate: monday + 86400 + 3600,
                heartRateSamples: makeSamples([122, 124, 125]),
                hrvSDNNMilliseconds: nil,
                intent: .zone2
            ),
            WorkoutInput(
                workoutType: .walking,
                startDate: monday + 2 * 86400,
                endDate: monday + 2 * 86400 + 3600,
                heartRateSamples: makeSamples([105, 108, 110]),
                hrvSDNNMilliseconds: 50,
                intent: .activityReview
            )
        ]

        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)
        XCTAssertEqual(summary.hrvSampledWorkoutCount, 2)
        XCTAssertEqual(summary.hrvCoverageRatio, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.averageHRVSDNNMilliseconds ?? -1, 45.0, accuracy: 0.001)
    }

    func testCurrentWeekUsesElapsedDaysInsteadOfFullWeek() {
        let monday = weekMonday
        let asOf = monday + 3 * 86400 + 12 * 3600 // Thursday noon (day 4)
        let workouts = [
            makeWorkout(intent: .zone2, startDate: monday, duration: 3600),
            makeWorkout(intent: .zone2, startDate: monday + 86400, duration: 3600),
            makeWorkout(intent: .zone2, startDate: monday + 2 * 86400, duration: 3600),
        ]

        let summary = WeeklyObservationBuilder.build(
            workouts: workouts,
            weekStart: monday,
            calendar: utcCalendar,
            asOf: asOf
        )

        XCTAssertEqual(summary.elapsedDays, 4)
        XCTAssertEqual(summary.restDays, 1) // Thu is rest day so far; Fri-Sun should not be counted yet
    }

    func testStrengthDaysIncludesStrengthWorkoutType() {
        let monday = weekMonday
        let workouts = [
            WorkoutInput(
                workoutType: .strengthTraining,
                startDate: monday,
                endDate: monday + 3600,
                heartRateSamples: makeSamples([98, 101, 103]),
                intent: .activityReview
            ),
            WorkoutInput(
                workoutType: .strengthTraining,
                startDate: monday + 86400,
                endDate: monday + 86400 + 1800,
                heartRateSamples: makeSamples([100, 102, 104]),
                intent: .zone2
            )
        ]

        let summary = WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: utcCalendar, asOf: weekEndAsOf)
        XCTAssertEqual(summary.strengthDays, 2)
    }

    // MARK: - ZoneDistributionAnalyzer.merge

    func testZoneDistributionMergeOfEmptyArrayReturnsZeroCounts() {
        let merged = ZoneDistributionAnalyzer.merge([])
        XCTAssertEqual(merged.counts.values.reduce(0, +), 0)
        XCTAssertTrue(merged.ratios.isEmpty)
    }

    func testZoneDistributionMergeAddsCountsAndRecomputesRatios() {
        let zoneBounds = AnalysisPolicy.default.zoneBounds
        let d1 = ZoneDistributionAnalyzer.analyze(
            samples: makeSamples([115, 115, 115, 115]),  // 4 × zone2
            zoneBounds: zoneBounds
        )
        let d2 = ZoneDistributionAnalyzer.analyze(
            samples: makeSamples([150, 150]),            // 2 × zone4
            zoneBounds: zoneBounds
        )
        let merged = ZoneDistributionAnalyzer.merge([d1, d2])

        XCTAssertEqual(merged.counts[.zone2], 4)
        XCTAssertEqual(merged.counts[.zone4], 2)
        XCTAssertEqual(merged.ratios[.zone2] ?? 0, 4.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(merged.ratios[.zone4] ?? 0, 2.0 / 6.0, accuracy: 0.001)
    }

    func testZoneDistributionMergeOfSingleDistributionIsIdentity() {
        let zoneBounds = AnalysisPolicy.default.zoneBounds
        let d = ZoneDistributionAnalyzer.analyze(
            samples: makeSamples([115, 118, 120]),
            zoneBounds: zoneBounds
        )
        let merged = ZoneDistributionAnalyzer.merge([d])

        XCTAssertEqual(merged.counts, d.counts)
        XCTAssertEqual(merged.ratios, d.ratios)
    }

    // MARK: - WeeklyWorkoutSummary structure guard

    func testWeeklyWorkoutSummaryExcludesSemanticJudgmentFields() {
        let monday = weekMonday
        let summary = WeeklyObservationBuilder.build(workouts: [], weekStart: monday, calendar: utcCalendar)
        let fieldNames = Set(Mirror(reflecting: summary).children.compactMap(\.label))

        XCTAssertFalse(fieldNames.contains("tooMuch"))
        XCTAssertFalse(fieldNames.contains("notEnoughRest"))
        XCTAssertFalse(fieldNames.contains("recoveryRisk"))
        XCTAssertFalse(fieldNames.contains("recommendation"))
        XCTAssertFalse(fieldNames.contains("tendency"))
        XCTAssertFalse(fieldNames.contains("verdict"))

        XCTAssertTrue(fieldNames.contains("workoutCount"))
        XCTAssertTrue(fieldNames.contains("intentDistribution"))
        XCTAssertTrue(fieldNames.contains("zoneDistribution"))
        XCTAssertTrue(fieldNames.contains("consecutiveTrainingDays"))
    }

    // MARK: - Helpers

    private func makeWorkout(
        intent: TrainingIntent,
        startDate: Date,
        duration: TimeInterval,
        sampleCount: Int = 30
    ) -> WorkoutInput {
        let endDate = startDate.addingTimeInterval(duration)
        let bpm: Double
        switch intent {
        case .zone2:         bpm = 118
        case .vo2Interval:   bpm = 150
        case .strength:      bpm = 100
        case .activityReview:bpm = 130
        }
        let spacing = sampleCount > 1 ? duration / Double(sampleCount - 1) : 0
        let samples = (0..<sampleCount).map { i in
            HeartRateSample(timestamp: startDate.addingTimeInterval(Double(i) * spacing), bpm: bpm)
        }
        return WorkoutInput(workoutType: .running, startDate: startDate, endDate: endDate, heartRateSamples: samples, intent: intent)
    }

    private func makeSamples(_ bpms: [Double]) -> [HeartRateSample] {
        bpms.enumerated().map { i, bpm in
            HeartRateSample(timestamp: Date(timeIntervalSince1970: TimeInterval(i * 60)), bpm: bpm)
        }
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0))!
    }
}
