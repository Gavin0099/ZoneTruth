import SwiftUI
import ZoneTruthCore

enum WeeklyDecisionAuthority: String {
    case observational = "Direct observation"
    case boundedInference = "Bounded inference"
    case weakInference = "Weak inference"

    var localizedLabel: String {
        switch self {
        case .observational: return "直接觀測"
        case .boundedInference: return "受限推論"
        case .weakInference: return "弱推論"
        }
    }
}

enum WeeklyInferenceClass: String {
    case bounded = "Bounded inference"
    case weak = "Weak inference"
    case unsupported = "Unsupported speculation"

    var localizedLabel: String {
        switch self {
        case .bounded: return "受限推論"
        case .weak: return "弱推論"
        case .unsupported: return "觀測不足"
        }
    }
}

enum WeeklyDataFreshness: String {
    case fresh = "fresh"
    case partial = "partial"
    case stale = "stale"
    case missing = "missing"

    var label: String {
        switch self {
        case .fresh: return "資料新鮮"
        case .partial: return "資料部分"
        case .stale: return "資料偏舊"
        case .missing: return "資料缺失"
        }
    }
}

enum WeeklyFreshnessSignal {
    static func classify(
        workouts: [WorkoutInput],
        weekStart: Date,
        now: Date = Date()
    ) -> WeeklyDataFreshness {
        let weekWorkouts = workouts.filter { $0.startDate >= weekStart }
        guard let latest = weekWorkouts.map(\.startDate).max() else {
            return .missing
        }
        let hours = now.timeIntervalSince(latest) / 3600
        if hours <= 30 { return .fresh }
        if hours <= 72 { return .partial }
        return .stale
    }
}

enum WeeklyAuthorityRendering {
    static func authority(for confidence: Double, freshness: WeeklyDataFreshness) -> WeeklyDecisionAuthority {
        if freshness == .stale || freshness == .missing {
            return .weakInference
        }
        if confidence < 0.6 { return .weakInference }
        if confidence < 0.75 { return .boundedInference }
        return .observational
    }

    static func recommendationEmphasisOpacity(for authority: WeeklyDecisionAuthority) -> Double {
        switch authority {
        case .observational: return 0.08
        case .boundedInference: return 0.06
        case .weakInference: return 0.03
        }
    }

    static func recommendationStrokeOpacity(for authority: WeeklyDecisionAuthority) -> Double {
        switch authority {
        case .observational: return 0.2
        case .boundedInference: return 0.16
        case .weakInference: return 0.12
        }
    }

    static func cardSurfaceOpacity(for authority: WeeklyDecisionAuthority) -> Double {
        switch authority {
        case .observational: return 1.0
        case .boundedInference: return 0.95
        case .weakInference: return 0.88
        }
    }
}

enum WeeklyConfidenceSemantics {
    static func calibrated(
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

enum WeeklyInferenceClassifier {
    static func classify(
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

enum WeeklyHRVCoverageSignal: Equatable {
    case missing
    case sparse
    case partial
    case good

    static func classify(workoutCount: Int, sampledCount: Int, coverageRatio: Double) -> WeeklyHRVCoverageSignal {
        guard workoutCount > 0 else { return .missing }
        if sampledCount == 0 { return .missing }
        if sampledCount == 1 || coverageRatio < 0.34 { return .sparse }
        if coverageRatio < 0.67 { return .partial }
        return .good
    }

    var label: String {
        switch self {
        case .missing: return "HRV 缺失"
        case .sparse: return "HRV 稀疏"
        case .partial: return "HRV 部分"
        case .good: return "HRV 充足"
        }
    }

    var color: Color {
        switch self {
        case .missing: return .gray
        case .sparse: return PremiumColor.gold
        case .partial: return PremiumColor.skyBlue
        case .good: return PremiumColor.emerald
        }
    }
}

enum NonAuthorityReminderLevel {
    case none
    case soft
    case strong

    var message: String {
        switch self {
        case .none:
            return ""
        case .soft:
            return "Based on available HR-derived observations. Not a physiological diagnosis."
        case .strong:
            return "Evidence is limited or stale. Use this as directional guidance only, not a physiological diagnosis."
        }
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .soft: return .secondary
        case .strong: return PremiumColor.gold
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .none: return 0
        case .soft: return 0.0
        case .strong: return 0.08
        }
    }
}

// CTA wording ceiling: stronger directives require higher-authority evidence.
// The base text is preserved so the content signal stays intact;
// only the epistemic framing changes.
enum WeeklyCTAPresenter {
    static func render(_ base: String, for authority: WeeklyDecisionAuthority) -> String {
        switch authority {
        case .observational:
            return base
        case .boundedInference:
            return base + "（建議觀察體感後再決定。）"
        case .weakInference:
            return "訊號有限，僅供方向參考：" + base
        }
    }
}

enum NonAuthorityReminderPolicy {
    static func level(
        inference: WeeklyInferenceClass,
        freshness: WeeklyDataFreshness
    ) -> NonAuthorityReminderLevel {
        if inference == .unsupported || freshness == .missing || freshness == .stale {
            return .strong
        }
        if inference == .weak || freshness == .partial {
            return .soft
        }
        return .none
    }
}

enum WeeklyAdaptationDirection: String {
    case enduranceBuild = "Endurance build"
    case maintenance = "Maintenance"
    case mixedAdaptation = "Mixed adaptation"
    case recoveryBiased = "Recovery-biased"
    case noSignal = "No clear direction"

    var localizedLabel: String {
        switch self {
        case .enduranceBuild: return "有氧建設期"
        case .maintenance: return "訓練負荷穩定維持中"
        case .mixedAdaptation: return "混合適應"
        case .recoveryBiased: return "恢復優先週"
        case .noSignal: return "目前無明顯訓練方向訊號"
        }
    }

    // Claim ceiling: displayed wording is constrained by evidence authority level.
    // Higher claims require higher-quality evidence; residual classification
    // (.noSignal) is always rendered as an explicit evidence gap, never as a
    // positive direction label regardless of authority.
    func admissibleLabel(for authority: WeeklyDecisionAuthority) -> String {
        switch self {
        case .noSignal:
            return "目前沒有足夠訊號判定適應方向"
        case .enduranceBuild:
            switch authority {
            case .observational:   return "有氧建設期"
            case .boundedInference: return "偏向有氧建設方向"
            case .weakInference:   return "觀察到部分有氧偏重訊號"
            }
        case .maintenance:
            switch authority {
            case .observational:   return "訓練負荷穩定維持中"
            case .boundedInference: return "偏向負荷維持態勢"
            case .weakInference:   return "訊號偏中性，方向不明確"
            }
        case .mixedAdaptation:
            switch authority {
            case .observational:   return "混合強度適應"
            case .boundedInference: return "偏向混合強度適應"
            case .weakInference:   return "觀察到強度混合現象"
            }
        case .recoveryBiased:
            switch authority {
            case .observational:   return "恢復優先週"
            case .boundedInference: return "偏向恢復導向"
            case .weakInference:   return "負荷偏輕，休息機會較多"
            }
        }
    }
}

enum TrainingState: String {
    case recovered = "Recovered"
    case accumulatingLoad = "Accumulating load"
    case functionalFatigue = "Functional fatigue"
    case possibleUnderRecovery = "Possible under-recovery"
    case recoveryNormalizing = "Recovery normalizing"

    static let progression: [TrainingState] = [
        .recovered,
        .accumulatingLoad,
        .functionalFatigue,
        .possibleUnderRecovery,
        .recoveryNormalizing
    ]

    var localizedLabel: String {
        switch self {
        case .recovered: return "恢復穩定"
        case .accumulatingLoad: return "累積負荷中"
        case .functionalFatigue: return "功能性疲勞"
        case .possibleUnderRecovery: return "可能恢復不足"
        case .recoveryNormalizing: return "恢復回穩中"
        }
    }

    // Claim ceiling for training state labels.
    // .functionalFatigue requires longitudinal performance degradation data which
    // this system does not collect; the internal classification fires on
    // consecutiveTrainingDays alone, so the rendered wording is always
    // downgraded to reflect the actual evidence level.
    func admissibleLabel(for authority: WeeklyDecisionAuthority) -> String {
        switch self {
        case .recovered:
            return "恢復穩定"
        case .accumulatingLoad:
            switch authority {
            case .observational:   return "負荷累積中"
            case .boundedInference: return "偏向負荷累積狀態"
            case .weakInference:   return "持續訓練中，負荷持平"
            }
        case .functionalFatigue:
            // Never renders clinical term; evidence only supports load-frequency observation.
            switch authority {
            case .observational, .boundedInference: return "恢復壓力偏高"
            case .weakInference:                    return "負荷連續，恢復機會受限"
            }
        case .possibleUnderRecovery:
            switch authority {
            case .observational:   return "可能恢復不足"
            case .boundedInference: return "恢復壓力上升"
            case .weakInference:   return "強度積累，留意恢復狀況"
            }
        case .recoveryNormalizing:
            return "恢復回穩中"
        }
    }
}

struct WeeklyTrainingStateSignal {
    let state: TrainingState
    let authority: WeeklyDecisionAuthority
    let inferenceClass: WeeklyInferenceClass
    let rationale: String

    static func from(
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
                rationale: "觀測不足，暫以恢復回穩中呈現，不做狀態升級判定。"
            )
        }

        if freshness == .stale || freshness == .missing {
            return WeeklyTrainingStateSignal(
                state: .recoveryNormalizing,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "資料新鮮度不足，狀態回到恢復回穩中並降低決策權重。"
            )
        }

        if summary.workoutCount == 0 || summary.restDays >= 4 {
            return WeeklyTrainingStateSignal(
                state: .recovered,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "近期負荷偏低且休息比例較高，恢復訊號偏穩定。"
            )
        }

        if summary.highIntensityDays >= 2 && summary.consecutiveTrainingDays >= 4 {
            return WeeklyTrainingStateSignal(
                state: .possibleUnderRecovery,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "高強度與連續負荷並存，恢復壓力上升，建議控管強度堆疊。"
            )
        }

        if summary.consecutiveTrainingDays >= 3 || policy.recoveryConcernLevel == .elevated || policy.recoveryConcernLevel == .high {
            return WeeklyTrainingStateSignal(
                state: .functionalFatigue,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "負荷連續性提升，較像適應期常見的功能性疲勞訊號。"
            )
        }

        if summary.workoutCount >= 3 {
            return WeeklyTrainingStateSignal(
                state: .accumulatingLoad,
                authority: authority,
                inferenceClass: inferenceClass,
                rationale: "本週訓練節奏連續，負荷正在累積，屬於正常訓練推進期。"
            )
        }

        return WeeklyTrainingStateSignal(
            state: .recoveryNormalizing,
            authority: authority,
            inferenceClass: inferenceClass,
            rationale: "訊號偏中性，恢復與負荷正在重新平衡。"
        )
    }
}

enum AdaptationTemporalScope {
    case short7d
    case medium28dUnavailable

    var label: String {
        switch self {
        case .short7d: return "7d signal"
        case .medium28dUnavailable: return "28d unavailable"
        }
    }
}

struct WeeklyAdaptationSignal {
    let direction: WeeklyAdaptationDirection
    let authority: WeeklyDecisionAuthority
    let inferenceClass: WeeklyInferenceClass
    let temporalScopes: [AdaptationTemporalScope]
    let rationale: String

    static func from(
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
                rationale: "目前觀測不足，無法形成可靠的適應方向推論。"
            )
        }

        if total == 0 {
            return WeeklyAdaptationSignal(
                direction: .recoveryBiased,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "本週尚無有效訓練觀測，方向訊號偏向恢復優先。"
            )
        }
        if summary.restDays >= 3 && total <= 3 {
            return WeeklyAdaptationSignal(
                direction: .recoveryBiased,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "休息日比例偏高，整體負荷偏向恢復導向。"
            )
        }
        if z2Ratio >= 0.6 && summary.highIntensityDays <= 1 {
            return WeeklyAdaptationSignal(
                direction: .enduranceBuild,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "低中強度佔比較高，與有氧建設期型態一致。"
            )
        }
        if summary.highIntensityDays >= 2 && summary.consecutiveTrainingDays >= 4 {
            return WeeklyAdaptationSignal(
                direction: .mixedAdaptation,
                authority: authority,
                inferenceClass: inferenceClass,
                temporalScopes: [.short7d, .medium28dUnavailable],
                rationale: "高強度與連續負荷並存，訊號偏向混合適應。"
            )
        }
        return WeeklyAdaptationSignal(
            direction: .noSignal,
            authority: authority,
            inferenceClass: inferenceClass,
            temporalScopes: [.short7d, .medium28dUnavailable],
            rationale: "目前訓練型態無法對應到特定適應方向，僅能觀察負荷分布。"
        )
    }
}

// MARK: - Extensions

extension RecoveryConcernLevel {
    var localizedLabel: String {
        switch self {
        case .low:      return "低"
        case .moderate: return "中等"
        case .elevated: return "偏高"
        case .high:     return "高"
        }
    }

    var accentColor: Color {
        switch self {
        case .low:      return PremiumColor.emerald
        case .moderate: return PremiumColor.gold
        case .elevated: return .orange
        case .high:     return PremiumColor.redOrange
        }
    }
}

extension LoadTendency {
    var localizedLabel: String {
        switch self {
        case .balanced:           return "均衡"
        case .highIntensityFocused: return "高強度為主"
        case .aerobicFocused:     return "有氧為主"
        case .mixed:              return "混合"
        case .underloaded:        return "訓練量偏少"
        }
    }

    var iconName: String {
        switch self {
        case .balanced:           return "checkmark.circle"
        case .highIntensityFocused: return "bolt.fill"
        case .aerobicFocused:     return "heart.fill"
        case .mixed:              return "shuffle"
        case .underloaded:        return "tortoise.fill"
        }
    }
}

// MARK: - Root view

struct WeeklyDashboardView: View {
    @ObservedObject var viewModel: WorkoutListViewModel
    @ObservedObject var settingsManager: SettingsManager
    private var freshness: WeeklyDataFreshness {
        WeeklyFreshnessSignal.classify(
            workouts: viewModel.workouts,
            weekStart: viewModel.weeklySummary.weekStart
        )
    }

    var body: some View {
        ZStack {
            PremiumColor.bgDark.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    weekRangeHeader
                    WeeklyOverviewCard(
                        summary: viewModel.weeklySummary,
                        policy: viewModel.weeklyPolicy,
                        freshness: freshness,
                        trainingGoal: settingsManager.trainingGoal
                    )
                    WeeklyAdvancedCard(
                        summary: viewModel.weeklySummary,
                        policy: viewModel.weeklyPolicy,
                        freshness: freshness,
                        bodyCompositionLedger: viewModel.bodyCompositionLedger,
                        adaptationTrend28d: viewModel.adaptationTrend28d
                    )
                    WeeklyDistributionCard(summary: viewModel.weeklySummary)
                }
                .padding(16)
            }
        }
        .navigationTitle("本週概況")
        .iosNavigationBarStyling()
    }

    private var weekRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        let s = viewModel.weeklySummary.weekStart
        let e = viewModel.weeklySummary.weekEnd
        return "\(fmt.string(from: s)) – \(fmt.string(from: e))"
    }

    private var weekRangeHeader: some View {
        HStack {
            Text(weekRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Section 1: Overview

struct WeeklyOverviewCard: View {
    let summary: WeeklyWorkoutSummary
    let policy: WeeklyLoadPolicy
    let freshness: WeeklyDataFreshness
    let trainingGoal: UserTrainingGoal?
    private var semanticConfidence: Double {
        WeeklyConfidenceSemantics.calibrated(
            baseConfidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
    }
    private var authority: WeeklyDecisionAuthority {
        WeeklyAuthorityRendering.authority(for: semanticConfidence, freshness: freshness)
    }
    private var inferenceClass: WeeklyInferenceClass {
        WeeklyInferenceClassifier.classify(
            confidence: semanticConfidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
    }
    private var hrvCoverageSignal: WeeklyHRVCoverageSignal {
        WeeklyHRVCoverageSignal.classify(
            workoutCount: summary.workoutCount,
            sampledCount: summary.hrvSampledWorkoutCount,
            coverageRatio: summary.hrvCoverageRatio
        )
    }
    private var reminderLevel: NonAuthorityReminderLevel {
        NonAuthorityReminderPolicy.level(inference: inferenceClass, freshness: freshness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if summary.workoutCount == 0 {
                Label("本週尚無訓練紀錄", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 20) {
                    concernBlock
                    Divider()
                        .frame(height: 44)
                        .background(PremiumColor.border)
                    tendencyBlock
                    Spacer()
                }

                Divider().background(PremiumColor.border)

                HStack(spacing: 8) {
                    EvidenceChip(label: inferenceClass.localizedLabel, color: inferenceChipColor)
                    EvidenceChip(label: freshness.label, color: freshnessChipColor)
                    EvidenceChip(label: hrvCoverageSignal.label, color: hrvCoverageSignal.color)
                    EvidenceChip(label: authority.localizedLabel, color: authorityChipColor)
                    if semanticConfidence < 0.6 || freshness == .stale || freshness == .missing {
                        EvidenceChip(label: "證據缺口", color: PremiumColor.gold)
                    }
                }

                // Goal alignment: only shown when user has declared a training goal
                if let goal = trainingGoal {
                    let signal = GoalAlignmentEngine.evaluate(goal: goal, summary: summary)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            EvidenceChip(label: goal.chipLabel, color: PremiumColor.skyBlue)
                            EvidenceChip(label: signal.localizedLabel, color: signal.chipColor)
                        }
                        Text(signal.observationalLabel(for: goal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(policy.keyFindings, id: \.self) { finding in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 7)
                            Text(finding)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(PremiumColor.gold)
                        .font(.subheadline)
                    Text(WeeklyCTAPresenter.render(policy.nextAction, for: authority))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PremiumColor.gold.opacity(WeeklyAuthorityRendering.recommendationEmphasisOpacity(for: authority)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(PremiumColor.gold.opacity(WeeklyAuthorityRendering.recommendationStrokeOpacity(for: authority)), lineWidth: 1)
                )

                if reminderLevel != .none {
                    Text(reminderLevel.message)
                        .font(.caption2)
                        .foregroundStyle(reminderLevel.color)
                        .padding(reminderLevel == .strong ? 8 : 0)
                        .background(PremiumColor.gold.opacity(reminderLevel.backgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    private var concernBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("恢復觀察")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(policy.recoveryConcernLevel.accentColor)
                    .frame(width: 8, height: 8)
                Text(policy.recoveryConcernLevel.localizedLabel)
                    .font(.headline.bold())
                    .foregroundStyle(policy.recoveryConcernLevel.accentColor)
            }
        }
    }

    private var tendencyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("訓練傾向")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: policy.loadTendency.iconName)
                    .font(.caption.bold())
                    .foregroundStyle(PremiumColor.skyBlue)
                Text(policy.loadTendency.localizedLabel)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private var freshnessChipColor: Color {
        switch freshness {
        case .fresh: return PremiumColor.emerald
        case .partial: return PremiumColor.skyBlue
        case .stale: return PremiumColor.gold
        case .missing: return .gray
        }
    }

    private var inferenceChipColor: Color {
        switch inferenceClass {
        case .bounded: return PremiumColor.skyBlue
        case .weak: return PremiumColor.gold
        case .unsupported: return .gray
        }
    }

    private var authorityChipColor: Color {
        switch authority {
        case .observational: return PremiumColor.emerald
        case .boundedInference: return PremiumColor.skyBlue
        case .weakInference: return PremiumColor.gold
        }
    }
}

// MARK: - Section 2: Distribution

struct WeeklyDistributionCard: View {
    let summary: WeeklyWorkoutSummary

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本週分布")
                .font(.headline.bold())
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 12) {
                MetricGridCell(
                    icon: "figure.run",
                    color: PremiumColor.skyBlue,
                    title: "訓練次數",
                    value: "\(summary.workoutCount) 次"
                )
                MetricGridCell(
                    icon: "clock.fill",
                    color: PremiumColor.neonPurple,
                    title: "總時間",
                    value: String(format: "%.0f 分鐘", summary.totalDurationMinutes)
                )
                MetricGridCell(
                    icon: "moon.zzz",
                    color: .gray,
                    title: "休息日",
                    value: "\(summary.restDays) 天"
                )
                MetricGridCell(
                    icon: "bolt.fill",
                    color: PremiumColor.redOrange,
                    title: "高強度日",
                    value: "\(summary.highIntensityDays) 天"
                )
                MetricGridCell(
                    icon: "flame.fill",
                    color: .orange,
                    title: "連續訓練",
                    value: "\(summary.consecutiveTrainingDays) 天"
                )
                MetricGridCell(
                    icon: "figure.strengthtraining.functional",
                    color: PremiumColor.emerald,
                    title: "肌力日",
                    value: "\(summary.strengthDays) 天"
                )
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }
}

private struct EvidenceChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(color.opacity(0.28), lineWidth: 1)
            )
    }
}

// MARK: - Section 3: Advanced

struct WeeklyAdvancedCard: View {
    let summary: WeeklyWorkoutSummary
    let policy: WeeklyLoadPolicy
    let freshness: WeeklyDataFreshness
    let bodyCompositionLedger: BodyCompositionLedger?
    let adaptationTrend28d: AdaptationTrend28d?
    private var semanticConfidence: Double {
        WeeklyConfidenceSemantics.calibrated(
            baseConfidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            hrvSampledWorkoutCount: summary.hrvSampledWorkoutCount,
            hrvCoverageRatio: summary.hrvCoverageRatio
        )
    }
    private var adaptation: WeeklyAdaptationSignal {
        WeeklyAdaptationSignal.from(
            summary: summary,
            policy: policy,
            freshness: freshness,
            confidenceOverride: semanticConfidence
        )
    }
    private var reminderLevel: NonAuthorityReminderLevel {
        NonAuthorityReminderPolicy.level(inference: adaptation.inferenceClass, freshness: freshness)
    }
    private var trainingState: WeeklyTrainingStateSignal {
        WeeklyTrainingStateSignal.from(
            summary: summary,
            policy: policy,
            freshness: freshness,
            confidenceOverride: semanticConfidence
        )
    }
    private var advancedAuthority: WeeklyDecisionAuthority {
        minimumAuthority(adaptation.authority, trainingState.authority)
    }
    private var hrvCoverageSignal: WeeklyHRVCoverageSignal {
        WeeklyHRVCoverageSignal.classify(
            workoutCount: summary.workoutCount,
            sampledCount: summary.hrvSampledWorkoutCount,
            coverageRatio: summary.hrvCoverageRatio
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("進階")
                .font(.headline.bold())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("適應方向")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))
                // Claim layer: single inference-class chip + direction label
                HStack(spacing: 8) {
                    EvidenceChip(label: adaptation.inferenceClass.localizedLabel, color: adaptationInferenceChipColor)
                    EvidenceChip(label: adaptation.authority.localizedLabel, color: authorityChipColor(for: adaptation.authority))
                    Text(adaptation.direction.admissibleLabel(for: adaptation.authority))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                // Coverage layer: 7d chip always present; 28d chip shows actual trend if available
                HStack(spacing: 6) {
                    EvidenceChip(label: "7d signal", color: .gray)
                    if let trend = adaptationTrend28d {
                        EvidenceChip(label: trend.chipLabel, color: trend.chipColor)
                    } else {
                        EvidenceChip(label: "28d unavailable", color: .gray)
                    }
                }
                Text(adaptation.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let trend = adaptationTrend28d {
                    Text(trend.rationaleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if reminderLevel != .none {
                    Text(reminderLevel.message)
                        .font(.caption2)
                        .foregroundStyle(reminderLevel.color)
                        .padding(reminderLevel == .strong ? 8 : 0)
                        .background(PremiumColor.gold.opacity(reminderLevel.backgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: adaptation.authority))

            Divider().background(PremiumColor.border)

            VStack(alignment: .leading, spacing: 8) {
                Text("訓練狀態")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 8) {
                    EvidenceChip(label: trainingState.inferenceClass.localizedLabel, color: stateInferenceChipColor)
                    EvidenceChip(label: trainingState.authority.localizedLabel, color: authorityChipColor(for: trainingState.authority))
                    Text(trainingState.state.admissibleLabel(for: trainingState.authority))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                StateProgressionBar(currentState: trainingState.state)
                Text(trainingState.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: trainingState.authority))

            Divider().background(PremiumColor.border)

            // Intent distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("訓練目標分布")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))

                let intentsWithData = TrainingIntent.allCases.filter {
                    summary.intentDistribution[$0, default: 0] > 0
                }
                if intentsWithData.isEmpty {
                    Text("本週無訓練紀錄")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(intentsWithData, id: \.self) { intent in
                        HStack {
                            Text(intent.localizedName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(summary.intentDistribution[intent, default: 0]) 次")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: advancedAuthority))

            Divider().background(PremiumColor.border)

            // Zone distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("心率區間分布")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))

                if summary.zoneDistribution.counts.values.reduce(0, +) > 0 {
                    ZoneDistributionChartView(distribution: summary.zoneDistribution)
                } else {
                    Text("心率樣本不足，無法計算區間分布")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: advancedAuthority))

            Divider().background(PremiumColor.border)

            // HRV observation import (P3a): observation-only, no policy coupling.
            VStack(alignment: .leading, spacing: 8) {
                Text("HRV 觀測")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))

                if let avg = summary.averageHRVSDNNMilliseconds {
                    EvidenceChip(label: hrvCoverageSignal.label, color: hrvCoverageSignal.color)
                    HStack {
                        Text("平均 SDNN")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f ms", avg))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Text("覆蓋率")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary.hrvSampledWorkoutCount)/\(max(summary.workoutCount, 0))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text(String(format: "(%.0f%%)", summary.hrvCoverageRatio * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("僅顯示 HRV 觀測訊號，不直接輸出恢復診斷。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    EvidenceChip(label: hrvCoverageSignal.label, color: hrvCoverageSignal.color)
                    Text("本週尚無可用 HRV（SDNN）樣本。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("若健康已有 HRV，請刷新資料與健康授權；系統會優先抓訓練時段，無樣本時回退同日觀測。")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.85))
                }
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: advancedAuthority))

            Divider().background(PremiumColor.border)

            // Long-term body composition context
            VStack(alignment: .leading, spacing: 8) {
                if let ledger = bodyCompositionLedger {
                    BodyCompositionContextSection(ledger: ledger)
                } else {
                    Text("身體組成脈絡")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    Text("尚無可用的身體組成資料，請確認 seed 載入或匯入資料。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(WeeklyAuthorityRendering.cardSurfaceOpacity(for: advancedAuthority))
            Divider().background(PremiumColor.border)

            // Confidence
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("資料完整度")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    if semanticConfidence < 0.6 {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(PremiumColor.gold)
                            Text("部分訓練心率樣本不足，數據僅供參考")
                                .font(.caption)
                                .foregroundStyle(PremiumColor.gold.opacity(0.9))
                        }
                    }
                }
                Spacer()
                ConfidenceRingView(
                    confidence: semanticConfidence,
                    color: semanticConfidence < 0.6 ? PremiumColor.gold : PremiumColor.emerald
                )
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    private var adaptationInferenceChipColor: Color {
        switch adaptation.inferenceClass {
        case .bounded: return PremiumColor.skyBlue
        case .weak: return PremiumColor.gold
        case .unsupported: return .gray
        }
    }

    private var stateInferenceChipColor: Color {
        switch trainingState.inferenceClass {
        case .bounded: return PremiumColor.skyBlue
        case .weak: return PremiumColor.gold
        case .unsupported: return .gray
        }
    }

    private func authorityChipColor(for authority: WeeklyDecisionAuthority) -> Color {
        switch authority {
        case .observational: return PremiumColor.emerald
        case .boundedInference: return PremiumColor.skyBlue
        case .weakInference: return PremiumColor.gold
        }
    }

    private func minimumAuthority(_ lhs: WeeklyDecisionAuthority, _ rhs: WeeklyDecisionAuthority) -> WeeklyDecisionAuthority {
        let rank: [WeeklyDecisionAuthority: Int] = [
            .weakInference: 0,
            .boundedInference: 1,
            .observational: 2
        ]
        return (rank[lhs, default: 0] <= rank[rhs, default: 0]) ? lhs : rhs
    }
}

private struct StateProgressionBar: View {
    let currentState: TrainingState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrainingState.progression, id: \.rawValue) { state in
                    Text(state.localizedLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state == currentState ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((state == currentState ? PremiumColor.skyBlue : Color.gray).opacity(state == currentState ? 0.2 : 0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke((state == currentState ? PremiumColor.skyBlue : Color.gray).opacity(0.35), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 28d trend UI helpers

extension WeeklyAdaptationDirection {
    var shortLabel: String {
        switch self {
        case .enduranceBuild:  return "有氧建設"
        case .maintenance:     return "維持期"
        case .mixedAdaptation: return "混合適應"
        case .recoveryBiased:  return "恢復優先"
        case .noSignal:        return "無方向訊號"
        }
    }
}

extension AdaptationTrend28d {
    var chipLabel: String {
        isStrong ? "28d: \(dominantDirection.shortLabel)" : "28d ↗ \(dominantDirection.shortLabel)"
    }

    var chipColor: Color {
        isStrong ? PremiumColor.skyBlue : PremiumColor.gold
    }

    var rationaleText: String {
        let consistCount = max(1, Int((consistencyRatio * Double(qualifyingWeekCount)).rounded()))
        let suffix = isStrong ? "，方向一致性偏強。" : "，方向尚不穩定。"
        return "近 4 週有效資料 \(qualifyingWeekCount) 週，其中 \(consistCount) 週觀察到「\(dominantDirection.shortLabel)」型態\(suffix)"
    }
}

// MARK: - Goal alignment UI helpers

extension UserTrainingGoal {
    var localizedLabel: String {
        switch self {
        case .aerobicBase:    return "有氧基礎"
        case .strengthFocus:  return "肌力為主"
        case .fatLossRecomp:  return "體脂調整"
        case .performancePeak: return "競技準備"
        case .activeRecovery: return "主動恢復"
        }
    }

    var chipLabel: String { "目標：\(localizedLabel)" }
}

extension GoalAlignmentSignal {
    var localizedLabel: String {
        switch self {
        case .aligned:              return "型態一致"
        case .partiallyAligned:     return "部分一致"
        case .divergent:            return "型態偏差"
        case .insufficientEvidence: return "訓練不足"
        }
    }

    var chipColor: Color {
        switch self {
        case .aligned:              return PremiumColor.emerald
        case .partiallyAligned:     return PremiumColor.gold
        case .divergent:            return PremiumColor.redOrange
        case .insufficientEvidence: return .gray
        }
    }

    // Observational wording: describes pattern consistency only.
    // No achievement, prediction, or causal claim.
    func observationalLabel(for goal: UserTrainingGoal) -> String {
        switch (self, goal) {
        case (.aligned, .aerobicBase):     return "本週低強度佔比偏高，與有氧基礎方向一致"
        case (.aligned, .strengthFocus):   return "本週肌力訓練頻率符合以肌力為主的方向"
        case (.aligned, .fatLossRecomp):   return "本週訓練刺激與頻率與體脂調整型態一致"
        case (.aligned, .performancePeak): return "本週負荷量與強度與競技準備期型態一致"
        case (.aligned, .activeRecovery):  return "本週休息比例偏高，符合主動恢復期安排"
        case (.partiallyAligned, .aerobicBase):     return "有氧偏重訊號部分符合，強度分布仍有調整空間"
        case (.partiallyAligned, .strengthFocus):   return "肌力訓練頻率偏低，可增加肌力課次比例"
        case (.partiallyAligned, .fatLossRecomp):   return "訓練刺激部分符合，可適度提高訓練頻率"
        case (.partiallyAligned, .performancePeak): return "負荷量或強度低於競技準備期預期"
        case (.partiallyAligned, .activeRecovery):  return "仍有部分中高強度課次，可再調低負荷"
        case (.divergent, .aerobicBase):     return "本週高強度比例偏高，與有氧基礎週期化方向有偏差"
        case (.divergent, .strengthFocus):   return "本週無肌力訓練課次，與目標方向不一致"
        case (.divergent, .fatLossRecomp):   return "訓練頻率不足，週次刺激偏少"
        case (.divergent, .performancePeak): return "本週訓練量偏少，與競技準備強度不符"
        case (.divergent, .activeRecovery):  return "高強度或高頻率訓練，與主動恢復期型態不符"
        case (.insufficientEvidence, _):     return "本週訓練量不足，無法判定型態一致性"
        }
    }
}
