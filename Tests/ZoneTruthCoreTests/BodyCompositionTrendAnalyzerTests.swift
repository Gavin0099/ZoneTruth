import Foundation
import XCTest
@testable import ZoneTruthCore

final class BodyCompositionTrendAnalyzerTests: XCTestCase {
    func testAnalyzeReturnsNilWhenMeasurementsAreInsufficient() {
        let onlyOne = [measurement(dayOffset: 0, weightKg: 70.0, muscleKg: 30.0, fatKg: 15.0, visceralCm2: 90.0)]
        XCTAssertNil(BodyCompositionTrendAnalyzer.analyze(measurements: onlyOne))
    }

    func testAnalyzeMarksTrendsUncertainWithinNoiseBand() {
        let measurements = [
            measurement(dayOffset: 0, weightKg: 70.0, muscleKg: 30.0, fatKg: 15.0, visceralCm2: 90.0),
            measurement(dayOffset: 7, weightKg: 70.2, muscleKg: 30.2, fatKg: 14.7, visceralCm2: 87.0),
            measurement(dayOffset: 14, weightKg: 70.4, muscleKg: 30.4, fatKg: 14.4, visceralCm2: 84.0),
        ]

        let ledger = BodyCompositionTrendAnalyzer.analyze(measurements: measurements)
        XCTAssertNotNil(ledger)
        XCTAssertEqual(ledger?.fatTrend.direction, .stable)
        XCTAssertEqual(ledger?.fatTrend.confidence, .uncertain)
        XCTAssertEqual(ledger?.muscleTrend.direction, .stable)
        XCTAssertEqual(ledger?.muscleTrend.confidence, .uncertain)
        XCTAssertFalse(ledger?.isBodyRecomposition ?? true)
    }

    func testAnalyzeDetectsBodyRecompositionWhenFatDeclinesAndMuscleIsPreserved() {
        let measurements = [
            measurement(dayOffset: 0, weightKg: 74.0, muscleKg: 31.0, fatKg: 20.0, visceralCm2: 110.0),
            measurement(dayOffset: 10, weightKg: 73.4, muscleKg: 31.1, fatKg: 18.8, visceralCm2: 101.0),
            measurement(dayOffset: 21, weightKg: 72.8, muscleKg: 31.2, fatKg: 17.6, visceralCm2: 93.0),
            measurement(dayOffset: 35, weightKg: 72.4, muscleKg: 31.3, fatKg: 16.9, visceralCm2: 86.0),
        ]

        let ledger = BodyCompositionTrendAnalyzer.analyze(measurements: measurements)
        XCTAssertNotNil(ledger)
        XCTAssertEqual(ledger?.fatTrend.direction, .declining)
        XCTAssertTrue(
            ledger?.fatTrend.confidence == .strong || ledger?.fatTrend.confidence == .directional,
            "Fat trend should be admissibly declining beyond noise."
        )
        XCTAssertNotEqual(ledger?.muscleTrend.direction, .declining)
        XCTAssertTrue(ledger?.isBodyRecomposition ?? false)
    }

    private func measurement(
        dayOffset: Int,
        weightKg: Double,
        muscleKg: Double,
        fatKg: Double,
        visceralCm2: Double
    ) -> BodyCompositionMeasurement {
        BodyCompositionMeasurement(
            date: Date(timeIntervalSince1970: TimeInterval(dayOffset * 86_400)),
            weightKg: weightKg,
            skeletalMuscleKg: muscleKg,
            bodyFatKg: fatKg,
            bmi: 22.0,
            bodyFatPercent: 20.0,
            waistHipRatio: 0.85,
            visceralFatCm2: visceralCm2,
            subcutaneousFatCm2: 120.0,
            basalMetabolicRateKcal: 1550
        )
    }
}
