import Foundation

public enum CalibrationEngine {
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
                reason: "Consistent low heart rate drift (avg \(Int(averageDrift * 100))%) suggests your aerobic threshold may be higher than currently set.",
                confidence: min(0.9, 0.5 + Double(zone2Passes.count) * 0.1),
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
                reason: "Consistent high heart rate drift (avg \(Int(averageDrift * 100))%) suggests your current Zone 2 upper bound may be too intense for steady-state aerobic work.",
                confidence: min(0.9, 0.5 + Double(zone2Passes.count) * 0.1),
                sourceSessionIDs: zone2Passes.map { $0.0.id }
            )
        }
        
        return nil
    }
}
