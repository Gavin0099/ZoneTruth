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
            return ["將此紀錄視為一般活動摘要，而非嚴格的有氧訓練評分。"]
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
            return ["表現優異！您已達到刺激最大攝氧量 (VO2 Max) 所需的高強度區間。"]
        case .warning:
            return ["試著在間歇期稍微拉高強度，讓心率多停留一些時間在 Zone 4 和 Zone 5。"]
        case .fail:
            return [
                "此紀錄缺乏間歇訓練應有的高強度心率峰值。",
                "確保衝刺時的強度足以達到 Zone 4，並給予足夠的恢復時間以便進行下一組衝刺。"
            ]
        }
    }

    private static func strengthRecommendations(
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution
    ) -> [String] {
        switch verdict {
        case .pass:
            return ["心率數據顯示您在組間有適當的休息，這非常適合肌力與爆發力的發展。"]
        case .warning:
            return ["對於純肌力訓練來說，您的心率偏高。如果目標是最大肌力，建議拉長組間休息時間。"]
        case .fail:
            return [
                "這筆紀錄的心率更像是代謝循環訓練或心肺有氧，而非傳統的肌力訓練。",
                "如果想專注於提升肌力，請將組間休息時間增加到 2-3 分鐘，確保肌肉完全恢復。"
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
            return ["這是一次相當標準的 Zone 2 訓練！下次請繼續保持這個配速與呼吸節奏。"]
        case .warning:
            var items = ["在前 10 分鐘稍微降低強度，以減少訓練後段的心率飄移現象。"]
            if distribution.ratio(for: .zone3) >= 0.10 {
                items.append("當您發現呼吸不再能輕鬆對話時（即使覺得配速還可以），請適度放慢腳步。")
            }
            if let driftRatio, driftRatio >= 0.05 {
                items.append("注意下半場心率是否會逐漸攀升，並提早放慢配速。")
            }
            return items
        case .fail:
            return [
                "這次訓練可能已經偏離了穩定的 Zone 2 狀態。",
                "請降低配速或阻力，保持在「輕鬆舒適」的體感，避免長時間停留在 Zone 3 以上。",
            ]
        }
    }
}
