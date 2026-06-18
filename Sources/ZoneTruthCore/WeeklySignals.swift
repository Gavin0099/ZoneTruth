import Foundation

public enum WeeklyDecisionAuthority: String, Codable, Equatable, Sendable {
    case observational = "Direct observation"
    case boundedInference = "Bounded inference"
    case weakInference = "Weak inference"
}

public enum WeeklyInferenceClass: String, Codable, Equatable, Sendable {
    case bounded = "Bounded inference"
    case weak = "Weak inference"
    case unsupported = "Unsupported speculation"
}

public enum WeeklyDataFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case partial
    case stale
    case missing
}

public enum WeeklyFreshnessSignal {
    public static func classify(
        workouts: [WorkoutInput],
        weekStart: Date,
        now: Date = Date()
    ) -> WeeklyDataFreshness {
        let calendar = Calendar.current
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)
            ?? weekStart.addingTimeInterval(7 * 24 * 60 * 60)
        let weekWorkouts = workouts.filter { workout in
            workout.startDate >= weekStart && workout.startDate < nextWeekStart
        }
        guard let latest = weekWorkouts.map(\.startDate).max() else {
            return .missing
        }
        let hours = now.timeIntervalSince(latest) / 3600
        if hours <= 30 { return .fresh }
        if hours <= 72 { return .partial }
        return .stale
    }
}

public enum WeeklyAuthorityRendering {
    public static func authority(for confidence: Double, freshness: WeeklyDataFreshness) -> WeeklyDecisionAuthority {
        if freshness == .stale || freshness == .missing {
            return .weakInference
        }
        if confidence < 0.6 { return .weakInference }
        if confidence < 0.75 { return .boundedInference }
        return .observational
    }
}

public enum WeeklyConfidenceSemantics {
    public static func calibrated(
        baseConfidence: Double,
        freshness: WeeklyDataFreshness,
        workoutCount: Int,
        hrvSampledWorkoutCount: Int,
        hrvCoverageRatio: Double
    ) -> Double {
        var value = baseConfidence

        switch freshness {
        case .missing, .stale:
            value = min(value, 0.55)
        case .partial:
            value = min(value, 0.70)
        case .fresh:
            break
        }

        if workoutCount >= 3 {
            if hrvSampledWorkoutCount == 0 {
                value = min(value, 0.58)
            } else if hrvCoverageRatio < 0.34 {
                value = min(value, 0.60)
            } else if hrvCoverageRatio < 0.67 {
                value = min(value, 0.72)
            }
        }

        return max(0.1, min(0.95, value))
    }
}

public enum WeeklyInferenceClassifier {
    public static func classify(
        confidence: Double,
        freshness: WeeklyDataFreshness,
        workoutCount: Int,
        elapsedDays: Int,
        hrvSampledWorkoutCount: Int = 0,
        hrvCoverageRatio: Double = 0
    ) -> WeeklyInferenceClass {
        if freshness == .missing || workoutCount == 0 || elapsedDays == 0 {
            return .unsupported
        }
        if workoutCount >= 3 {
            if hrvSampledWorkoutCount == 0 { return .weak }
            if hrvCoverageRatio < 0.34 { return .weak }
        }
        if freshness == .stale || confidence < 0.6 {
            return .weak
        }
        return .bounded
    }
}

public enum TrainingState: String, Codable, Equatable, Sendable {
    case recovered = "Recovered"
    case accumulatingLoad = "Accumulating load"
    case functionalFatigue = "Functional fatigue"
    case possibleUnderRecovery = "Possible under-recovery"
    case recoveryNormalizing = "Recovery normalizing"
}

public enum AdaptationTemporalScope: String, Codable, Equatable, Sendable {
    case short7d
    case medium28dUnavailable
}

public enum WeeklyAdaptationDirection: String, Codable, Equatable, Sendable {
    case enduranceBuild = "Endurance build"
    case maintenance = "Maintenance"
    case mixedAdaptation = "Mixed adaptation"
    case recoveryBiased = "Recovery-biased"
    case noSignal = "No clear direction"
}

public struct WeeklyTrainingStateSignal: Equatable, Sendable {
    public let state: TrainingState
    public let authority: WeeklyDecisionAuthority
    public let inferenceClass: WeeklyInferenceClass
    public let rationale: String
    public let provenance: InferenceProvenance

    public static func from(
        summary: WeeklyWorkoutSummary,
        policy: WeeklyLoadPolicy,
        freshness: WeeklyDataFreshness,
        confidenceOverride: Double? = nil
    ) -> WeeklyTrainingStateSignal {
        let confidence = confidenceOverride ?? policy.confidence
        let authority = WeeklyAuthorityRendering.authority(for: confidence, freshness: freshness)
        let inferenceClass = WeeklyInferenceClassifier.classify(
            confidence: confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )

        if inferenceClass == .unsupported {
            return WeeklyTrainingStateSignal(
                state: .recoveryNormalizing,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "觀測不足，暫以恢復回穩中呈現，不做狀態升級判定。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .dataFreshness, .hrvCoverage], summary: summary)
            )
        }

        if freshness == .stale || freshness == .missing {
            return WeeklyTrainingStateSignal(
                state: .recoveryNormalizing,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "資料新鮮度不足，狀態回到恢復回穩中並降低決策權重。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.dataFreshness, .workoutCount], summary: summary)
            )
        }

        if summary.workoutCount == 0 || summary.restDays >= 4 {
            return WeeklyTrainingStateSignal(
                state: .recovered,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "近期負荷偏低且休息比例較高，恢復訊號偏穩定。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .restDays], summary: summary)
            )
        }

        if summary.highIntensityDays >= 2 && summary.consecutiveTrainingDays >= 4 {
            return WeeklyTrainingStateSignal(
                state: .possibleUnderRecovery,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "高強度與連續負荷並存，恢復壓力上升，建議控管強度堆疊。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.highIntensityDays, .consecutiveTrainingDays, .workoutCount], summary: summary)
            )
        }

        if summary.consecutiveTrainingDays >= 3 || policy.recoveryConcernLevel == .elevated || policy.recoveryConcernLevel == .high {
            return WeeklyTrainingStateSignal(
                state: .functionalFatigue,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "負荷連續性提升，較像適應期常見的功能性疲勞訊號。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.consecutiveTrainingDays, .recoveryConcernLevel, .workoutCount], summary: summary)
            )
        }

        if summary.workoutCount >= 3 {
            return WeeklyTrainingStateSignal(
                state: .accumulatingLoad,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "本週訓練節奏連續，負荷正在累積，屬於正常訓練推進期。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .consecutiveTrainingDays, .highIntensityDays], summary: summary)
            )
        }

        return WeeklyTrainingStateSignal(
            state: .recoveryNormalizing,
            authority: authority,
            inferenceClass: inferenceClass,
            rationale: "訊號偏中性，恢復與負荷正在重新平衡。",
            provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .zoneDistribution, .restDays], summary: summary)
        )
    }
}

public struct WeeklyAdaptationSignal: Equatable, Sendable {
    public let direction: WeeklyAdaptationDirection
    public let authority: WeeklyDecisionAuthority
    public let inferenceClass: WeeklyInferenceClass
    public let temporalScopes: [AdaptationTemporalScope]
    public let rationale: String
    public let provenance: InferenceProvenance

    public static func from(
        summary: WeeklyWorkoutSummary,
        policy: WeeklyLoadPolicy,
        freshness: WeeklyDataFreshness,
        confidenceOverride: Double? = nil
    ) -> WeeklyAdaptationSignal {
        let confidence = confidenceOverride ?? policy.confidence
        let authority = WeeklyAuthorityRendering.authority(for: confidence, freshness: freshness)
        let inferenceClass = WeeklyInferenceClassifier.classify(
            confidence: confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
        let total = summary.workoutCount
        let z2Count = summary.intentDistribution[.zone2, default: 0]
        let z2Ratio = total > 0 ? Double(z2Count) / Double(total) : 0

        if inferenceClass == .unsupported {
            return WeeklyAdaptationSignal(
                direction: .recoveryBiased,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "目前觀測不足，無法形成可靠的適應方向推論。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .dataFreshness, .hrvCoverage], summary: summary)
            )
        }

        if total == 0 {
            return WeeklyAdaptationSignal(
                direction: .recoveryBiased,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "本週尚無有效訓練觀測，方向訊號偏向恢復優先。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.workoutCount, .restDays], summary: summary)
            )
        }
        if summary.restDays >= 3 && total <= 3 {
            return WeeklyAdaptationSignal(
                direction: .recoveryBiased,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "休息日比例偏高，整體負荷偏向恢復導向。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.restDays, .workoutCount], summary: summary)
            )
        }
        if z2Ratio >= 0.6 && summary.highIntensityDays <= 1 {
            return WeeklyAdaptationSignal(
                direction: .enduranceBuild,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "低中強度佔比較高，與有氧建設期型態一致。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.intentDistribution, .highIntensityDays, .workoutCount], summary: summary)
            )
        }
        if summary.highIntensityDays >= 2 && summary.consecutiveTrainingDays >= 4 {
            return WeeklyAdaptationSignal(
                direction: .mixedAdaptation,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "高強度與連續負荷並存，訊號偏向混合適應。",
                provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.highIntensityDays, .consecutiveTrainingDays, .workoutCount], summary: summary)
            )
        }
        return WeeklyAdaptationSignal(
            direction: .noSignal,
            authority: authority,
            inferenceClass: inferenceClass,
            temporalScopes: [.short7d, .medium28dUnavailable],
            rationale: "目前訓練型態無法對應到特定適應方向，僅能觀察負荷分布。",
            provenance: buildWeeklyProvenance(inferenceClass: inferenceClass, derivedFrom: [.intentDistribution, .zoneDistribution, .workoutCount], summary: summary)
        )
    }
}

public struct WeeklyOverviewSignal: Equatable, Sendable {
    public let semanticConfidence: Double
    public let authority: WeeklyDecisionAuthority
    public let inferenceClass: WeeklyInferenceClass

    public static func from(
        summary: WeeklyWorkoutSummary,
        policy: WeeklyLoadPolicy,
        freshness: WeeklyDataFreshness
    ) -> WeeklyOverviewSignal {
        let semanticConfidence = WeeklyConfidenceSemantics.calibrated(
            baseConfidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
        let authority = WeeklyAuthorityRendering.authority(for: semanticConfidence, freshness: freshness)
        let inferenceClass = WeeklyInferenceClassifier.classify(
            confidence: semanticConfidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
        return WeeklyOverviewSignal(
            semanticConfidence: semanticConfidence,
            authority: authority,
            inferenceClass: inferenceClass
        )
    }
}

private func buildWeeklyProvenance(
    inferenceClass: WeeklyInferenceClass,
    derivedFrom: [DerivedFromSignal],
    summary: WeeklyWorkoutSummary
) -> InferenceProvenance {
    let strength: InferenceStrength = (inferenceClass == .bounded) ? .bounded : .sparse
    return InferenceProvenanceFactory.weekly(
        strength: strength,
        derivedFrom: derivedFrom,
        workoutCount: summary.workoutCount,
        hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount
    )
}
