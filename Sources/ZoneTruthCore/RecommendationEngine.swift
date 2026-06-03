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
            return ["高強度區間停留比例與 VO2 間歇目標較一致，可維持目前間歇結構並觀察恢復品質。"]
        case .warning:
            return ["若目標是 VO2，可考慮微調間歇段強度或時間，讓 Zone 4/5 停留比例更接近目標。"]
        case .fail:
            return [
                "此紀錄缺乏間歇訓練應有的高強度心率峰值。",
                "若目標是 VO2，可考慮提高間歇段刺激或延長恢復段，讓下一組更容易回到高強度區間。"
            ]
        }
    }

    private static func strengthRecommendations(
        verdict: AnalysisVerdict,
        distribution: ZoneDistribution
    ) -> [String] {
        switch verdict {
        case .pass:
            return ["心率型態顯示組間恢復較明顯，與傳統肌力或爆發力訓練節奏較一致。"]
        case .warning:
            return ["對於純肌力訓練來說，您的心率偏高。如果目標是最大肌力，建議拉長組間休息時間。"]
        case .fail:
            return [
                "這筆紀錄的心率更像是代謝循環訓練或心肺有氧，而非傳統的肌力訓練。",
                "如果想專注於肌力訓練，可考慮將組間休息時間拉長到 2-3 分鐘，並觀察下一組開始前的恢復狀態。"
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
            return ["這次 Zone 2 型態偏穩定，下次可維持相近配速與呼吸節奏。"]
        case .warning:
            var items = ["在前 10 分鐘稍微降低強度，以減少訓練後段的心率飄移現象。"]
            if distribution.ratio(for: .zone3) >= 0.10 {
                items.append("當呼吸不再能輕鬆對話時，即使配速體感尚可，也可考慮小幅放慢。")
            }
            if let driftRatio, driftRatio >= 0.05 {
                items.append("建議觀察下半場心率是否逐漸攀升，必要時可提早微調配速。")
            }
            return items
        case .fail:
            return [
                "這次訓練可能已經偏離了穩定的 Zone 2 狀態。",
                "若目標是 Zone 2，可考慮降低配速或阻力，讓體感回到較輕鬆、可對話的範圍。",
            ]
        }
    }
}
