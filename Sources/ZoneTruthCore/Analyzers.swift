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
            reasons.append("Session duration is shorter than the minimum needed for reliable Zone 2 judgment.")
            severityScores.append(2)
        }

        if preparedSamples.count < policy.minimumSampleCount {
            // Return early — running stability and drift on too few samples produces misleading reasons.
            let thinDistribution = ZoneDistributionAnalyzer.analyze(samples: preparedSamples, zoneBounds: policy.zoneBounds)
            return AnalysisResult(
                verdict: .fail,
                confidence: 0.4,
                reasons: reasons + ["Heart rate sample count is too low after filtering. The device may not have recorded heart rate throughout the session."],
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
            reasons.append("Zone 3 time stayed below 10%.")
            severityScores.append(0)
        case .warning:
            reasons.append("Zone 3 time was between 10% and 20%, higher than ideal for Zone 2.")
            severityScores.append(1)
        case .fail:
            reasons.append("Zone 3 time exceeded 20%, which is too high for a Zone 2 session.")
            severityScores.append(2)
        }

        let stabilityValue = HeartRateStabilityAnalyzer.standardDeviation(for: preparedSamples)
        let stabilityVerdict = HeartRateStabilityAnalyzer.verdict(for: preparedSamples, policy: policy)
        switch stabilityVerdict {
        case .pass:
            reasons.append("Heart rate stayed stable throughout the analyzed portion of the session.")
            severityScores.append(0)
        case .warning:
            reasons.append("Heart rate variability was moderate, so pacing may have been uneven.")
            severityScores.append(1)
        case .fail:
            reasons.append("Heart rate variability was high, which weakens the Zone 2 interpretation.")
            severityScores.append(2)
        }

        let driftValue = HeartRateDriftAnalyzer.driftRatio(for: preparedSamples)
        let driftVerdict = HeartRateDriftAnalyzer.verdict(for: preparedSamples)
        switch driftVerdict {
        case .pass:
            reasons.append("Heart rate drift stayed below 5% between the first and second half.")
            severityScores.append(0)
        case .warning:
            reasons.append("Heart rate drift was between 5% and 8%, suggesting mild decoupling.")
            severityScores.append(1)
        case .fail:
            reasons.append("Heart rate drift exceeded 8%, suggesting the session drifted out of steady aerobic work.")
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
        case .vo2Interval, .strength:
            return AnalysisResult(
                verdict: .warning,
                confidence: 0.35,
                reasons: ["This intent is outside the first MVP judgment scope and is currently treated as a basic activity review."],
                recommendations: ["Use Zone 2 or Activity / Skill as the first supported workflow in MVP."],
                zoneDistribution: ZoneDistributionAnalyzer.analyze(
                    samples: HeartRateSampleSanitizer.sanitize(workout.heartRateSamples, policy: policy),
                    zoneBounds: policy.zoneBounds
                )
            )
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
            reasons: ["This session is reviewed as general activity rather than strict Zone 2 compliance."],
            recommendations: ["Use this mode when you want a descriptive review instead of a strict training-quality judgment."],
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
