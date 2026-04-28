import Foundation

public enum RecommendationEngine {
    public static func recommendations(
        for intent: TrainingIntent,
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution,
        driftRatio: Double?
    ) -> [String] {
        switch intent {
        case .zone2:
            return zone2Recommendations(verdict: verdict, distribution: distribution, driftRatio: driftRatio)
        case .activityReview:
            return ["Treat this session as descriptive activity review, not as a strict aerobic quality score."]
        case .vo2Interval:
            return vo2IntervalRecommendations(verdict: verdict, distribution: distribution)
        case .strength:
            return strengthRecommendations(verdict: verdict, distribution: distribution)
        }
    }

    private static func vo2IntervalRecommendations(
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution
    ) -> [String] {
        switch verdict {
        case .pass:
            return ["Great work. You reached the high-intensity zones required to stimulate VO2 max improvements."]
        case .warning:
            return ["Try to push slightly harder during your work intervals to spend more time in Zone 4 and 5."]
        case .fail:
            return [
                "This session lacked the high-intensity peaks expected for VO2/Interval work.",
                "Ensure your intervals are intense enough to reach Zone 4, and allow enough recovery to repeat the effort."
            ]
        }
    }

    private static func strengthRecommendations(
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution
    ) -> [String] {
        switch verdict {
        case .pass:
            return ["Heart rate suggests appropriate rest periods for strength and power development."]
        case .warning:
            return ["Your heart rate is slightly high for pure strength work. Consider longer rest periods if your goal is maximum strength."]
        case .fail:
            return [
                "This session looks more like a metabolic circuit or cardio than traditional strength training.",
                "If focusing on strength, increase rest between sets to 2-3 minutes to allow for full recovery."
            ]
        }
    }

    private static func zone2Recommendations(
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution,
        driftRatio: Double?
    ) -> [String] {
        switch verdict {
        case .pass:
            return ["This looked like a plausible Zone 2 session. Keep the same pacing and breathing pattern next time."]
        case .warning:
            var items = ["Lower intensity slightly in the first 10 minutes to reduce later drift."]
            if distribution.ratio(for: .zone3) >= 0.10 {
                items.append("Back off when breathing becomes less conversational, even if pace still feels manageable.")
            }
            if let driftRatio, driftRatio >= 0.05 {
                items.append("Watch for gradual heart rate creep in the second half and reduce pace earlier.")
            }
            return items
        case .fail:
            return [
                "This session likely drifted away from steady Zone 2 work.",
                "Reduce pace or resistance and keep the effort comfortable enough to stay out of extended Zone 3.",
            ]
        }
    }
}
