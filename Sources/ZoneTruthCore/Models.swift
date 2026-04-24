import Foundation

public enum TrainingIntent: String, Codable, CaseIterable, Sendable {
    case zone2 = "Zone 2"
    case activityReview = "Activity / Skill"
    case vo2Interval = "VO2 / Interval"
    case strength = "Strength"
}

public enum WorkoutType: String, Codable, Sendable {
    case running
    case cycling
    case swimming
    case walking
    case strengthTraining
    case mixed
    case other
}

public enum AnalysisVerdict: String, Codable, Sendable {
    case pass
    case warning
    case fail
}

public enum TrainingZone: Int, CaseIterable, Codable, Sendable {
    case zone1 = 1
    case zone2
    case zone3
    case zone4
    case zone5
}

public struct HeartRateSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let bpm: Double

    public init(timestamp: Date, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

public struct ZoneBounds: Codable, Equatable, Sendable {
    public let zone2LowerBound: Double
    public let zone2UpperBound: Double
    public let zone4Threshold: Double
    public let zone5Threshold: Double

    public init(
        zone2LowerBound: Double,
        zone2UpperBound: Double,
        zone4Threshold: Double,
        zone5Threshold: Double
    ) {
        self.zone2LowerBound = zone2LowerBound
        self.zone2UpperBound = zone2UpperBound
        self.zone4Threshold = zone4Threshold
        self.zone5Threshold = zone5Threshold
    }

    public func zone(for bpm: Double) -> TrainingZone {
        if bpm < zone2LowerBound { return .zone1 }
        if bpm <= zone2UpperBound { return .zone2 }
        if bpm < zone4Threshold { return .zone3 }
        if bpm < zone5Threshold { return .zone4 }
        return .zone5
    }
}

public struct AnalysisPolicy: Codable, Equatable, Sendable {
    public let warmupExclusionSeconds: TimeInterval
    public let cooldownExclusionSeconds: TimeInterval
    public let minimumDurationSeconds: TimeInterval
    public let minimumSampleCount: Int
    public let abnormalSpikeDeltaBPM: Double
    public let lowStabilityStdDev: Double
    public let mediumStabilityStdDev: Double
    public let zoneBounds: ZoneBounds

    public init(
        warmupExclusionSeconds: TimeInterval,
        cooldownExclusionSeconds: TimeInterval,
        minimumDurationSeconds: TimeInterval,
        minimumSampleCount: Int,
        abnormalSpikeDeltaBPM: Double,
        lowStabilityStdDev: Double,
        mediumStabilityStdDev: Double,
        zoneBounds: ZoneBounds
    ) {
        self.warmupExclusionSeconds = warmupExclusionSeconds
        self.cooldownExclusionSeconds = cooldownExclusionSeconds
        self.minimumDurationSeconds = minimumDurationSeconds
        self.minimumSampleCount = minimumSampleCount
        self.abnormalSpikeDeltaBPM = abnormalSpikeDeltaBPM
        self.lowStabilityStdDev = lowStabilityStdDev
        self.mediumStabilityStdDev = mediumStabilityStdDev
        self.zoneBounds = zoneBounds
    }

    public static let `default` = AnalysisPolicy(
        warmupExclusionSeconds: 5 * 60,
        cooldownExclusionSeconds: 3 * 60,
        minimumDurationSeconds: 20 * 60,
        minimumSampleCount: 20,
        abnormalSpikeDeltaBPM: 25,
        lowStabilityStdDev: 5,
        mediumStabilityStdDev: 10,
        zoneBounds: ZoneBounds(
            zone2LowerBound: 110,
            zone2UpperBound: 125,
            zone4Threshold: 141,
            zone5Threshold: 156
        )
    )
}

public struct WorkoutInput: Codable, Equatable, Sendable {
    public let id: UUID
    public let workoutType: WorkoutType
    public let startDate: Date
    public let endDate: Date
    public let durationSeconds: TimeInterval
    public let heartRateSamples: [HeartRateSample]
    public let intent: TrainingIntent

    public init(
        id: UUID = UUID(),
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval? = nil,
        heartRateSamples: [HeartRateSample],
        intent: TrainingIntent
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds ?? endDate.timeIntervalSince(startDate)
        self.heartRateSamples = heartRateSamples.sorted { $0.timestamp < $1.timestamp }
        self.intent = intent
    }
}

public struct ZoneDistribution: Equatable, Sendable {
    public let counts: [TrainingZone: Int]
    public let ratios: [TrainingZone: Double]

    public init(counts: [TrainingZone: Int], ratios: [TrainingZone: Double]) {
        self.counts = counts
        self.ratios = ratios
    }

    public func ratio(for zone: TrainingZone) -> Double {
        ratios[zone, default: 0]
    }
}

public struct AnalysisResult: Equatable, Sendable {
    public let verdict: AnalysisVerdict
    public let confidence: Double
    public let reasons: [String]
    public let recommendations: [String]
    public let zoneDistribution: ZoneDistribution
    public let stabilityStandardDeviation: Double?
    public let driftRatio: Double?

    public init(
        verdict: AnalysisVerdict,
        confidence: Double,
        reasons: [String],
        recommendations: [String],
        zoneDistribution: ZoneDistribution,
        stabilityStandardDeviation: Double? = nil,
        driftRatio: Double? = nil
    ) {
        self.verdict = verdict
        self.confidence = confidence
        self.reasons = reasons
        self.recommendations = recommendations
        self.zoneDistribution = zoneDistribution
        self.stabilityStandardDeviation = stabilityStandardDeviation
        self.driftRatio = driftRatio
    }
}

public typealias WorkoutIntent = TrainingIntent
public typealias WorkoutKind = WorkoutType
public typealias AnalysisStatus = AnalysisVerdict
public typealias WorkoutSummary = WorkoutInput
