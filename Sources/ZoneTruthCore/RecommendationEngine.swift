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
        case .vo2Interval, .strength:
            return ["This intent is intentionally deferred in MVP because heart rate alone is not enough for a trustworthy judgment."]
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
