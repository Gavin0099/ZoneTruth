import Foundation
import XCTest
@testable import ZoneTruthCore

final class WeeklyLoadSnapshotTests: XCTestCase {

    // 2026-05-18 is a Monday
    private var weekMonday: Date { makeUTCDate(year: 2026, month: 5, day: 18) }

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var weekEndAsOf: Date { weekMonday + (7 * 86400) - 1 }

    // MARK: - Snapshot

    func testWeeklyLoadPolicySnapshotFixture() throws {
        let records = buildFixtureRecords()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = try encoder.encode(records)
        let url = fixtureURL()

        if ProcessInfo.processInfo.environment["UPDATE_WEEKLY_LOAD_FIXTURE"] == "1" {
            try rendered.write(to: url)
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture not found. Run with UPDATE_WEEKLY_LOAD_FIXTURE=1 to generate.")
        }
        let expected = try Data(contentsOf: url)
        XCTAssertEqual(
            String(decoding: rendered, as: UTF8.self),
            String(decoding: expected, as: UTF8.self),
            "Weekly load policy snapshot mismatch. Use UPDATE_WEEKLY_LOAD_FIXTURE=1 only after intentional policy changes."
        )
    }

    // MARK: - Guards

    func testAllSixCasesHaveNoForbiddenLanguage() {
        let forbidden = ["過度訓練", "overtraining", "身體恢復不良", "休息不足", "not enough rest", "恢復不良"]
        for (id, summary) in buildCaseSummaries() {
            let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)
            let allText = (policy.keyFindings + [policy.nextAction]).joined(separator: " ")
            for term in forbidden {
                XCTAssertFalse(
                    allText.contains(term),
                    "Case '\(id)' contains forbidden term '\(term)'"
                )
            }
        }
    }

    func testSparseDataCaseHasLowConcernAndReducedConfidence() {
        let cases = buildCaseSummaries()
        let entry = cases.first { $0.id == "sparse_data_week" }!
        let policy = WeeklyLoadPolicyEngine.evaluate(summary: entry.summary)

        XCTAssertEqual(policy.recoveryConcernLevel, .low,
            "Sparse data must not inflate concern level")
        XCTAssertLessThan(policy.confidence, 0.6,
            "Sparse data must reduce confidence")
    }

    // MARK: - Case builders

    private func buildCaseSummaries() -> [(id: String, summary: WeeklyWorkoutSummary)] {
        let monday = weekMonday
        let cal = utcCalendar
        let d: (Int) -> Date = { monday + TimeInterval($0) * 86400 }

        return [
            ("balanced_week", build([
                wo(.zone2,          d(0), 3600),
                wo(.vo2Interval,    d(1), 2700),
                wo(.strength,       d(2), 2700),
                wo(.zone2,          d(4), 3600),
            ], monday: monday, cal: cal)),

            ("high_intensity_cluster", build([
                wo(.vo2Interval,    d(0), 2700),
                wo(.vo2Interval,    d(1), 2700),
                wo(.vo2Interval,    d(2), 2700),
                wo(.zone2,          d(3), 3600),
                wo(.zone2,          d(4), 3600),
                wo(.strength,       d(5), 2700),
            ], monday: monday, cal: cal)),

            ("no_rest_days_zone2", build(
                (0..<7).map { wo(.zone2, d($0), 3600) },
                monday: monday, cal: cal
            )),

            ("mixed_week", build([
                wo(.zone2,          d(0), 3600),
                wo(.vo2Interval,    d(1), 2700),
                wo(.strength,       d(3), 2700),
                wo(.activityReview, d(5), 3600),
                wo(.zone2,          d(6), 3600),
            ], monday: monday, cal: cal)),

            ("underloaded_week", build([
                wo(.zone2, d(2), 2700),
            ], monday: monday, cal: cal)),

            ("sparse_data_week", build([
                wo(.zone2, d(0), 3600, n: 3),
                wo(.zone2, d(2), 3600, n: 3),
            ], monday: monday, cal: cal)),
        ]
    }

    private func buildFixtureRecords() -> [WeeklyLoadPolicyFixtureRecord] {
        buildCaseSummaries().map { id, summary in
            let policy = WeeklyLoadPolicyEngine.evaluate(summary: summary)
            return WeeklyLoadPolicyFixtureRecord(
                id: id,
                recoveryConcernLevel: policy.recoveryConcernLevel.rawValue,
                loadTendency: policy.loadTendency.rawValue,
                keyFindings: policy.keyFindings,
                nextAction: policy.nextAction,
                confidence: policy.confidence
            )
        }
    }

    private func build(_ workouts: [WorkoutInput], monday: Date, cal: Calendar) -> WeeklyWorkoutSummary {
        WeeklyObservationBuilder.build(workouts: workouts, weekStart: monday, calendar: cal, asOf: weekEndAsOf)
    }

    private func wo(
        _ intent: TrainingIntent,
        _ startDate: Date,
        _ duration: TimeInterval,
        n sampleCount: Int = 30
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

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("weekly_load_policy_snapshot.json", isDirectory: false)
    }
}

private struct WeeklyLoadPolicyFixtureRecord: Codable, Equatable {
    let id: String
    let recoveryConcernLevel: String
    let loadTendency: String
    let keyFindings: [String]
    let nextAction: String
    let confidence: Double
}
