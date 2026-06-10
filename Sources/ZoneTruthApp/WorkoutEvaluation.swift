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
    let maxHeartRateBPM: Double?
    let activeCaloriesKcal: Double?
    let totalDistanceMeters: Double?

    init(
        primaryIntent: PrimaryIntent,
        classificationConfidence: Int,
        evaluationConfidence: Int,
        zoneDistribution: ZoneDistribution,
        stabilityStandardDeviation: Double?,
        driftRatio: Double?,
        maxHeartRateBPM: Double? = nil,
        activeCaloriesKcal: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        self.primaryIntent = primaryIntent
        self.classificationConfidence = classificationConfidence
        self.evaluationConfidence = evaluationConfidence
        self.zoneDistribution = zoneDistribution
        self.stabilityStandardDeviation = stabilityStandardDeviation
        self.driftRatio = driftRatio
        self.maxHeartRateBPM = maxHeartRateBPM
        self.activeCaloriesKcal = activeCaloriesKcal
        self.totalDistanceMeters = totalDistanceMeters
    }
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
            driftRatio: primitives.driftRatio,
            maxHeartRateBPM: primitives.maxHeartRateBPM,
            activeCaloriesKcal: primitives.activeCaloriesKcal,
            totalDistanceMeters: primitives.totalDistanceMeters
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

        if let maxHR = observation.maxHeartRateBPM {
            signals.append(String(format: "最高心率 %.0f bpm", maxHR))
        }

        if let kcal = observation.activeCaloriesKcal {
            signals.append(String(format: "消耗 %.0f 大卡", kcal))
        }

        if let meters = observation.totalDistanceMeters, meters > 0 {
            if meters >= 1000 {
                signals.append(String(format: "距離 %.2f km", meters / 1000))
            } else {
                signals.append(String(format: "距離 %.0f m", meters))
            }
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
            tendency = "穩定有氧中夾帶較多變速"
            score = 42
            findings = ["中高強度停留偏多，和穩定有氧的目標有些距離。", "後段狀態仍要和整體強度一起看，先不用單看一個指標下結論。"]
            nextAction = "如果這次想更偏穩定有氧，下次可先把配速或阻力再保守一些，減少長時間往上衝。"
        } else if zone3 >= 0.10 {
            tendency = "穩定有氧為主，但強度略高"
            score = 58
            findings = ["中高強度停留比預期稍多，純度還可以再拉回來。", drift < 0.05 ? "後段整體仍算穩，耐力節奏沒有明顯散掉。" : "後段心率有些上浮，代表強度可能慢慢墊高。"]
            nextAction = "下次前段先保守一點，讓心率更早穩住，整體會更接近想要的有氧節奏。"
        } else {
            tendency = "穩定有氧表現穩定"
            score = 82
            findings = ["整體大多維持在穩定有氧範圍內，節奏維持得不錯。", "心率波動與後段變化都在可接受範圍。"]
            nextAction = "目前節奏可以延續；如果身體感受穩定，下次可再小幅拉長時間。"
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
            tendency = "高強度刺激明確"
            score = 84
            findings = ["高強度停留時間足夠，這次確實有做到刺激。"]
            nextAction = "這樣的結構可以延續；下次可以多觀察每組之間恢復是否有跟上。"
        } else if highIntensity >= 0.05 {
            tendency = "有高強度刺激，但密度還不高"
            score = 64
            findings = ["有進入高強度區，但總量仍偏中等。", "如果這次目標是強刺激，密度還有再往上調的空間。"]
            nextAction = "若這次本來就想做高強度刺激，下次可考慮把工作段再做得更完整一些。"
        } else {
            tendency = "整體更像穩定有氧"
            score = 45
            findings = ["高強度停留不多，整體更像穩定有氧而不是強刺激課。"]
            nextAction = "若這次原本是想做高強度刺激，下次可考慮把工作段拉得更明確一些。"
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
        let tendency = highIntensity > 0.20 ? "較像代謝循環型肌力" : "偏典型肌力訓練節奏"
        let score = highIntensity > 0.20 ? 46 : 78
        let findings = highIntensity > 0.20
            ? ["高心率停留較多，整體更像連續循環式刺激。"]
            : ["整體節奏較接近有休息分段的肌力訓練。"]
        let nextAction = highIntensity > 0.20
            ? "如果你想更偏純肌力，下次可把組間休息再拉長一些。"
            : "目前節奏可以延續，之後可再觀察組間恢復是否穩定。"
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
            nextAction: "若想做更明確的訓練判讀，可先指定這次更接近有氧、高強度或肌力。"
        )
    }
}
