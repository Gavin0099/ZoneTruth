import Foundation

// MARK: - User-declared training goal

public enum UserTrainingGoal: String, Codable, CaseIterable, Equatable, Sendable {
    case aerobicBase    = "aerobic_base"
    case strengthFocus  = "strength_focus"
    case fatLossRecomp  = "fat_loss_recomp"
    case performancePeak = "performance_peak"
    case activeRecovery = "active_recovery"
}

// MARK: - Pattern alignment signal

// Describes how well the observed weekly training pattern matches the declared goal.
// This is always an observational claim — never a prediction or achievement statement.
public enum GoalAlignmentSignal: String, Equatable, Sendable {
    case aligned               // observed pattern is consistent with declared goal direction
    case partiallyAligned      // partial match; some dimensions diverge
    case divergent             // pattern differs from declared goal direction
    case insufficientEvidence  // too few workouts to assess pattern
}

// MARK: - Alignment engine

// Pure deterministic mapping from weekly summary → goal alignment signal.
// Input: user-declared goal + observed weekly summary.
// Output: pattern consistency signal (no causal or predictive claim).
public enum GoalAlignmentEngine {

    public static func evaluate(
        goal: UserTrainingGoal,
        summary: WeeklyWorkoutSummary
    ) -> GoalAlignmentSignal {
        guard summary.workoutCount >= 2 else {
            return .insufficientEvidence
        }
        switch goal {
        case .aerobicBase:    return evaluateAerobicBase(summary)
        case .strengthFocus:  return evaluateStrengthFocus(summary)
        case .fatLossRecomp:  return evaluateFatLossRecomp(summary)
        case .performancePeak: return evaluatePerformancePeak(summary)
        case .activeRecovery: return evaluateActiveRecovery(summary)
        }
    }

    // MARK: - Private per-goal evaluators

    private static func evaluateAerobicBase(_ s: WeeklyWorkoutSummary) -> GoalAlignmentSignal {
        let z2Count = s.intentDistribution[.zone2, default: 0]
        let z2Ratio = Double(z2Count) / Double(s.workoutCount)
        if z2Ratio >= 0.6 && s.highIntensityDays <= 1 && s.workoutCount >= 3 { return .aligned }
        if s.highIntensityDays >= 3 { return .divergent }
        if z2Ratio >= 0.4 || s.highIntensityDays <= 1 { return .partiallyAligned }
        return .divergent
    }

    private static func evaluateStrengthFocus(_ s: WeeklyWorkoutSummary) -> GoalAlignmentSignal {
        if s.strengthDays >= 2 && s.workoutCount >= 3 { return .aligned }
        if s.strengthDays >= 1 { return .partiallyAligned }
        return .divergent
    }

    private static func evaluateFatLossRecomp(_ s: WeeklyWorkoutSummary) -> GoalAlignmentSignal {
        let hasMixedStimulus = s.strengthDays >= 1 || s.highIntensityDays >= 1
        if s.workoutCount >= 3 && hasMixedStimulus && s.restDays <= 4 { return .aligned }
        if s.workoutCount >= 2 && s.restDays <= 5 { return .partiallyAligned }
        return .divergent
    }

    private static func evaluatePerformancePeak(_ s: WeeklyWorkoutSummary) -> GoalAlignmentSignal {
        if s.workoutCount >= 4 && s.highIntensityDays >= 1 { return .aligned }
        if s.workoutCount >= 3 { return .partiallyAligned }
        if s.restDays >= 4 { return .divergent }
        return .partiallyAligned
    }

    private static func evaluateActiveRecovery(_ s: WeeklyWorkoutSummary) -> GoalAlignmentSignal {
        if s.restDays >= 4 || (s.workoutCount <= 2 && s.highIntensityDays == 0) { return .aligned }
        if s.highIntensityDays >= 2 || s.workoutCount >= 5 { return .divergent }
        return .partiallyAligned
    }
}
