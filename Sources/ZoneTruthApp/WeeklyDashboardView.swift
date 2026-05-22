import SwiftUI
import ZoneTruthCore

enum WeeklyDecisionAuthority: String {
    case observational = "Direct observation"
    case boundedInference = "Bounded inference"
    case weakInference = "Weak inference"
}

enum WeeklyInferenceClass: String {
    case bounded = "Bounded inference"
    case weak = "Weak inference"
    case unsupported = "Unsupported speculation"
}

enum WeeklyDataFreshness: String {
    case fresh = "fresh"
    case partial = "partial"
    case stale = "stale"
    case missing = "missing"

    var label: String {
        switch self {
        case .fresh: return "Data fresh"
        case .partial: return "Data partial"
        case .stale: return "Data stale"
        case .missing: return "Data missing"
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
}

enum WeeklyInferenceClassifier {
    static func classify(
        confidence: Double,
        freshness: WeeklyDataFreshness,
        workoutCount: Int,
        elapsedDays: Int
    ) -> WeeklyInferenceClass {
        if freshness == .missing || workoutCount == 0 || elapsedDays == 0 {
            return .unsupported
        }
        if freshness == .stale || confidence < 0.6 {
            return .weak
        }
        return .bounded
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

    static func from(summary: WeeklyWorkoutSummary, policy: WeeklyLoadPolicy, freshness: WeeklyDataFreshness) -> WeeklyTrainingStateSignal {
        let authority = WeeklyAuthorityRendering.authority(for: policy.confidence, freshness: freshness)
        let inferenceClass = WeeklyInferenceClassifier.classify(
            confidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays
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

    static func from(summary: WeeklyWorkoutSummary, policy: WeeklyLoadPolicy, freshness: WeeklyDataFreshness) -> WeeklyAdaptationSignal {
        let authority = WeeklyAuthorityRendering.authority(for: policy.confidence, freshness: freshness)
        let inferenceClass = WeeklyInferenceClassifier.classify(
            confidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays
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
                        freshness: freshness
                    )
                    WeeklyDistributionCard(summary: viewModel.weeklySummary)
                    WeeklyAdvancedCard(
                        summary: viewModel.weeklySummary,
                        policy: viewModel.weeklyPolicy,
                        freshness: freshness,
                        bodyCompositionLedger: viewModel.bodyCompositionLedger
                    )
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
    private var authority: WeeklyDecisionAuthority {
        WeeklyAuthorityRendering.authority(for: policy.confidence, freshness: freshness)
    }
    private var inferenceClass: WeeklyInferenceClass {
        WeeklyInferenceClassifier.classify(
            confidence: policy.confidence,
            freshness: freshness,
            workoutCount: summary.workoutCount,
            elapsedDays: summary.elapsedDays
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
                    EvidenceChip(label: inferenceClass.rawValue, color: inferenceChipColor)
                    EvidenceChip(label: freshness.label, color: freshnessChipColor)
                    if policy.confidence < 0.6 || freshness == .stale || freshness == .missing {
                        EvidenceChip(label: "Evidence gap", color: PremiumColor.gold)
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
    private var adaptation: WeeklyAdaptationSignal {
        WeeklyAdaptationSignal.from(summary: summary, policy: policy, freshness: freshness)
    }
    private var reminderLevel: NonAuthorityReminderLevel {
        NonAuthorityReminderPolicy.level(inference: adaptation.inferenceClass, freshness: freshness)
    }
    private var trainingState: WeeklyTrainingStateSignal {
        WeeklyTrainingStateSignal.from(summary: summary, policy: policy, freshness: freshness)
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
                    EvidenceChip(label: adaptation.inferenceClass.rawValue, color: adaptationInferenceChipColor)
                    Text(adaptation.direction.admissibleLabel(for: adaptation.authority))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                // Coverage layer: temporal scope chips (evidence window transparency)
                HStack(spacing: 6) {
                    ForEach(adaptation.temporalScopes.map(\.label), id: \.self) { label in
                        EvidenceChip(label: label, color: .gray)
                    }
                }
                Text(adaptation.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if reminderLevel != .none {
                    Text(reminderLevel.message)
                        .font(.caption2)
                        .foregroundStyle(reminderLevel.color)
                        .padding(reminderLevel == .strong ? 8 : 0)
                        .background(PremiumColor.gold.opacity(reminderLevel.backgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider().background(PremiumColor.border)

            VStack(alignment: .leading, spacing: 8) {
                Text("訓練狀態")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 8) {
                    EvidenceChip(label: trainingState.inferenceClass.rawValue, color: stateInferenceChipColor)
                    Text(trainingState.state.admissibleLabel(for: trainingState.authority))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Text(trainingState.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Divider().background(PremiumColor.border)

            // Long-term body composition context
            if let ledger = bodyCompositionLedger {
                BodyCompositionContextSection(ledger: ledger)
                Divider().background(PremiumColor.border)
            }

            // Confidence
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("資料完整度")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    if policy.confidence < 0.6 {
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
                    confidence: policy.confidence,
                    color: policy.confidence < 0.6 ? PremiumColor.gold : PremiumColor.emerald
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
}
