import Foundation
import ZoneTruthCore

// MARK: - 28d adaptation trend

// Aggregates direction signals from up to 4 weekly summaries.
// Claim level: bounded inference only — direction is HR-derived, not directly measured.
struct AdaptationTrend28d {
    let dominantDirection: WeeklyAdaptationDirection
    let consistencyRatio: Double    // fraction of meaningful weeks with dominant direction
    let qualifyingWeekCount: Int    // weeks with workoutCount >= 2
    let isStrong: Bool              // ratio >= 0.75 AND qualifyingWeekCount >= 3
}

// MARK: - Analyzer

enum MultiWeekAdaptationAnalyzer {

    // Requires at least 2 qualifying weeks (workoutCount >= 2).
    // Returns nil when data is insufficient to form a trend.
    static func analyze(summaries: [WeeklyWorkoutSummary]) -> AdaptationTrend28d? {
        let qualifying = summaries.filter { $0.workoutCount >= 2 }
        guard qualifying.count >= 2 else { return nil }

        let directions = qualifying.map { classifyDirection($0) }
        let meaningful = directions.filter { $0 != .noSignal }
        guard !meaningful.isEmpty else { return nil }

        var counts: [WeeklyAdaptationDirection: Int] = [:]
        for dir in meaningful { counts[dir, default: 0] += 1 }
        guard let (dominant, dominantCount) = counts.max(by: { $0.value < $1.value }) else { return nil }

        let ratio = Double(dominantCount) / Double(meaningful.count)
        let isStrong = ratio >= 0.75 && qualifying.count >= 3

        return AdaptationTrend28d(
            dominantDirection: dominant,
            consistencyRatio: ratio,
            qualifyingWeekCount: qualifying.count,
            isStrong: isStrong
        )
    }

    // Simplified direction from summary: policy-free, freshness-free.
    // Mirrors the core classification in WeeklyAdaptationSignal.from() without authority wrapping.
    static func classifyDirection(_ s: WeeklyWorkoutSummary) -> WeeklyAdaptationDirection {
        let total = s.workoutCount
        guard total >= 2 else { return .noSignal }
        let z2Count = s.intentDistribution[.zone2, default: 0]
        let z2Ratio = Double(z2Count) / Double(total)
        if s.restDays >= 3 && total <= 3 { return .recoveryBiased }
        if z2Ratio >= 0.6 && s.highIntensityDays <= 1 { return .enduranceBuild }
        if s.highIntensityDays >= 2 && s.consecutiveTrainingDays >= 4 { return .mixedAdaptation }
        return .noSignal
    }
}
