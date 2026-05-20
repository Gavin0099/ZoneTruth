import Foundation
import ZoneTruthCore

enum PrimaryIntent: String, Codable, Equatable, Sendable {
    case zone2
    case vo2Max
    case strength
    case activity
}

struct WorkoutEvaluation: Codable, Equatable, Sendable {
    let primaryIntent: PrimaryIntent
    let trainingTendency: String
    let goalFitScore: Int
    let classificationConfidence: Int
    let evaluationConfidence: Int
    let keyFindings: [String]
    let nextAction: String
    let secondarySignals: [String]
    let legacyPassFail: Bool

    var goalFitLabel: String {
        "目標符合度 \(goalFitScore)%"
    }
}

enum WorkoutEvaluationAdapter {
    static func mapLegacyAnalysisToEvaluation(
        primaryIntentBaseline: TrainingIntent,
        legacy: AnalysisResult
    ) -> WorkoutEvaluation {
        let primaryIntent = mapPrimaryIntent(primaryIntentBaseline)
        let tendency = trainingTendency(primaryIntent: primaryIntent, distribution: legacy.zoneDistribution)
        let classificationConfidence = boundedPercent(Int((legacy.confidence * 100).rounded()))

        var evaluationConfidence = classificationConfidence
        if legacy.stabilityStandardDeviation == nil { evaluationConfidence -= 10 }
        if legacy.driftRatio == nil { evaluationConfidence -= 10 }
        evaluationConfidence = boundedPercent(evaluationConfidence)

        let goalFitScore = boundedPercent(scoreForVerdict(legacy.verdict, confidence: evaluationConfidence))
        let keyFindings = primaryFindings(from: legacy, limit: 2)
        let nextAction = primaryNextAction(from: legacy)
        let secondarySignals = secondarySignals(from: legacy)

        return WorkoutEvaluation(
            primaryIntent: primaryIntent,
            trainingTendency: tendency,
            goalFitScore: goalFitScore,
            classificationConfidence: classificationConfidence,
            evaluationConfidence: evaluationConfidence,
            keyFindings: keyFindings,
            nextAction: nextAction,
            secondarySignals: secondarySignals,
            legacyPassFail: legacy.verdict == .pass
        )
    }

    private static func mapPrimaryIntent(_ intent: TrainingIntent) -> PrimaryIntent {
        switch intent {
        case .zone2: return .zone2
        case .vo2Interval: return .vo2Max
        case .strength: return .strength
        case .activityReview: return .activity
        }
    }

    private static func trainingTendency(primaryIntent: PrimaryIntent, distribution: ZoneDistribution) -> String {
        let zone3 = distribution.ratio(for: .zone3)
        let highIntensity = distribution.ratio(for: .zone4) + distribution.ratio(for: .zone5)

        switch primaryIntent {
        case .zone2:
            if zone3 >= 0.20 { return "偏混合有氧訓練" }
            if zone3 >= 0.10 { return "偏 Zone 2 但強度略高" }
            return "偏穩定有氧訓練"
        case .vo2Max:
            if highIntensity > 0.10 { return "偏高強度間歇訓練" }
            if highIntensity >= 0.05 { return "偏中高強度有氧訓練" }
            return "偏穩態有氧訓練"
        case .strength:
            if highIntensity > 0.20 { return "偏代謝循環訓練" }
            return "偏傳統肌力訓練"
        case .activity:
            return "偏一般活動訓練"
        }
    }

    private static func scoreForVerdict(_ verdict: AnalysisVerdict, confidence: Int) -> Int {
        let base: Int
        switch verdict {
        case .pass: base = 80
        case .warning: base = 60
        case .fail: base = 40
        }
        let confidenceAdjustment = (confidence - 70) / 4
        return base + confidenceAdjustment
    }

    private static func primaryFindings(from legacy: AnalysisResult, limit: Int) -> [String] {
        let normalized = legacy.reasons.map(normalizeCoachTone)
        return Array(normalized.prefix(limit))
    }

    private static func primaryNextAction(from legacy: AnalysisResult) -> String {
        if let first = legacy.recommendations.first {
            return normalizeCoachTone(first)
        }
        return "下次先以可穩定維持的配速開始，再逐步調整強度。"
    }

    private static func secondarySignals(from legacy: AnalysisResult) -> [String] {
        var signals: [String] = []
        let zone3 = legacy.zoneDistribution.ratio(for: .zone3) * 100
        let zone4plus = (legacy.zoneDistribution.ratio(for: .zone4) + legacy.zoneDistribution.ratio(for: .zone5)) * 100

        signals.append(String(format: "Zone 3 比例 %.0f%%", zone3))
        signals.append(String(format: "Zone 4/5 比例 %.0f%%", zone4plus))

        if let drift = legacy.driftRatio {
            signals.append(String(format: "心率飄移 %.1f%%", drift * 100))
        } else {
            signals.append("心率飄移資料不足")
        }

        if let stability = legacy.stabilityStandardDeviation {
            signals.append(String(format: "心率標準差 %.1f bpm", stability))
        } else {
            signals.append("心率穩定度資料不足")
        }

        return signals
    }

    private static func normalizeCoachTone(_ text: String) -> String {
        text
            .replacingOccurrences(of: "未達標", with: "與目標有偏離")
            .replacingOccurrences(of: "失敗", with: "偏離")
            .replacingOccurrences(of: "強度太高了", with: "強度偏高")
    }

    private static func boundedPercent(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}
