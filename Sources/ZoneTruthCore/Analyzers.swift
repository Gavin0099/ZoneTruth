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
}

public enum Zone3LeakageAnalyzer {
    public static func verdict(for distribution: ZoneDistribution) -> AnalysisVerdict {
        let zone3Ratio = distribution.ratio(for: .zone3)
        if zone3Ratio > 0.20 { return .fail }
        if zone3Ratio >= 0.10 { return .warning }
        return .pass
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
                driftRatio: nil
            )
        }

        let leakageVerdict = Zone3LeakageAnalyzer.verdict(for: distribution)
        switch leakageVerdict {
        case .pass:
            reasons.append("Zone 3 區間的時間比例維持在 10% 以下，控制得非常好。")
            severityScores.append(0)
        case .warning:
            reasons.append("Zone 3 區間的時間比例介於 10% 到 20% 之間，對 Zone 2 訓練來說稍微偏高。")
            severityScores.append(1)
        case .fail:
            reasons.append("Zone 3 區間的時間比例超過 20%，對於 Zone 2 訓練來說強度太高了。")
            severityScores.append(2)
        }

        let stabilityValue = HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples)
        let stabilityVerdict = HeartRateStabilityAnalyzer.verdict(for: preparedSamples, policy: policy)
        switch stabilityVerdict {
        case .pass:
            reasons.append("在整個分析區間內，您的心率保持得非常穩定。")
            severityScores.append(0)
        case .warning:
            reasons.append("心率變異度為中等，這表示您的配速或阻力可能不太均勻。")
            severityScores.append(1)
        case .fail:
            reasons.append("心率波動過大，這削弱了維持在 Zone 2 狀態的效果。")
            severityScores.append(2)
        }

        let driftValue = HeartRateDriftAnalyzer.driftRatio(for: preparedSamples)
        let driftVerdict = HeartRateDriftAnalyzer.verdict(for: preparedSamples)
        switch driftVerdict {
        case .pass:
            reasons.append("前半段與後半段的心率飄移維持在 5% 以下，耐力表現優秀。")
            severityScores.append(0)
        case .warning:
            reasons.append("心率飄移介於 5% 到 8% 之間，顯示有輕微的心率脫鉤現象 (Cardiac Drift)。")
            severityScores.append(1)
        case .fail:
            reasons.append("心率飄移超過 8%，顯示後段訓練已經偏離了穩定的有氧狀態。")
            severityScores.append(2)
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
            driftRatio: driftValue
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
        
        var verdict: AnalysisVerdict = .pass
        var reasons: [String] = []
        
        if highIntensityRatio > 0.10 {
            verdict = .pass
            reasons.append("在高強度區間 (Zone 4/5) 停留的時間充足，這是一次達標的間歇訓練。")
        } else if highIntensityRatio >= 0.05 {
            verdict = .warning
            reasons.append("在高強度區間的時間適中；建議下次間歇訓練時可以試著拉高一點強度。")
        } else {
            verdict = .fail
            reasons.append("在高強度區間的時間過少，而這通常是間歇訓練所必備的。")
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
            driftRatio: nil
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
            highHrSustainedRatio: highHrSustainedRatio
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
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 非常高。這次訓練的實質效果比較像是體能代謝循環訓練，而不是傳統肌力訓練。")
        } else {
            verdict = .pass
            reasons.append("平均心率 (\(Int(averageHR)) bpm) 偏低，這對於組間完全恢復的純肌力訓練來說是非常理想的。")
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
            driftRatio: nil
        )
    }
}

public enum WorkoutIntentAnalyzer {
    public static func analyze(
        _ workout: WorkoutInput,
        policy: AnalysisPolicy = .default
    ) -> AnalysisResult {
        switch workout.intent {
        case .zone2:
            return Zone2QualityAnalyzer.analyze(workout: workout, policy: policy)
        case .activityReview:
            return basicActivityReview(workout: workout, policy: policy)
        case .vo2Interval:
            return VO2IntervalAnalyzer.analyze(workout: workout, policy: policy)
        case .strength:
            return StrengthAnalyzer.analyze(workout: workout, policy: policy)
        }
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
