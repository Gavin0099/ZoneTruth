import Foundation

public enum CalibrationEngine {
    public static func suggestZoneBounds(
        restingHeartRate: Double,
        currentPolicy: AnalysisPolicy,
        offsets: RestingHeartRateSuggestionOffsets = .default
    ) -> CalibrationSuggestion? {
        guard restingHeartRate >= 35, restingHeartRate <= 100 else { return nil }

        let suggestedLower = restingHeartRate + offsets.lowerOffset
        let suggestedUpper = restingHeartRate + offsets.upperOffset
        guard suggestedUpper > suggestedLower else { return nil }

        let zone4Gap = currentPolicy.zoneBounds.zone4Threshold - currentPolicy.zoneBounds.zone2UpperBound
        let zone5Gap = currentPolicy.zoneBounds.zone5Threshold - currentPolicy.zoneBounds.zone2UpperBound
        let suggestedZone4 = max(suggestedUpper + 8, suggestedUpper + zone4Gap)
        let suggestedZone5 = max(suggestedZone4 + 8, suggestedUpper + zone5Gap)

        let suggestedBounds = ZoneBounds(
            zone2LowerBound: suggestedLower,
            zone2UpperBound: suggestedUpper,
            zone4Threshold: suggestedZone4,
            zone5Threshold: suggestedZone5
        )

        return CalibrationSuggestion(
            currentBounds: currentPolicy.zoneBounds,
            suggestedBounds: suggestedBounds,
            reason: "依靜息心率 \(Int(restingHeartRate.rounded())) bpm 與產品預設偏移規則，產生初步 Zone 2 參考範圍。此範圍尚未經足夠訓練資料驗證，後續應依心率漂移、配速穩定度與主觀感受校正。",
            confidence: 0.55,
            source: .restingHeartRateHeuristic,
            sourceSessionIDs: []
        )
    }

    /// Analyzes a set of historical workout results to determine if the heart rate zones should be adjusted.
    /// Currently focuses on Zone 2 sessions.
    public static func analyzeDriftTrend(
        analyses: [(WorkoutInput, AnalysisResult)],
        currentPolicy: AnalysisPolicy
    ) -> CalibrationSuggestion? {
        let zone2Passes = analyses.filter { $0.0.intent == .zone2 && $0.1.verdict == .pass }
        
        // We need at least 3 successful sessions to consider calibration valid.
        guard zone2Passes.count >= 3 else { return nil }
        
        let drifts = zone2Passes.compactMap { $0.1.driftRatio }
        guard !drifts.isEmpty else { return nil }
        
        let averageDrift = drifts.reduce(0, +) / Double(drifts.count)
        let averageLeakage = zone2Passes.map { $0.1.zoneDistribution.ratio(for: .zone3) }.reduce(0, +) / Double(zone2Passes.count)
        
        let currentUpperBound = currentPolicy.zoneBounds.zone2UpperBound
        
        // Logic:
        // 1. If average drift is extremely low (< 2.5%) and leakage is minimal (< 3%),
        //    the upper bound might be too conservative. Suggest raising it.
        if averageDrift < 0.025 && averageLeakage < 0.03 {
            let suggestedUpper = currentUpperBound + 3
            return CalibrationSuggestion(
                currentBounds: currentPolicy.zoneBounds,
                suggestedBounds: ZoneBounds(
                    zone2LowerBound: currentPolicy.zoneBounds.zone2LowerBound,
                    zone2UpperBound: suggestedUpper,
                    zone4Threshold: currentPolicy.zoneBounds.zone4Threshold,
                    zone5Threshold: currentPolicy.zoneBounds.zone5Threshold
                ),
                reason: "心率飄移持續偏低（平均 \(Int(averageDrift * 100))%），建議你的有氧閾值可能高於目前設定的 Zone 2 上限。",
                confidence: min(0.9, 0.5 + Double(zone2Passes.count) * 0.1),
                source: .driftTrend,
                sourceSessionIDs: zone2Passes.map { $0.0.id }
            )
        }
        
        // 2. If average drift is high (> 6%) even in successful sessions,
        //    the upper bound might be too aggressive. Suggest lowering it.
        if averageDrift > 0.06 {
            let suggestedUpper = currentUpperBound - 3
            return CalibrationSuggestion(
                currentBounds: currentPolicy.zoneBounds,
                suggestedBounds: ZoneBounds(
                    zone2LowerBound: currentPolicy.zoneBounds.zone2LowerBound,
                    zone2UpperBound: suggestedUpper,
                    zone4Threshold: currentPolicy.zoneBounds.zone4Threshold,
                    zone5Threshold: currentPolicy.zoneBounds.zone5Threshold
                ),
                reason: "心率飄移持續偏高（平均 \(Int(averageDrift * 100))%），目前的 Zone 2 上限對穩態有氧訓練可能過於激進，建議適度下調。",
                confidence: min(0.9, 0.5 + Double(zone2Passes.count) * 0.1),
                source: .driftTrend,
                sourceSessionIDs: zone2Passes.map { $0.0.id }
            )
        }
        
        return nil
    }
}
