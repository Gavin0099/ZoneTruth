import Foundation
import ZoneTruthCore

enum PrimaryIntent: String, Codable, Equatable, Sendable {
    case zone2
    case vo2Max
    case strength
    case activity
}

struct WorkoutObservation: Equatable, Sendable {
    let primaryIntent: PrimaryIntent
    let classificationConfidence: Int
    let evaluationConfidence: Int
    let zoneDistribution: ZoneDistribution
    let stabilityStandardDeviation: Double?
    let driftRatio: Double?
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

protocol WorkoutEvaluationPolicy {
    func evaluate(_ observation: WorkoutObservation) -> WorkoutEvaluation
}

enum WorkoutEvaluationPolicyFactory {
    static func make(for primaryIntent: PrimaryIntent) -> WorkoutEvaluationPolicy {
        switch primaryIntent {
        case .zone2:
            return Zone2EvaluationPolicy()
        case .vo2Max:
            return VO2EvaluationPolicy()
        case .strength:
            return StrengthEvaluationPolicy()
        case .activity:
            return ActivityEvaluationPolicy()
        }
    }
}

enum ObservationBridge {
    static func intent(from training: TrainingIntent) -> PrimaryIntent {
        switch training {
        case .zone2: return .zone2
        case .vo2Interval: return .vo2Max
        case .strength: return .strength
        case .activityReview: return .activity
        }
    }

    static func observation(
        from primitives: WorkoutObservationPrimitives,
        intent: PrimaryIntent
    ) -> WorkoutObservation {
        let classificationConfidence = primitives.sampleQuality == .sufficient ? 80 : 55
        var evaluationConfidence = primitives.sampleQuality == .sufficient ? 75 : 50
        if primitives.driftRatio == nil { evaluationConfidence -= 10 }
        if primitives.stabilityStandardDeviation == nil { evaluationConfidence -= 10 }
        evaluationConfidence = max(evaluationConfidence, 30)
        return WorkoutObservation(
            primaryIntent: intent,
            classificationConfidence: classificationConfidence,
            evaluationConfidence: evaluationConfidence,
            zoneDistribution: primitives.zoneDistribution,
            stabilityStandardDeviation: primitives.stabilityStandardDeviation,
            driftRatio: primitives.driftRatio
        )
    }
}

enum WorkoutEvaluationAdapter {
    static func mapLegacyAnalysisToEvaluation(
        primaryIntentBaseline: TrainingIntent,
        legacy: AnalysisResult
    ) -> WorkoutEvaluation {
        let primaryIntent = ObservationBridge.intent(from: primaryIntentBaseline)
        let classificationConfidence = boundedPercent(Int((legacy.confidence * 100).rounded()))
        var evaluationConfidence = classificationConfidence
        if legacy.stabilityStandardDeviation == nil { evaluationConfidence -= 10 }
        if legacy.driftRatio == nil { evaluationConfidence -= 10 }
        evaluationConfidence = boundedPercent(evaluationConfidence)
        let observation = WorkoutObservation(
            primaryIntent: primaryIntent,
            classificationConfidence: classificationConfidence,
            evaluationConfidence: evaluationConfidence,
            zoneDistribution: legacy.zoneDistribution,
            stabilityStandardDeviation: legacy.stabilityStandardDeviation,
            driftRatio: legacy.driftRatio
        )
        return WorkoutEvaluationPolicyFactory.make(for: primaryIntent).evaluate(observation)
    }

    private static func boundedPercent(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

private protocol SharedEvaluationLogic {}

private extension SharedEvaluationLogic {
    func buildEvaluation(
        from observation: WorkoutObservation,
        trainingTendency: String,
        goalFitScore: Int,
        keyFindings: [String],
        nextAction: String
    ) -> WorkoutEvaluation {
        let secondarySignals = secondarySignals(from: observation)

        return WorkoutEvaluation(
            primaryIntent: observation.primaryIntent,
            trainingTendency: trainingTendency,
            goalFitScore: boundedPercent(goalFitScore),
            classificationConfidence: observation.classificationConfidence,
            evaluationConfidence: observation.evaluationConfidence,
            keyFindings: Array(keyFindings.prefix(2)).map(normalizeCoachTone),
            nextAction: normalizeCoachTone(nextAction),
            secondarySignals: secondarySignals,
            legacyPassFail: goalFitScore >= 70
        )
    }

    func secondarySignals(from observation: WorkoutObservation) -> [String] {
        var signals: [String] = []
        let zone3 = observation.zoneDistribution.ratio(for: .zone3) * 100
        let zone4plus = (observation.zoneDistribution.ratio(for: .zone4) + observation.zoneDistribution.ratio(for: .zone5)) * 100

        signals.append(String(format: "Zone 3 比例 %.0f%%", zone3))
        signals.append(String(format: "Zone 4/5 比例 %.0f%%", zone4plus))

        if let drift = observation.driftRatio {
            signals.append(String(format: "心率飄移 %.1f%%", drift * 100))
        } else {
            signals.append("心率飄移資料不足")
        }

        if let stability = observation.stabilityStandardDeviation {
            signals.append(String(format: "心率標準差 %.1f bpm", stability))
        } else {
            signals.append("心率穩定度資料不足")
        }

        return signals
    }

    func normalizeCoachTone(_ text: String) -> String {
        text
            .replacingOccurrences(of: "未達標", with: "與目標有偏離")
            .replacingOccurrences(of: "失敗", with: "偏離")
            .replacingOccurrences(of: "強度太高了", with: "強度偏高")
    }

    func boundedPercent(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

private struct Zone2EvaluationPolicy: WorkoutEvaluationPolicy, SharedEvaluationLogic {
    func evaluate(_ observation: WorkoutObservation) -> WorkoutEvaluation {
        let zone3 = observation.zoneDistribution.ratio(for: .zone3)
        let drift = observation.driftRatio ?? 0
        let tendency: String
        let score: Int
        let findings: [String]
        let nextAction: String

        if zone3 >= 0.20 {
            tendency = "偏混合有氧訓練"
            score = 42
            findings = ["Zone 3 比例偏高，與 Zone 2 目標有偏離。", "心率飄移穩定性需搭配整體強度一起看。"]
            nextAction = "若目標是 Zone 2，請降低配速或阻力，避免長時間停留在 Zone 3。"
        } else if zone3 >= 0.10 {
            tendency = "偏 Zone 2 但強度略高"
            score = 58
            findings = ["Zone 3 比例偏高，Zone 2 純度不足。", drift < 0.05 ? "心率飄移低，耐力穩定性仍不錯。" : "心率飄移略高，後段有強度上浮。"]
            nextAction = "前段先保守 5-10 分鐘，將心率穩定控制在 Zone 2 上緣以下。"
        } else {
            tendency = "偏穩定有氧訓練"
            score = 82
            findings = ["Zone 2 佔比為主，整體強度分布穩定。", "心率飄移與波動在可接受範圍。"]
            nextAction = "維持目前節奏，下一次可小幅延長訓練時間。"
        }
        return buildEvaluation(
            from: observation,
            trainingTendency: tendency,
            goalFitScore: score + (observation.evaluationConfidence - 70) / 5,
            keyFindings: findings,
            nextAction: nextAction
        )
    }
}

private struct VO2EvaluationPolicy: WorkoutEvaluationPolicy, SharedEvaluationLogic {
    func evaluate(_ observation: WorkoutObservation) -> WorkoutEvaluation {
        let highIntensity = observation.zoneDistribution.ratio(for: .zone4) + observation.zoneDistribution.ratio(for: .zone5)
        let tendency: String
        let score: Int
        let findings: [String]
        let nextAction: String
        if highIntensity > 0.10 {
            tendency = "偏高強度間歇訓練"
            score = 84
            findings = ["Zone 4/5 佔比足夠，符合高強度刺激需求。"]
            nextAction = "維持間歇品質，下一次優先確保每組恢復完整。"
        } else if highIntensity >= 0.05 {
            tendency = "偏中高強度有氧訓練"
            score = 64
            findings = ["有進入高強度區，但總量仍偏中等。", "與標準 VO2 間歇相比，刺激密度略不足。"]
            nextAction = "下次提高間歇段強度或延長高強度停留時間。"
        } else {
            tendency = "偏穩態有氧訓練"
            score = 45
            findings = ["高強度區停留不足，較不像 VO2 間歇訓練。"]
            nextAction = "若目標是 VO2，請增加衝刺段強度，確保進入 Zone 4/5。"
        }
        return buildEvaluation(
            from: observation,
            trainingTendency: tendency,
            goalFitScore: score + (observation.evaluationConfidence - 70) / 5,
            keyFindings: findings,
            nextAction: nextAction
        )
    }
}

private struct StrengthEvaluationPolicy: WorkoutEvaluationPolicy, SharedEvaluationLogic {
    func evaluate(_ observation: WorkoutObservation) -> WorkoutEvaluation {
        let highIntensity = observation.zoneDistribution.ratio(for: .zone4) + observation.zoneDistribution.ratio(for: .zone5)
        let tendency = highIntensity > 0.20 ? "偏代謝循環訓練" : "偏傳統肌力訓練"
        let score = highIntensity > 0.20 ? 46 : 78
        let findings = highIntensity > 0.20
            ? ["高強度停留較多，整體較偏代謝循環刺激。"]
            : ["強度分布較接近傳統肌力訓練節奏。"]
        let nextAction = highIntensity > 0.20
            ? "若目標是純肌力，請拉長組間休息，降低連續高心率時間。"
            : "維持目前訓練節奏，並觀察組間恢復是否穩定。"
        return buildEvaluation(
            from: observation,
            trainingTendency: tendency,
            goalFitScore: score + (observation.evaluationConfidence - 70) / 6,
            keyFindings: findings,
            nextAction: nextAction
        )
    }
}

private struct ActivityEvaluationPolicy: WorkoutEvaluationPolicy, SharedEvaluationLogic {
    func evaluate(_ observation: WorkoutObservation) -> WorkoutEvaluation {
        buildEvaluation(
            from: observation,
            trainingTendency: "偏一般活動訓練",
            goalFitScore: 72 + (observation.evaluationConfidence - 70) / 8,
            keyFindings: ["本次為一般活動型態，建議以描述性回顧為主。"],
            nextAction: "若需要嚴格訓練品質評估，請改用明確訓練目標（Zone2/VO2/Strength）。"
        )
    }
}
