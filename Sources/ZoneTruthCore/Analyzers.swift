import Foundation

public enum HeartRateSampleSanitizer {
    public static func sanitize(_ samples: [HeartRateSample], policy: AnalysisPolicy) -> [HeartRateSample] {
        guard !samples.isEmpty else { return [] }

        let filteredSpikes = samples.enumerated().filter { index, sample in
            guard index > 0 else { return true }
            let previous = samples[index - 1]
            return abs(sample.bpm - previous.bpm) <= policy.abnormalSpikeDeltaBPM
        }.map(\.element)

        guard
            let first = filteredSpikes.first?.timestamp,
            let last = filteredSpikes.last?.timestamp
        else {
            return []
        }

        let warmupCutoff = first.addingTimeInterval(policy.warmupExclusionSeconds)
        let cooldownCutoff = last.addingTimeInterval(-policy.cooldownExclusionSeconds)

        return filteredSpikes.filter { sample in
            sample.timestamp >= warmupCutoff && sample.timestamp <= cooldownCutoff
        }
    }
}

public enum ZoneDistributionAnalyzer {
    public static func analyze(samples: [HeartRateSample], zoneBounds: ZoneBounds) -> ZoneDistribution {
        var counts = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map { ($0, 0) })
        guard !samples.isEmpty else {
            return ZoneDistribution(counts: counts, ratios: [:])
        }

        for sample in samples {
            counts[zoneBounds.zone(for: sample.bpm), default: 0] += 1
        }

        let total = Double(samples.count)
        let ratios = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map { zone in
            (zone, Double(counts[zone, default: 0]) / total)
        })

        return ZoneDistribution(counts: counts, ratios: ratios)
    }

    public static func merge(_ distributions: [ZoneDistribution]) -> ZoneDistribution {
        var mergedCounts = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map { ($0, 0) })
        for distribution in distributions {
            for zone in TrainingZone.allCases {
                mergedCounts[zone, default: 0] += distribution.counts[zone, default: 0]
            }
        }
        let total = Double(mergedCounts.values.reduce(0, +))
        guard total > 0 else {
            return ZoneDistribution(counts: mergedCounts, ratios: [:])
        }
        let ratios = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map { zone in
            (zone, Double(mergedCounts[zone, default: 0]) / total)
        })
        return ZoneDistribution(counts: mergedCounts, ratios: ratios)
    }
}

public enum Zone3LeakageAnalyzer {
    public static func verdict(for distribution: ZoneDistribution) -> AnalysisVerdict {
        let zone3Ratio = distribution.ratio(for: .zone3)
        if zone3Ratio > 0.20 { return .fail }
        if zone3Ratio >= 0.10 { return .warning }
        return .pass
    }

    public static func boundaryLabel(for distribution: ZoneDistribution) -> String? {
        let zone3Ratio = distribution.ratio(for: .zone3)
        if zone3Ratio >= 0.08 && zone3Ratio < 0.10 {
            return "Zone 3 比例接近 10% 提醒線，這次仍屬於可接受範圍，但已接近 Zone 2 純度下降的邊界。"
        }
        if zone3Ratio >= 0.10 && zone3Ratio < 0.12 {
            return "Zone 3 比例剛超過 10% 提醒線，屬於輕微偏高，建議先視為配速微調訊號。"
        }
        if zone3Ratio >= 0.18 && zone3Ratio <= 0.20 {
            return "Zone 3 比例接近 20% 失敗線，這次尚未超過失敗閾值，但已接近偏離 Zone 2 訓練的上緣。"
        }
        if zone3Ratio > 0.20 && zone3Ratio <= 0.22 {
            return "Zone 3 比例剛超過 20% 失敗線，判定為偏離 Zone 2；這是邊界附近的失敗訊號，不代表整體能力退步。"
        }
        return nil
    }
}

public enum HeartRateStabilityAnalyzer {
    public static func standardDeviation(for samples: [HeartRateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let values = samples.map(\.bpm)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    public static func verdict(for samples: [HeartRateSample], policy: AnalysisPolicy) -> AnalysisVerdict {
        guard let stdDev = standardDeviation(for: samples) else { return .fail }
        if stdDev < policy.lowStabilityStdDev { return .pass }
        if stdDev <= policy.mediumStabilityStdDev { return .warning }
        return .fail
    }
}

public enum HeartRateDriftAnalyzer {
    public static func driftRatio(for samples: [HeartRateSample]) -> Double? {
        guard samples.count >= 2 else { return nil }
        let midpoint = samples.count / 2
        let firstHalf = Array(samples[..<midpoint])
        let secondHalf = Array(samples[midpoint...])
        guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return nil }

        let firstAverage = firstHalf.map(\.bpm).reduce(0, +) / Double(firstHalf.count)
        let secondAverage = secondHalf.map(\.bpm).reduce(0, +) / Double(secondHalf.count)
        guard firstAverage > 0 else { return nil }
        return (secondAverage - firstAverage) / firstAverage
    }

    public static func verdict(for samples: [HeartRateSample]) -> AnalysisVerdict {
        guard let drift = driftRatio(for: samples) else { return .fail }
        if drift < 0.05 { return .pass }
        if drift <= 0.08 { return .warning }
        return .fail
    }

    public static func boundaryLabel(for driftRatio: Double?) -> String? {
        guard let driftRatio else { return nil }
        if driftRatio >= 0.045 && driftRatio < 0.05 {
            return "心率飄移接近 5% 提醒線，這次仍在穩定範圍內，但後段已有輕微上升跡象。"
        }
        if driftRatio >= 0.05 && driftRatio < 0.055 {
            return "心率飄移剛超過 5% 提醒線，屬於輕微脫鉤訊號，建議觀察是否連續出現。"
        }
        if driftRatio >= 0.075 && driftRatio <= 0.08 {
            return "心率飄移接近 8% 失敗線，這次尚未超過失敗閾值，但後段穩定度已接近上限。"
        }
        if driftRatio > 0.08 && driftRatio <= 0.085 {
            return "心率飄移剛超過 8% 失敗線，判定為偏離穩定有氧狀態；這是邊界附近的失敗訊號。"
        }
        return nil
    }
}

public enum Zone2QualityAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> AnalysisResult {
        let preparedSamples = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy)
        let distribution = ZoneDistributionAnalyzer.analyze(
            samples: preparedSamples,
            zoneBounds: policy.zoneBounds
        )

        var reasons: [String] = []
        var severityScores: [Int] = []

        if workout.durationSeconds < policy.minimumDurationSeconds {
            reasons.append("訓練時間過短，無法進行可靠的 Zone 2 分析。")
            severityScores.append(2)
        }

        if preparedSamples.count < policy.minimumSampleCount {
            let thinDistribution = ZoneDistributionAnalyzer.analyze(samples: preparedSamples, zoneBounds: policy.zoneBounds)
            let rawCount = workout.heartRateSamples.count
            let sampleQuality = TrainingMetricMetadataFactory.sampleQuality(
                rawSampleCount: rawCount,
                preparedSampleCount: preparedSamples.count,
                policy: policy
            )
            let message = rawCount < policy.minimumSampleCount 
                ? "心率樣本數過低（僅 \(rawCount) 筆）。您的裝置可能沒有完整記錄整個運動過程的心率。"
                : "原本的心率樣本數足夠（\(rawCount) 筆），但過多異常的心率突波被過濾掉，僅剩 \(preparedSamples.count) 筆有效樣本，無法分析。"
            
            return AnalysisResult(
                verdict: .fail,
                confidence: 0.3,
                reasons: reasons + [message],
                recommendations: RecommendationEngine.recommendations(
                    for: workout.intent, verdict: .fail, distribution: thinDistribution, driftRatio: nil
                ),
                zoneDistribution: thinDistribution,
                stabilityStandardDeviation: nil,
                driftRatio: nil,
                metricMetadata: [
                    TrainingMetricMetadataFactory.zone2Range(sampleQuality: sampleQuality)
                ]
            )
        }

        let leakageVerdict = Zone3LeakageAnalyzer.verdict(for: distribution)
        switch leakageVerdict {
        case .pass:
            reasons.append("Zone 3 區間的時間比例維持在 10% 以下，強度分布偏穩定。")
            severityScores.append(0)
        case .warning:
            reasons.append("Zone 3 區間的時間比例介於 10% 到 20% 之間，對 Zone 2 訓練來說稍微偏高。")
            severityScores.append(1)
        case .fail:
            reasons.append("Zone 3 區間的時間比例超過 20%，對 Zone 2 目標來說強度偏高。")
            severityScores.append(2)
        }
        if let leakageBoundaryLabel = Zone3LeakageAnalyzer.boundaryLabel(for: distribution) {
            reasons.append(leakageBoundaryLabel)
        }

        let stabilityValue = HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples)
        let stabilityVerdict = HeartRateStabilityAnalyzer.verdict(for: preparedSamples, policy: policy)
        switch stabilityVerdict {
        case .pass:
            reasons.append("在整個分析區間內，心率波動偏低。")
            severityScores.append(0)
        case .warning:
            reasons.append("心率變異度為中等，這表示您的配速或阻力可能不太均勻。")
            severityScores.append(1)
        case .fail:
            reasons.append("心率波動偏大，較不利於維持穩定 Zone 2 型態。")
            severityScores.append(2)
        }

        let driftValue = HeartRateDriftAnalyzer.driftRatio(for: preparedSamples)
        let driftVerdict = HeartRateDriftAnalyzer.verdict(for: preparedSamples)
        switch driftVerdict {
        case .pass:
            reasons.append("前半段與後半段的心率飄移維持在 5% 以下，後段穩定度偏佳。")
            severityScores.append(0)
        case .warning:
            reasons.append("心率飄移介於 5% 到 8% 之間，顯示有輕微的心率脫鉤現象 (Cardiac Drift)。")
            severityScores.append(1)
        case .fail:
            reasons.append("心率飄移超過 8%，顯示後段訓練已經偏離了穩定的有氧狀態。")
            severityScores.append(2)
        }
        if let driftBoundaryLabel = HeartRateDriftAnalyzer.boundaryLabel(for: driftValue) {
            reasons.append(driftBoundaryLabel)
        }

        let verdict = overallVerdict(from: severityScores)
        let confidence = confidenceScore(from: severityScores, sampleCount: preparedSamples.count, policy: policy)

        return AnalysisResult(
            verdict: verdict,
            confidence: confidence,
            reasons: reasons,
            recommendations: RecommendationEngine.recommendations(
                for: workout.intent,
                verdict: verdict,
                distribution: distribution,
                driftRatio: driftValue
            ),
            zoneDistribution: distribution,
            stabilityStandardDeviation: stabilityValue,
            driftRatio: driftValue,
            metricMetadata: [
                TrainingMetricMetadataFactory.zone2Range(sampleQuality: .sufficient)
            ]
        )
    }
}

public enum Zone2ObservationAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> Zone2Observation {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        return analyze(primitives: primitives)
    }

    static func analyze(primitives: WorkoutObservationPrimitives) -> Zone2Observation {
        Zone2Observation(
            zoneDistribution: primitives.zoneDistribution,
            driftRatio: primitives.driftRatio,
            stabilityStandardDeviation: primitives.stabilityStandardDeviation,
            sampleQuality: primitives.sampleQuality
        )
    }
}

public enum VO2IntervalAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> AnalysisResult {
        let preparedSamples = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy)
        let distribution = ZoneDistributionAnalyzer.analyze(
            samples: preparedSamples,
            zoneBounds: policy.zoneBounds
        )

        let highIntensityRatio = distribution.ratio(for: .zone4) + distribution.ratio(for: .zone5)
        let observation = VO2ObservationAnalyzer.analyze(workout: workout, policy: policy)
        
        var verdict: AnalysisVerdict = .pass
        var reasons: [String] = []
        
        if highIntensityRatio > 0.10 {
            verdict = .pass
            reasons.append("在高強度區間 (Zone 4/5) 停留的時間充足，與間歇訓練目標較一致。")
        } else if highIntensityRatio >= 0.05 {
            verdict = .warning
            reasons.append("在高強度區間的時間適中；若目標是 VO2，可考慮微調間歇段強度或時間。")
        } else {
            verdict = .fail
            reasons.append("在高強度區間的時間偏少，較不像典型 VO2 間歇訓練。")
        }

        switch observation.intervalPatternHint {
        case .repeatedPeaks:
            reasons.append("心率型態出現多次高峰，與間歇訓練結構較一致。")
        case .possible:
            reasons.append("心率型態可能包含間歇段，但證據仍偏描述性，需要搭配實際課表確認。")
        case .none:
            reasons.append("心率型態未呈現明顯重複高峰，較不像典型 VO2 間歇結構。")
        }

        return AnalysisResult(
            verdict: verdict,
            confidence: 0.8,
            reasons: reasons,
            recommendations: RecommendationEngine.recommendations(
                for: workout.intent,
                verdict: verdict,
                distribution: distribution,
                driftRatio: nil
            ),
            zoneDistribution: distribution,
            stabilityStandardDeviation: HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples),
            driftRatio: nil,
            metricMetadata: [
                TrainingMetricMetadataFactory.vo2IntervalQuality(sampleQuality: observation.sampleQuality)
            ]
        )
    }
}

public enum VO2ObservationAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> VO2Observation {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        return analyze(primitives: primitives)
    }

    static func analyze(primitives: WorkoutObservationPrimitives) -> VO2Observation {
        let intervalPatternHint: IntervalPatternHint
        if primitives.sampleQuality != .sufficient {
            intervalPatternHint = .possible
        } else if primitives.highIntensityRatio >= 0.20 && primitives.peakZoneRatio >= 0.05 {
            intervalPatternHint = .repeatedPeaks
        } else if primitives.highIntensityRatio < 0.05 {
            intervalPatternHint = .none
        } else {
            intervalPatternHint = .possible
        }

        return VO2Observation(
            zoneDistribution: primitives.zoneDistribution,
            highIntensityRatio: primitives.highIntensityRatio,
            peakZoneRatio: primitives.peakZoneRatio,
            intervalPatternHint: intervalPatternHint,
            sampleQuality: primitives.sampleQuality
        )
    }
}

public enum WorkoutObservationPrimitiveBuilder {
    public static func build(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> WorkoutObservationPrimitives {
        let rawCount = workout.heartRateSamples.count
        let preparedSamples = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy)
        let preparedCount = preparedSamples.count
        let distribution = ZoneDistributionAnalyzer.analyze(samples: preparedSamples, zoneBounds: policy.zoneBounds)
        let drift = HeartRateDriftAnalyzer.driftRatio(for: preparedSamples)
        let stability = HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples)

        let quality: SampleQuality
        if rawCount < policy.minimumSampleCount {
            quality = .sparse
        } else if preparedCount < policy.minimumSampleCount {
            quality = .heavilyFiltered
        } else {
            quality = .sufficient
        }

        let isInsufficient = preparedCount < policy.minimumSampleCount
        let finalDrift = isInsufficient ? nil : drift
        let finalStability = isInsufficient ? nil : stability

        let finalDistribution: ZoneDistribution
        if quality == .sparse {
            let emptyCounts = Dictionary(uniqueKeysWithValues: TrainingZone.allCases.map { ($0, 0) })
            finalDistribution = ZoneDistribution(counts: emptyCounts, ratios: [:])
        } else {
            finalDistribution = distribution
        }

        let highIntensityRatio = finalDistribution.ratio(for: .zone4) + finalDistribution.ratio(for: .zone5)
        let peakZoneRatio = finalDistribution.ratio(for: .zone5)
        let averageHeartRate = preparedSamples.isEmpty
            ? nil
            : preparedSamples.map(\.bpm).reduce(0, +) / Double(preparedSamples.count)
        let maxHeartRateBPM = preparedSamples.isEmpty ? nil : preparedSamples.map(\.bpm).max()
        let highHrSustainedRatio = preparedSamples.isEmpty
            ? 0
            : Double(preparedSamples.filter { $0.bpm >= policy.zoneBounds.zone4Threshold }.count) / Double(preparedSamples.count)

        return WorkoutObservationPrimitives(
            zoneDistribution: finalDistribution,
            sampleQuality: quality,
            driftRatio: finalDrift,
            stabilityStandardDeviation: finalStability,
            highIntensityRatio: highIntensityRatio,
            peakZoneRatio: peakZoneRatio,
            averageHeartRate: averageHeartRate,
            maxHeartRateBPM: maxHeartRateBPM,
            highHrSustainedRatio: highHrSustainedRatio,
            activeCaloriesKcal: workout.activeCaloriesKcal,
            totalDistanceMeters: workout.totalDistanceMeters
        )
    }
}

private enum ObservationComputationGuard {
    // Shared primitive math authority:
    // observation analyzers should consume WorkoutObservationPrimitives and avoid recomputing
    // distribution/drift/ratio directly.
    static let authority = "WorkoutObservationPrimitiveBuilder"
}

public enum StrengthObservationAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> StrengthObservation {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        return analyze(primitives: primitives)
    }

    static func analyze(primitives: WorkoutObservationPrimitives) -> StrengthObservation {
        let hint: RecoveryDropHint
        if primitives.sampleQuality != .sufficient {
            hint = .possible
        } else if primitives.highHrSustainedRatio < 0.25 {
            hint = .visibleDrops
        } else if primitives.highHrSustainedRatio > 0.50 {
            hint = .none
        } else {
            hint = .possible
        }

        return StrengthObservation(
            avgHeartRate: primitives.averageHeartRate,
            highHrSustainedRatio: primitives.highHrSustainedRatio,
            recoveryDropHint: hint,
            sampleQuality: primitives.sampleQuality
        )
    }
}

public enum ActivityObservationAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> ActivityObservation {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        return analyze(workout: workout, primitives: primitives)
    }

    static func analyze(
        workout: WorkoutInput,
        primitives: WorkoutObservationPrimitives
    ) -> ActivityObservation {
        let z2 = primitives.zoneDistribution.ratio(for: .zone2)
        let z3 = primitives.zoneDistribution.ratio(for: .zone3)
        let z4plus = primitives.zoneDistribution.ratio(for: .zone4) + primitives.zoneDistribution.ratio(for: .zone5)

        let movementType: ActivityMovementType
        if z4plus >= 0.20 && z2 <= 0.40 {
            movementType = .intermittent
        } else if z3 >= 0.20 && z2 >= 0.30 {
            movementType = .mixed
        } else {
            movementType = .steady
        }

        return ActivityObservation(
            zoneDistribution: primitives.zoneDistribution,
            movementType: movementType,
            duration: workout.durationSeconds,
            sampleQuality: primitives.sampleQuality
        )
    }
}

public enum TrainingModeClassifier {
    private static let classificationVersion = "training-classification-v3.1-sprint3"

    public static func classify(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default,
        zoneConfigVersion: String? = nil,
        usedPersonalizedZones: Bool = false
    ) -> TrainingClassification {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        let dataQuality = trainingDataQuality(for: workout, primitives: primitives, policy: policy)
        let debug = TrainingClassificationDebug(
            classificationVersion: classificationVersion,
            zoneConfigVersion: zoneConfigVersion,
            usedPersonalizedZones: usedPersonalizedZones,
            ruleScores: ruleScores(for: primitives),
            notes: ["Core-only rule classifier; not connected to UI rendering."]
        )

        if workout.durationSeconds < policy.minimumDurationSeconds {
            return insufficientDataClassification(
                dataQuality: dataQuality,
                evidence: [
                    TrainingClassificationEvidence(
                        label: "運動時間",
                        value: formatDuration(workout.durationSeconds),
                        direction: .weakens,
                        explanation: "運動時間低於本分類器的最低判讀條件。"
                    )
                ],
                warnings: [
                    TrainingClassificationWarning(
                        type: .insufficientDuration,
                        message: "運動時間不足，暫不分類訓練型態。"
                    )
                ],
                debug: debug
            )
        }

        if primitives.sampleQuality != .sufficient {
            return insufficientDataClassification(
                dataQuality: dataQuality,
                evidence: [
                    TrainingClassificationEvidence(
                        label: "心率樣本",
                        value: "\(workout.heartRateSamples.count) 筆",
                        direction: .weakens,
                        explanation: "心率樣本不足或過度過濾，無法穩定判讀訓練型態。"
                    )
                ],
                warnings: [
                    TrainingClassificationWarning(
                        type: .lowHeartRateQuality,
                        message: "心率資料不足，暫不分類訓練型態。"
                    )
                ],
                debug: debug
            )
        }

        switch workout.workoutType {
        case .strengthTraining:
            return classifyStrength(primitives: primitives, dataQuality: dataQuality, debug: debug)
        case .running, .cycling, .walking, .swimming, .mixed, .other:
            return classifyCardioOrActivity(
                workout: workout,
                primitives: primitives,
                dataQuality: dataQuality,
                debug: debug
            )
        }
    }

    private static func classifyStrength(
        primitives: WorkoutObservationPrimitives,
        dataQuality: TrainingDataQuality,
        debug: TrainingClassificationDebug
    ) -> TrainingClassification {
        let averageHR = primitives.averageHeartRate ?? 0
        let highHrRatio = primitives.highHrSustainedRatio
        let highIntensityRatio = primitives.highIntensityRatio
        let isConditioningLike = averageHR >= 130 || highHrRatio >= 0.35 || highIntensityRatio >= 0.20

        if isConditioningLike {
            return TrainingClassification(
                primaryMode: .conditioningLike,
                confidence: confidence(for: dataQuality, strongMatch: true),
                dataQuality: dataQuality,
                claimLevel: .primaryClassification,
                evidence: [
                    TrainingClassificationEvidence(
                        label: "Apple Watch 活動類型",
                        value: "肌力訓練",
                        direction: .neutral,
                        explanation: "活動類型限制候選分類，但心率型態仍可指出是否偏高密度。"
                    ),
                    TrainingClassificationEvidence(
                        label: "高心率比例",
                        value: formatRatio(highHrRatio),
                        direction: .supports,
                        explanation: "重訓活動中高心率比例偏高，較像高密度循環訓練。"
                    ),
                    TrainingClassificationEvidence(
                        label: "平均心率",
                        value: formatBPM(averageHR),
                        direction: .supports,
                        explanation: "平均心率高於典型組間恢復明確的重訓型態。"
                    )
                ],
                notApplicableReasons: [
                    TrainingNotApplicableReason(
                        model: .zone2,
                        reason: .notSteadyStateActivity,
                        message: "重訓不以連續穩定 Zone 2 作為主要判讀。"
                    )
                ],
                debug: debug
            )
        }

        return TrainingClassification(
            primaryMode: .strengthPattern,
            confidence: confidence(for: dataQuality, strongMatch: true),
            dataQuality: dataQuality,
            claimLevel: .primaryClassification,
            evidence: [
                TrainingClassificationEvidence(
                    label: "Apple Watch 活動類型",
                    value: "肌力訓練",
                    direction: .supports,
                    explanation: "活動類型本身支援肌力訓練型態候選。"
                ),
                TrainingClassificationEvidence(
                    label: "高心率比例",
                    value: formatRatio(highHrRatio),
                    direction: .supports,
                    explanation: "高心率區間沒有長時間主導，符合較典型的肌力訓練心率型態。"
                ),
                TrainingClassificationEvidence(
                    label: "平均心率",
                    value: formatBPM(averageHR),
                    direction: .neutral,
                    explanation: "平均心率未觸發高密度循環訓練例外。"
                )
            ],
            notApplicableReasons: [
                TrainingNotApplicableReason(
                    model: .vo2Stimulus,
                    reason: .notSteadyStateActivity,
                    message: "這次沒有先以 VO2 刺激作為重訓主結論。"
                )
            ],
            debug: debug
        )
    }

    private static func classifyCardioOrActivity(
        workout: WorkoutInput,
        primitives: WorkoutObservationPrimitives,
        dataQuality: TrainingDataQuality,
        debug: TrainingClassificationDebug
    ) -> TrainingClassification {
        let zone2Ratio = primitives.zoneDistribution.ratio(for: .zone2)
        let zone3Ratio = primitives.zoneDistribution.ratio(for: .zone3)
        let highIntensityRatio = primitives.highIntensityRatio

        if highIntensityRatio >= 0.20 && primitives.peakZoneRatio >= 0.05 {
            return TrainingClassification(
                primaryMode: .vo2Stimulus,
                confidence: confidence(for: dataQuality, strongMatch: true),
                dataQuality: dataQuality,
                claimLevel: claimLevel(for: dataQuality),
                evidence: [
                    TrainingClassificationEvidence(
                        label: "Zone 4/5 比例",
                        value: formatRatio(highIntensityRatio),
                        direction: .supports,
                        explanation: "高強度心率區間比例足以支援 VO2 刺激型態描述。"
                    )
                ],
                warnings: workout.workoutType == .swimming ? lowSwimQualityWarning() : [],
                debug: debug
            )
        }

        if zone2Ratio >= 0.60 && zone3Ratio <= 0.20 && highIntensityRatio < 0.10 {
            return TrainingClassification(
                primaryMode: .zone2,
                confidence: confidence(for: dataQuality, strongMatch: true),
                dataQuality: dataQuality,
                claimLevel: claimLevel(for: dataQuality),
                evidence: [
                    TrainingClassificationEvidence(
                        label: "Zone 2 比例",
                        value: formatRatio(zone2Ratio),
                        direction: .supports,
                        explanation: "心率分布主要落在 Zone 2 區間。"
                    ),
                    TrainingClassificationEvidence(
                        label: "Zone 3+ 比例",
                        value: formatRatio(zone3Ratio + highIntensityRatio),
                        direction: .supports,
                        explanation: "較高心率區間沒有主導這次活動。"
                    )
                ],
                warnings: workout.workoutType == .swimming ? lowSwimQualityWarning() : [],
                debug: debug
            )
        }

        if primitives.zoneDistribution.ratio(for: .zone1) >= 0.50 && highIntensityRatio < 0.05 {
            return TrainingClassification(
                primaryMode: .generalLowIntensity,
                confidence: confidence(for: dataQuality, strongMatch: false),
                dataQuality: dataQuality,
                claimLevel: claimLevel(for: dataQuality),
                evidence: [
                    TrainingClassificationEvidence(
                        label: "Zone 1 比例",
                        value: formatRatio(primitives.zoneDistribution.ratio(for: .zone1)),
                        direction: .supports,
                        explanation: "活動以低心率區間為主。"
                    )
                ],
                debug: debug
            )
        }

        return TrainingClassification(
            primaryMode: .mixed,
            confidence: confidence(for: dataQuality, strongMatch: false),
            dataQuality: dataQuality,
            claimLevel: claimLevel(for: dataQuality),
            evidence: [
                TrainingClassificationEvidence(
                    label: "心率分布",
                    value: "混合",
                    direction: .neutral,
                    explanation: "心率分布沒有穩定落在單一訓練型態。"
                )
            ],
            warnings: [
                TrainingClassificationWarning(
                    type: .ambiguousPattern,
                    message: "這次心率型態混合，分類僅描述主要傾向。"
                )
            ] + (workout.workoutType == .swimming ? lowSwimQualityWarning() : []),
            debug: debug
        )
    }

    private static func insufficientDataClassification(
        dataQuality: TrainingDataQuality,
        evidence: [TrainingClassificationEvidence],
        warnings: [TrainingClassificationWarning],
        debug: TrainingClassificationDebug
    ) -> TrainingClassification {
        TrainingClassification(
            primaryMode: .insufficientData,
            confidence: .insufficient,
            dataQuality: dataQuality,
            claimLevel: .notApplicable,
            evidence: evidence,
            warnings: warnings,
            notApplicableReasons: [
                TrainingNotApplicableReason(
                    model: .zone2,
                    reason: .insufficientHeartRateData,
                    message: "心率資料不足，Zone 2 型態不適用。"
                ),
                TrainingNotApplicableReason(
                    model: .vo2Stimulus,
                    reason: .insufficientHeartRateData,
                    message: "心率資料不足，VO2 刺激型態不適用。"
                ),
                TrainingNotApplicableReason(
                    model: .strengthPattern,
                    reason: .insufficientHeartRateData,
                    message: "心率資料不足，肌力訓練型態不適用。"
                )
            ],
            debug: debug
        )
    }

    private static func trainingDataQuality(
        for workout: WorkoutInput,
        primitives: WorkoutObservationPrimitives,
        policy: AnalysisPolicy
    ) -> TrainingDataQuality {
        if workout.durationSeconds < policy.minimumDurationSeconds {
            return .insufficient
        }
        switch primitives.sampleQuality {
        case .sufficient:
            return workout.workoutType == .swimming ? .low : .high
        case .heavilyFiltered:
            return .insufficient
        case .sparse:
            return .insufficient
        }
    }

    private static func confidence(
        for dataQuality: TrainingDataQuality,
        strongMatch: Bool
    ) -> ClassificationConfidence {
        switch dataQuality {
        case .high:
            return strongMatch ? .mediumHigh : .medium
        case .medium:
            return strongMatch ? .medium : .low
        case .low:
            return strongMatch ? .low : .low
        case .insufficient:
            return .insufficient
        }
    }

    private static func claimLevel(for dataQuality: TrainingDataQuality) -> TrainingClaimLevel {
        dataQuality == .low ? .secondaryReference : .primaryClassification
    }

    private static func ruleScores(for primitives: WorkoutObservationPrimitives) -> [String: Double] {
        [
            "zone2": primitives.zoneDistribution.ratio(for: .zone2),
            "vo2_stimulus": primitives.highIntensityRatio,
            "conditioning_like": max(primitives.highHrSustainedRatio, primitives.highIntensityRatio),
            "strength_pattern": 1 - primitives.highHrSustainedRatio
        ]
    }

    private static func lowSwimQualityWarning() -> [TrainingClassificationWarning] {
        [
            TrainingClassificationWarning(
                type: .lowHeartRateQuality,
                message: "游泳心率資料較容易受量測限制影響，分類僅供描述參考。"
            )
        ]
    }

    private static func formatRatio(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func formatBPM(_ value: Double) -> String {
        "\(Int(value.rounded())) bpm"
    }

    private static func formatDuration(_ value: TimeInterval) -> String {
        "\(Int((value / 60).rounded())) 分鐘"
    }
}

public enum StrengthAnalyzer {
    public static func analyze(
        workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> AnalysisResult {
        let preparedSamples = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy)
        let distribution = ZoneDistributionAnalyzer.analyze(
            samples: preparedSamples,
            zoneBounds: policy.zoneBounds
        )

        let averageHR = preparedSamples.isEmpty ? 0 : preparedSamples.map(\.bpm).reduce(0, +) / Double(preparedSamples.count)
        let observation = StrengthObservationAnalyzer.analyze(workout: workout, policy: policy)
        
        var verdict: AnalysisVerdict = .pass
        var reasons: [String] = []
        
        if averageHR >= 90 && averageHR <= 115 {
            verdict = .pass
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 落在傳統肌力訓練的典型範圍內。")
        } else if averageHR > 115 && averageHR <= 130 {
            verdict = .warning
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 稍微偏高，這暗示了組間休息較短，或是這項訓練的代謝需求高於純肌力訓練。")
        } else if averageHR > 130 {
            verdict = .fail
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 偏高。這次訓練型態較像體能代謝循環訓練，而不是傳統肌力訓練。")
        } else {
            verdict = .pass
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 偏低，與組間恢復較充分的肌力訓練型態一致。")
        }

        if verdict == .fail {
            reasons.append("心率長時間維持在高區間，較偏代謝循環訓練型態，而非充分恢復的肌力節奏。")
        } else {
            switch observation.recoveryDropHint {
            case .visibleDrops:
                reasons.append("心率型態可見組間下降，與傳統肌力訓練的恢復節奏較一致。")
            case .possible:
                reasons.append("心率型態可能包含組間恢復，但僅靠心率仍屬描述性線索。")
            case .none:
                reasons.append("心率長時間維持在高區間，較偏代謝循環訓練型態，而非充分恢復的肌力節奏。")
            }
        }

        return AnalysisResult(
            verdict: verdict,
            confidence: 0.8,
            reasons: reasons,
            recommendations: RecommendationEngine.recommendations(
                for: workout.intent,
                verdict: verdict,
                distribution: distribution,
                driftRatio: nil
            ),
            zoneDistribution: distribution,
            stabilityStandardDeviation: HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples),
            driftRatio: nil,
            metricMetadata: [TrainingMetricMetadataFactory.strengthPattern(sampleQuality: observation.sampleQuality)] +
                TrainingMetricMetadataFactory.strengthMetrics(workout.strengthMetrics)
        )
    }
}

public enum WorkoutIntentAnalyzer {
    public static func analyze(
        _ workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> AnalysisResult {
        let result: AnalysisResult
        switch workout.intent {
        case .zone2:
            result = Zone2QualityAnalyzer.analyze(workout: workout, policy: policy)
        case .activityReview:
            result = basicActivityReview(workout: workout, policy: policy)
        case .vo2Interval:
            result = VO2IntervalAnalyzer.analyze(workout: workout, policy: policy)
        case .strength:
            result = StrengthAnalyzer.analyze(workout: workout, policy: policy)
        }
        return result.appendingMetricMetadata(
            TrainingMetricMetadataFactory.vo2MaxEstimate(workout.vo2MaxEstimate) +
                TrainingMetricMetadataFactory.heartRateRecovery(workout.heartRateRecoveryOneMinute) +
                TrainingMetricMetadataFactory.runningPower(workout.runningPower) +
                TrainingMetricMetadataFactory.cyclingPower(workout.cyclingPower) +
                TrainingMetricMetadataFactory.workoutRoute(workout.workoutRoute) +
                TrainingMetricMetadataFactory.externalLoadDecoupling(workout.externalLoadDecoupling)
        )
    }

    private static func basicActivityReview(
        workout: WorkoutInput,
        policy: AnalysisPolicy
    ) -> AnalysisResult {
        let samples = HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy)
        let distribution = ZoneDistributionAnalyzer.analyze(samples: samples, zoneBounds: policy.zoneBounds)
        return AnalysisResult(
            verdict: .pass,
            confidence: 0.5,
            reasons: ["本次紀錄是以一般活動的方式進行檢視，並非進行嚴格的 Zone 2 指標分析。"],
            recommendations: ["如果您需要的是純粹的摘要而非嚴格的訓練品質判定，就可以使用這個目標模式。"],
            zoneDistribution: distribution,
            stabilityStandardDeviation: HeartRateStabilityAnalyzer.standardDeviation(for: samples),
            driftRatio: HeartRateDriftAnalyzer.driftRatio(for: samples)
        )
    }
}

private enum TrainingMetricMetadataFactory {
    static func vo2MaxEstimate(_ estimate: VO2MaxEstimate?) -> [TrainingMetricMetadata] {
        guard let estimate else { return [] }
        let method = vo2MaxMethod(for: estimate)
        let confidence = vo2MaxConfidence(for: estimate)
        return [
            TrainingMetricMetadata(
                metric: .vo2Max,
                method: method,
                confidence: confidence,
                claim: TrainingMetricClaim(
                    ceiling: TrainingMetricClaimCeiling.defaultCeiling(for: method),
                    allowedTerms: ["VO2 max estimate", "trend estimate", "product reference"],
                    forbiddenTerms: ["true VO2 max", "lab-equivalent", "clinical fitness diagnosis"]
                ),
                dataQualityFlags: ["vo2max_value_imported"],
                recommendedValidation: "CPET/GXT gas analysis if VO2 max precision matters."
            )
        ]
    }

    static func heartRateRecovery(_ observation: HeartRateRecoveryObservation?) -> [TrainingMetricMetadata] {
        guard let observation else { return [] }
        let method = TrainingMetricMethod(
            tier: .productReference,
            source: observation.source,
            name: observation.sourceLabel ?? "Apple heart-rate recovery context",
            referenceStandardDistance: .twoOrMoreLevelsBelow
        )
        return [
            TrainingMetricMetadata(
                metric: .heartRateRecovery,
                method: method,
                confidence: TrainingMetricConfidence(
                    level: .mediumLow,
                    basis: heartRateRecoveryBasis(for: observation),
                    limitingFactors: ["Single recovery indicator", "No clinical recovery protocol"]
                ),
                claim: TrainingMetricClaim(
                    ceiling: .estimateOnly,
                    allowedTerms: ["recovery context", "post-workout recovery signal", "product reference"],
                    forbiddenTerms: ["recovery diagnosis", "VO2 max measurement", "clinical recovery diagnosis"]
                ),
                dataQualityFlags: ["heart_rate_recovery_imported"],
                recommendedValidation: "Use a standardized recovery protocol or broader lab/field testing if recovery precision matters."
            )
        ]
    }

    private static func heartRateRecoveryBasis(for observation: HeartRateRecoveryObservation) -> String {
        if observation.sourceLabel?.localizedCaseInsensitiveContains("Derived from Apple Health post-workout heart rate") == true {
            return "Derived post-workout heart-rate recovery context was computed from Apple Health heart-rate samples, not imported as a direct recovery sample."
        }
        return "Product heart-rate recovery context was imported, not a full recovery assessment."
    }

    static func runningPower(_ observation: RunningPowerObservation?) -> [TrainingMetricMetadata] {
        guard let observation else { return [] }
        let method = TrainingMetricMethod(
            tier: .fieldEstimator,
            source: observation.source,
            name: observation.sourceLabel ?? "Running power field-estimator support",
            referenceStandardDistance: .oneLevelBelow
        )
        return [
            TrainingMetricMetadata(
                metric: .runningPower,
                method: method,
                confidence: TrainingMetricConfidence(
                    level: .medium,
                    basis: "Running power context was imported as external-load support for field estimation.",
                    limitingFactors: ["No direct metabolic threshold measurement", "Running power method depends on device/model"]
                ),
                claim: TrainingMetricClaim(
                    ceiling: .estimateOnly,
                    allowedTerms: ["running power context", "external-load support", "field-estimator support"],
                    forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
                ),
                dataQualityFlags: ["running_power_imported"],
                recommendedValidation: "Use standardized threshold or lab testing if metabolic precision matters."
            )
        ]
    }

    static func cyclingPower(_ observation: CyclingPowerObservation?) -> [TrainingMetricMetadata] {
        guard let observation else { return [] }
        let method = TrainingMetricMethod(
            tier: .fieldEstimator,
            source: .cyclingPowerHR,
            name: observation.sourceLabel ?? "Cycling power field-estimator support",
            referenceStandardDistance: .oneLevelBelow
        )
        return [
            TrainingMetricMetadata(
                metric: .cyclingPower,
                method: method,
                confidence: TrainingMetricConfidence(
                    level: .medium,
                    basis: "Cycling power context was imported as external-load support for field estimation.",
                    limitingFactors: ["No direct metabolic threshold measurement", "Cycling power coverage depends on sensors and setup"]
                ),
                claim: TrainingMetricClaim(
                    ceiling: .estimateOnly,
                    allowedTerms: ["cycling power context", "external-load support", "field-estimator support"],
                    forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
                ),
                dataQualityFlags: ["cycling_power_imported"],
                recommendedValidation: "Use standardized threshold or lab testing if metabolic precision matters."
            )
        ]
    }

    static func workoutRoute(_ observation: WorkoutRouteObservation?) -> [TrainingMetricMetadata] {
        guard let observation else { return [] }
        let method = TrainingMetricMethod(
            tier: .fieldEstimator,
            source: observation.source,
            name: observation.sourceLabel ?? "Workout route terrain context",
            referenceStandardDistance: .twoOrMoreLevelsBelow
        )
        return [
            TrainingMetricMetadata(
                metric: .workoutRoute,
                method: method,
                confidence: TrainingMetricConfidence(
                    level: .mediumLow,
                    basis: "Workout route context was imported as terrain and outdoor-condition support.",
                    limitingFactors: ["Route context does not directly measure threshold or fitness", "Elevation quality depends on recorded route samples"]
                ),
                claim: TrainingMetricClaim(
                    ceiling: .estimateOnly,
                    allowedTerms: ["route context", "terrain context", "outdoor-condition support"],
                    forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
                ),
                dataQualityFlags: ["workout_route_imported"],
                recommendedValidation: "Use route context only as supporting evidence; pair with threshold or lab testing if metabolic precision matters."
            )
        ]
    }

    static func externalLoadDecoupling(_ observation: ExternalLoadDecouplingObservation?) -> [TrainingMetricMetadata] {
        guard let observation else { return [] }
        let method = TrainingMetricMethod(
            tier: .fieldEstimator,
            source: observation.source,
            name: observation.sourceLabel ?? externalLoadDecouplingMethodName(for: observation.source),
            referenceStandardDistance: .oneLevelBelow
        )
        return [
            TrainingMetricMetadata(
                metric: .externalLoadDecoupling,
                method: method,
                confidence: TrainingMetricConfidence(
                    level: .mediumLow,
                    basis: "External-load decoupling context was imported from first-half versus second-half heart-rate and power behavior.",
                    limitingFactors: ["No direct metabolic threshold measurement", "Half-split field summary does not replace controlled threshold testing"]
                ),
                claim: TrainingMetricClaim(
                    ceiling: .estimateOnly,
                    allowedTerms: ["external-load consistency context", "decoupling context", "field-estimator support"],
                    forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
                ),
                dataQualityFlags: ["external_load_decoupling_imported"],
                recommendedValidation: "Use standardized threshold or lab testing if metabolic precision matters."
            )
        ]
    }

    static func sampleQuality(
        rawSampleCount: Int,
        preparedSampleCount: Int,
        policy: AnalysisPolicy
    ) -> SampleQuality {
        if rawSampleCount < policy.minimumSampleCount { return .sparse }
        if preparedSampleCount < policy.minimumSampleCount { return .heavilyFiltered }
        return .sufficient
    }

    private static func vo2MaxMethod(for estimate: VO2MaxEstimate) -> TrainingMetricMethod {
        TrainingMetricMethod(
            tier: vo2MaxTier(for: estimate.source),
            source: estimate.source,
            name: estimate.sourceLabel ?? vo2MaxMethodName(for: estimate.source),
            referenceStandardDistance: vo2MaxReferenceDistance(for: estimate.source)
        )
    }

    private static func vo2MaxTier(for source: TrainingMetricMethodSource) -> TrainingMetricMethodTier {
        switch source {
        case .cpet:
            return .goldStandardAnchor
        case .runningHRSpeed, .cyclingPowerHR:
            return .fieldEstimator
        case .apple, .garmin, .firstbeat:
            return .productReference
        default:
            return .weakHeuristic
        }
    }

    private static func vo2MaxReferenceDistance(for source: TrainingMetricMethodSource) -> ReferenceStandardDistance {
        switch source {
        case .cpet:
            return .direct
        case .runningHRSpeed, .cyclingPowerHR:
            return .oneLevelBelow
        case .apple, .garmin, .firstbeat:
            return .twoOrMoreLevelsBelow
        default:
            return .unknown
        }
    }

    private static func vo2MaxConfidence(for estimate: VO2MaxEstimate) -> TrainingMetricConfidence {
        switch estimate.source {
        case .cpet:
            return TrainingMetricConfidence(
                level: .high,
                basis: "Direct lab VO2 max source was imported.",
                limitingFactors: []
            )
        case .runningHRSpeed, .cyclingPowerHR:
            return TrainingMetricConfidence(
                level: .medium,
                basis: "Structured field VO2 max estimate was imported, not lab CPET.",
                limitingFactors: ["No direct gas exchange data"]
            )
        case .apple, .garmin, .firstbeat:
            return TrainingMetricConfidence(
                level: .mediumLow,
                basis: "Product VO2 max estimate was imported, not lab CPET.",
                limitingFactors: ["Opaque product algorithm", "No direct gas exchange data"]
            )
        default:
            return TrainingMetricConfidence(
                level: .low,
                basis: "VO2 max value was imported with limited method provenance.",
                limitingFactors: ["Unknown VO2 max method"]
            )
        }
    }

    private static func vo2MaxMethodName(for source: TrainingMetricMethodSource) -> String {
        switch source {
        case .cpet:
            return "CPET/GXT gas analysis"
        case .runningHRSpeed:
            return "Running HR-speed VO2 max estimate"
        case .cyclingPowerHR:
            return "Cycling power-HR VO2 max estimate"
        case .apple:
            return "Apple VO2 max product estimate"
        case .garmin:
            return "Garmin VO2 max product estimate"
        case .firstbeat:
            return "Firstbeat VO2 max product estimate"
        default:
            return "Imported VO2 max value"
        }
    }

    private static func externalLoadDecouplingMethodName(for source: TrainingMetricMethodSource) -> String {
        switch source {
        case .runningHRSpeed:
            return "Running power + HR decoupling context"
        case .cyclingPowerHR:
            return "Cycling power + HR decoupling context"
        default:
            return "External-load decoupling context"
        }
    }

    static func zone2Range(sampleQuality: SampleQuality) -> TrainingMetricMetadata {
        TrainingMetricMetadata(
            metric: .zone2HeartRateRange,
            method: TrainingMetricMethod(
                tier: .weakHeuristic,
                source: .policyZoneBounds,
                name: "Policy Zone 2 heart-rate bounds",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .low,
                basis: "Current analysis uses configured heart-rate bounds, not LT1 or VT1 validation.",
                limitingFactors: limitingFactors(
                    for: sampleQuality,
                    baseline: ["No lactate or ventilatory threshold measurement"]
                )
            ),
            claim: TrainingMetricClaim(
                ceiling: .startingPointOnly,
                allowedTerms: ["estimated Zone 2 range", "usable starting point"],
                forbiddenTerms: ["exact Zone 2", "optimal Zone 2", "validated threshold"]
            ),
            dataQualityFlags: dataQualityFlags(for: sampleQuality),
            recommendedValidation: "Use lactate LT1 or CPET VT1/GET testing if threshold precision matters."
        )
    }

    static func vo2IntervalQuality(sampleQuality: SampleQuality) -> TrainingMetricMetadata {
        TrainingMetricMetadata(
            metric: .vo2IntervalQuality,
            method: TrainingMetricMethod(
                tier: .fieldEstimator,
                source: .heartRatePattern,
                name: "Heart-rate zone and interval-pattern classification",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: sampleQuality == .sufficient ? .mediumLow : .low,
                basis: "Classifies interval-like workout pattern from heart-rate zones; it does not estimate VO2 max.",
                limitingFactors: limitingFactors(
                    for: sampleQuality,
                    baseline: ["No gas exchange data", "No direct VO2 max value"]
                )
            ),
            claim: TrainingMetricClaim(
                ceiling: .estimateOnly,
                allowedTerms: ["interval pattern estimate", "consistent with VO2 interval structure"],
                forbiddenTerms: ["VO2 max measured", "true VO2 max", "lab-equivalent"]
            ),
            dataQualityFlags: dataQualityFlags(for: sampleQuality),
            recommendedValidation: "Use CPET/GXT gas analysis for VO2 max measurement."
        )
    }

    static func strengthPattern(sampleQuality: SampleQuality) -> TrainingMetricMetadata {
        TrainingMetricMetadata(
            metric: .strength,
            method: TrainingMetricMethod(
                tier: .weakHeuristic,
                source: .heartRatePattern,
                name: "Heart-rate pattern strength-session classification",
                referenceStandardDistance: .twoOrMoreLevelsBelow
            ),
            confidence: TrainingMetricConfidence(
                level: .low,
                basis: "Classifies strength-session pattern from heart-rate behavior; it does not measure force or 1RM.",
                limitingFactors: limitingFactors(
                    for: sampleQuality,
                    baseline: ["No load, reps, ROM, velocity, or direct 1RM measurement"]
                )
            ),
            claim: TrainingMetricClaim(
                ceiling: .startingPointOnly,
                allowedTerms: ["strength-session pattern", "heart-rate-based training pattern"],
                forbiddenTerms: ["measured strength", "1RM", "force output"]
            ),
            dataQualityFlags: dataQualityFlags(for: sampleQuality),
            recommendedValidation: "Use standardized 1RM, 3RM-5RM e1RM, or force/velocity testing for strength metrics."
        )
    }

    static func strengthMetrics(_ metrics: [StrengthMetric]) -> [TrainingMetricMetadata] {
        metrics.map { metric in
            let method = strengthMethod(for: metric)
            return TrainingMetricMetadata(
                metric: .strength,
                method: method,
                confidence: strengthConfidence(for: metric),
                claim: TrainingMetricClaim(
                    ceiling: TrainingMetricClaimCeiling.defaultCeiling(for: method),
                    allowedTerms: strengthAllowedTerms(for: metric),
                    forbiddenTerms: ["whole-body strength diagnosis", "clinical strength diagnosis", "全身肌力診斷"]
                ),
                dataQualityFlags: strengthDataQualityFlags(for: metric),
                recommendedValidation: "Use the same exercise, ROM, equipment, and rest protocol for comparable strength retests."
            )
        }
    }

    private static func strengthMethod(for metric: StrengthMetric) -> TrainingMetricMethod {
        TrainingMetricMethod(
            tier: strengthTier(for: metric.source),
            source: metric.source,
            name: metric.sourceLabel ?? strengthMethodName(for: metric),
            referenceStandardDistance: strengthReferenceDistance(for: metric.source)
        )
    }

    private static func strengthTier(for source: TrainingMetricMethodSource) -> TrainingMetricMethodTier {
        switch source {
        case .direct1RM:
            return .goldStandardAnchor
        case .e1RM, .gripStrength:
            return .fieldEstimator
        default:
            return .weakHeuristic
        }
    }

    private static func strengthReferenceDistance(for source: TrainingMetricMethodSource) -> ReferenceStandardDistance {
        switch source {
        case .direct1RM:
            return .direct
        case .e1RM, .gripStrength:
            return .oneLevelBelow
        default:
            return .unknown
        }
    }

    private static func strengthConfidence(for metric: StrengthMetric) -> TrainingMetricConfidence {
        switch metric.source {
        case .direct1RM:
            return TrainingMetricConfidence(
                level: .high,
                basis: "Direct 1RM strength metric was imported with exercise context.",
                limitingFactors: strengthLimitingFactors(for: metric)
            )
        case .e1RM:
            return TrainingMetricConfidence(
                level: .medium,
                basis: "Estimated 1RM strength metric was imported from load and repetition context.",
                limitingFactors: strengthLimitingFactors(for: metric)
            )
        case .gripStrength:
            return TrainingMetricConfidence(
                level: .medium,
                basis: "Grip strength metric was imported as a health-related proxy, not whole-body strength.",
                limitingFactors: ["Does not replace exercise-specific maximal strength testing"]
            )
        default:
            return TrainingMetricConfidence(
                level: .low,
                basis: "Strength metric was imported with limited method provenance.",
                limitingFactors: ["Unknown strength metric protocol"]
            )
        }
    }

    private static func strengthMethodName(for metric: StrengthMetric) -> String {
        switch metric.source {
        case .direct1RM:
            return "\(metric.exerciseName) direct 1RM"
        case .e1RM:
            return "\(metric.exerciseName) estimated 1RM"
        case .gripStrength:
            return "\(metric.exerciseName) grip strength"
        default:
            return "\(metric.exerciseName) strength metric"
        }
    }

    private static func strengthAllowedTerms(for metric: StrengthMetric) -> [String] {
        switch metric.source {
        case .direct1RM:
            return ["exercise-specific 1RM", "standardized strength metric"]
        case .e1RM:
            return ["estimated 1RM", "exercise-specific strength estimate"]
        case .gripStrength:
            return ["grip strength", "health-related proxy"]
        default:
            return ["strength metric", "exercise-specific observation"]
        }
    }

    private static func strengthDataQualityFlags(for metric: StrengthMetric) -> [String] {
        var flags = ["strength_metric_imported", "exercise_context_present"]
        if metric.repetitions != nil { flags.append("repetition_context_present") }
        if metric.loadValue != nil { flags.append("load_context_present") }
        return flags
    }

    private static func strengthLimitingFactors(for metric: StrengthMetric) -> [String] {
        var factors = ["ROM and technique standardization not independently verified"]
        if metric.source == .e1RM && metric.repetitions == nil {
            factors.append("Missing repetition count for e1RM provenance")
        }
        if metric.loadValue == nil {
            factors.append("Missing source load value")
        }
        return factors
    }

    private static func dataQualityFlags(for sampleQuality: SampleQuality) -> [String] {
        switch sampleQuality {
        case .sufficient:
            return ["heart_rate_samples_sufficient"]
        case .sparse:
            return ["heart_rate_samples_sparse"]
        case .heavilyFiltered:
            return ["heart_rate_samples_heavily_filtered"]
        }
    }

    private static func limitingFactors(
        for sampleQuality: SampleQuality,
        baseline: [String]
    ) -> [String] {
        baseline + (sampleQuality == .sufficient ? [] : dataQualityFlags(for: sampleQuality))
    }
}

private func overallVerdict(from severities: [Int]) -> AnalysisVerdict {
    if severities.contains(2) { return .fail }
    if severities.contains(1) { return .warning }
    return .pass
}

private func confidenceScore(
    from severities: [Int],
    sampleCount: Int,
    policy: AnalysisPolicy
) -> Double {
    let base = sampleCount >= policy.minimumSampleCount ? 0.8 : 0.45
    let penalty = Double(severities.reduce(0, +)) * 0.08
    return min(max(base - penalty, 0.1), 0.95)
}

public enum WeeklyObservationBuilder {
    public static func build(
        workouts: [WorkoutInput],
        weekStart: Date,
        calendar: Calendar = .current,
        asOf: Date = Date(),
        policy: AnalysisPolicy = .default
    ) -> WeeklyWorkoutSummary {
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let weekEnd = nextWeekStart.addingTimeInterval(-1)
        let effectiveEnd = min(nextWeekStart, asOf)

        let elapsedDays: Int = {
            if asOf < weekStart { return 0 }
            if asOf >= nextWeekStart { return 7 }
            let weekStartDay = calendar.startOfDay(for: weekStart)
            let asOfDay = calendar.startOfDay(for: asOf)
            let delta = calendar.dateComponents([.day], from: weekStartDay, to: asOfDay).day ?? 0
            return max(0, min(7, delta + 1))
        }()

        let weekWorkouts = workouts.filter {
            $0.startDate >= weekStart && $0.startDate < effectiveEnd
        }

        let totalDurationMinutes = weekWorkouts.reduce(0.0) { $0 + $1.durationSeconds } / 60.0

        var intentDistribution: [TrainingIntent: Int] = [:]
        var intentSourceDistribution: [IntentSource: Int] = [:]
        for workout in weekWorkouts {
            intentDistribution[workout.intent, default: 0] += 1
            intentSourceDistribution[workout.intentSource, default: 0] += 1
        }

        let distributions = weekWorkouts.map { workout in
            WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy).zoneDistribution
        }
        let zoneDistribution = ZoneDistributionAnalyzer.merge(distributions)

        let trainingDays = Set(weekWorkouts.map { calendar.startOfDay(for: $0.startDate) })

        let highIntensityDays = Set(
            weekWorkouts
                .filter { $0.intent == .vo2Interval }
                .map { calendar.startOfDay(for: $0.startDate) }
        ).count

        let strengthDays = Set(
            weekWorkouts
                .filter { $0.intent == .strength || $0.workoutType == .strengthTraining }
                .map { calendar.startOfDay(for: $0.startDate) }
        ).count

        let restDays = max(0, elapsedDays - trainingDays.count)

        let sortedDays = trainingDays.sorted()
        var consecutiveTrainingDays = sortedDays.isEmpty ? 0 : 1
        if sortedDays.count > 1 {
            var currentStreak = 1
            for i in 1..<sortedDays.count {
                let diff = calendar.dateComponents([.day], from: sortedDays[i - 1], to: sortedDays[i]).day ?? 0
                if diff == 1 {
                    currentStreak += 1
                    consecutiveTrainingDays = max(consecutiveTrainingDays, currentStreak)
                } else {
                    currentStreak = 1
                }
            }
        }

        let totalActiveCalories: Double? = {
            let values = weekWorkouts.compactMap(\.activeCaloriesKcal)
            return values.isEmpty ? nil : values.reduce(0, +)
        }()

        let hrvSamples = weekWorkouts.compactMap(\.hrvSDNNMilliseconds)
        let hrvSampledWorkoutCount = hrvSamples.count
        let hrvCoverageRatio = weekWorkouts.isEmpty
            ? 0
            : Double(hrvSampledWorkoutCount) / Double(weekWorkouts.count)
        let averageHRVSDNNMilliseconds: Double? = hrvSamples.isEmpty
            ? nil
            : hrvSamples.reduce(0, +) / Double(hrvSamples.count)

        return WeeklyWorkoutSummary(
            weekStart: weekStart,
            weekEnd: weekEnd,
            workoutCount: weekWorkouts.count,
            totalDurationMinutes: totalDurationMinutes,
            totalActiveCalories: totalActiveCalories,
            intentDistribution: intentDistribution,
            intentSourceDistribution: intentSourceDistribution,
            zoneDistribution: zoneDistribution,
            highIntensityDays: highIntensityDays,
            strengthDays: strengthDays,
            restDays: restDays,
            elapsedDays: elapsedDays,
            consecutiveTrainingDays: consecutiveTrainingDays,
            hrvSampledWorkoutCount: hrvSampledWorkoutCount,
            hrvCoverageRatio: hrvCoverageRatio,
            averageHRVSDNNMilliseconds: averageHRVSDNNMilliseconds
        )
    }
}

public enum WeeklyLoadPolicyEngine {
    public static func evaluate(summary: WeeklyWorkoutSummary) -> WeeklyLoadPolicy {
        let totalZoneSamples = summary.zoneDistribution.counts.values.reduce(0, +)
        let confidence = computeConfidence(workoutCount: summary.workoutCount, totalZoneSamples: totalZoneSamples)
        let (concern, findings) = buildConcernAndFindings(summary: summary)
        let tendency = assessLoadTendency(summary: summary)
        let nextAction = buildNextAction(concern: concern, tendency: tendency, workoutCount: summary.workoutCount)
        return WeeklyLoadPolicy(
            recoveryConcernLevel: concern,
            loadTendency: tendency,
            keyFindings: findings,
            nextAction: nextAction,
            confidence: confidence
        )
    }

    private static func computeConfidence(workoutCount: Int, totalZoneSamples: Int) -> Double {
        guard workoutCount > 0 else { return 0.75 }
        if totalZoneSamples == 0 { return 0.4 }
        if totalZoneSamples < workoutCount * 20 { return 0.6 }
        return 0.85
    }

    private static func buildConcernAndFindings(summary: WeeklyWorkoutSummary) -> (RecoveryConcernLevel, [String]) {
        var findings: [String] = []

        if summary.workoutCount == 0 {
            findings.append("本週第 \(summary.elapsedDays) 天，尚無訓練紀錄")
        } else {
            findings.append("本週第 \(summary.elapsedDays) 天，累計 \(summary.workoutCount) 次訓練，\(summary.restDays) 天休息")
        }

        if summary.highIntensityDays >= 2 {
            findings.append("高強度訓練（VO2／間歇）共 \(summary.highIntensityDays) 天")
        }

        if summary.strengthDays > 0 {
            findings.append("肌力訓練共 \(summary.strengthDays) 天")
        }

        if summary.consecutiveTrainingDays >= 4 {
            findings.append("最長連續訓練 \(summary.consecutiveTrainingDays) 天")
        }

        let concern: RecoveryConcernLevel
        if summary.highIntensityDays >= 3 && summary.restDays <= 1 {
            concern = .high
        } else if summary.consecutiveTrainingDays >= 5 || summary.restDays == 0 || summary.highIntensityDays >= 3 {
            concern = .elevated
        } else if summary.consecutiveTrainingDays >= 4 || summary.restDays <= 1 || summary.highIntensityDays >= 2 {
            concern = .moderate
        } else {
            concern = .low
        }

        return (concern, findings)
    }

    private static func assessLoadTendency(summary: WeeklyWorkoutSummary) -> LoadTendency {
        guard summary.workoutCount > 1 else { return .underloaded }
        let vo2Count = summary.intentDistribution[.vo2Interval, default: 0]
        let z2Count = summary.intentDistribution[.zone2, default: 0]
        let total = summary.workoutCount

        if Double(vo2Count) / Double(total) >= 0.4 || vo2Count >= 3 {
            return .highIntensityFocused
        }
        if Double(z2Count) / Double(total) >= 0.6 {
            return .aerobicFocused
        }
        if summary.restDays >= 2 && total >= 3 {
            return .balanced
        }
        return .mixed
    }

    private static func buildNextAction(
        concern: RecoveryConcernLevel,
        tendency: LoadTendency,
        workoutCount: Int
    ) -> String {
        switch concern {
        case .high:
            return "下週建議安排至少兩天輕量訓練或完整休息，並降低高強度課程的頻率。"
        case .elevated:
            return "下週可安排一天完整休息，有助於維持訓練與恢復的平衡。"
        case .moderate:
            if tendency == .highIntensityFocused {
                return "下週可加入一至兩次有氧基礎訓練，平衡高強度課程的比例。"
            }
            return "本週訓練節奏尚可，下週視體感微調強度。"
        case .low:
            if workoutCount == 0 {
                return "可嘗試從輕量活動開始，建立每週訓練習慣。"
            }
            return "目前訓練節奏良好，可依計劃繼續。"
        }
    }
}
