import Foundation

public enum TrainingIntent: String, Codable, CaseIterable, Sendable {
    case zone2 = "Zone 2"
    case activityReview = "Activity / Skill"
    case vo2Interval = "VO2 / Interval"
    case strength = "Strength"
}

public enum IntentSource: String, Codable, CaseIterable, Sendable {
    case auto
    case userOverride
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

public struct HeartRateSample: Codable, Equatable, Hashable, Sendable {
    public let timestamp: Date
    public let bpm: Double

    public init(timestamp: Date, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

public struct ZoneBounds: Codable, Equatable, Hashable, Sendable {
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

public struct AnalysisPolicy: Codable, Equatable, Hashable, Sendable {
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

public struct WorkoutInput: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let workoutType: WorkoutType
    public let startDate: Date
    public let endDate: Date
    public let durationSeconds: TimeInterval
    public let heartRateSamples: [HeartRateSample]
    public let hrvSDNNMilliseconds: Double?
    public let intent: TrainingIntent
    public let intentSource: IntentSource
    public let dataSource: String?
    public let activeCaloriesKcal: Double?
    public let totalDistanceMeters: Double?

    public init(
        id: UUID = UUID(),
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval? = nil,
        heartRateSamples: [HeartRateSample],
        hrvSDNNMilliseconds: Double? = nil,
        intent: TrainingIntent? = nil,
        intentSource: IntentSource? = nil,
        dataSource: String? = nil,
        activeCaloriesKcal: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        let resolvedIntent = intent ?? Self.defaultIntent(for: workoutType)
        let resolvedIntentSource = intentSource ?? (intent == nil ? .auto : .userOverride)
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds ?? endDate.timeIntervalSince(startDate)
        self.heartRateSamples = heartRateSamples.sorted { $0.timestamp < $1.timestamp }
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.intent = resolvedIntent
        self.intentSource = resolvedIntentSource
        self.dataSource = dataSource
        self.activeCaloriesKcal = activeCaloriesKcal
        self.totalDistanceMeters = totalDistanceMeters
    }

    public static func defaultIntent(for workoutType: WorkoutType) -> TrainingIntent {
        switch workoutType {
        case .strengthTraining:
            return .strength
        case .running, .cycling, .swimming, .walking:
            return .zone2
        case .mixed, .other:
            return .activityReview
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workoutType
        case startDate
        case endDate
        case durationSeconds
        case heartRateSamples
        case hrvSDNNMilliseconds
        case intent
        case intentSource
        case dataSource
        case activeCaloriesKcal
        case totalDistanceMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let workoutType = try container.decode(WorkoutType.self, forKey: .workoutType)
        let startDate = try container.decode(Date.self, forKey: .startDate)
        let endDate = try container.decode(Date.self, forKey: .endDate)
        let durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
        let heartRateSamples = try container.decodeIfPresent([HeartRateSample].self, forKey: .heartRateSamples) ?? []
        let hrvSDNNMilliseconds = try container.decodeIfPresent(Double.self, forKey: .hrvSDNNMilliseconds)
        let intent = try container.decodeIfPresent(TrainingIntent.self, forKey: .intent)
        let intentSource = try container.decodeIfPresent(IntentSource.self, forKey: .intentSource)
        let dataSource = try container.decodeIfPresent(String.self, forKey: .dataSource)
        let activeCaloriesKcal = try container.decodeIfPresent(Double.self, forKey: .activeCaloriesKcal)
        let totalDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .totalDistanceMeters)

        self.init(
            id: id,
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            heartRateSamples: heartRateSamples,
            hrvSDNNMilliseconds: hrvSDNNMilliseconds,
            intent: intent,
            intentSource: intentSource,
            dataSource: dataSource,
            activeCaloriesKcal: activeCaloriesKcal,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workoutType, forKey: .workoutType)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(heartRateSamples, forKey: .heartRateSamples)
        try container.encodeIfPresent(hrvSDNNMilliseconds, forKey: .hrvSDNNMilliseconds)
        try container.encode(intent, forKey: .intent)
        try container.encode(intentSource, forKey: .intentSource)
        try container.encodeIfPresent(dataSource, forKey: .dataSource)
        try container.encodeIfPresent(activeCaloriesKcal, forKey: .activeCaloriesKcal)
        try container.encodeIfPresent(totalDistanceMeters, forKey: .totalDistanceMeters)
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

public enum SampleQuality: String, Codable, Equatable, Sendable {
    case sufficient
    case sparse
    case heavilyFiltered
}

public struct Zone2Observation: Equatable, Sendable {
    public let zoneDistribution: ZoneDistribution
    public let driftRatio: Double?
    public let stabilityStandardDeviation: Double?
    public let sampleQuality: SampleQuality

    public init(
        zoneDistribution: ZoneDistribution,
        driftRatio: Double?,
        stabilityStandardDeviation: Double?,
        sampleQuality: SampleQuality
    ) {
        self.zoneDistribution = zoneDistribution
        self.driftRatio = driftRatio
        self.stabilityStandardDeviation = stabilityStandardDeviation
        self.sampleQuality = sampleQuality
    }
}

public enum IntervalPatternHint: String, Codable, Equatable, Sendable {
    case none
    case possible
    case repeatedPeaks
}

public struct VO2Observation: Equatable, Sendable {
    public let zoneDistribution: ZoneDistribution
    public let highIntensityRatio: Double
    public let peakZoneRatio: Double
    public let intervalPatternHint: IntervalPatternHint
    public let sampleQuality: SampleQuality

    public init(
        zoneDistribution: ZoneDistribution,
        highIntensityRatio: Double,
        peakZoneRatio: Double,
        intervalPatternHint: IntervalPatternHint,
        sampleQuality: SampleQuality
    ) {
        self.zoneDistribution = zoneDistribution
        self.highIntensityRatio = highIntensityRatio
        self.peakZoneRatio = peakZoneRatio
        self.intervalPatternHint = intervalPatternHint
        self.sampleQuality = sampleQuality
    }
}

public struct WorkoutObservationPrimitives: Equatable, Sendable {
    public let zoneDistribution: ZoneDistribution
    public let sampleQuality: SampleQuality
    public let driftRatio: Double?
    public let stabilityStandardDeviation: Double?
    public let highIntensityRatio: Double
    public let peakZoneRatio: Double
    public let averageHeartRate: Double?
    public let maxHeartRateBPM: Double?
    public let highHrSustainedRatio: Double
    public let activeCaloriesKcal: Double?
    public let totalDistanceMeters: Double?

    public init(
        zoneDistribution: ZoneDistribution,
        sampleQuality: SampleQuality,
        driftRatio: Double?,
        stabilityStandardDeviation: Double?,
        highIntensityRatio: Double,
        peakZoneRatio: Double,
        averageHeartRate: Double?,
        maxHeartRateBPM: Double? = nil,
        highHrSustainedRatio: Double,
        activeCaloriesKcal: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        self.zoneDistribution = zoneDistribution
        self.sampleQuality = sampleQuality
        self.driftRatio = driftRatio
        self.stabilityStandardDeviation = stabilityStandardDeviation
        self.highIntensityRatio = highIntensityRatio
        self.peakZoneRatio = peakZoneRatio
        self.averageHeartRate = averageHeartRate
        self.maxHeartRateBPM = maxHeartRateBPM
        self.highHrSustainedRatio = highHrSustainedRatio
        self.activeCaloriesKcal = activeCaloriesKcal
        self.totalDistanceMeters = totalDistanceMeters
    }
}

public enum RecoveryDropHint: String, Codable, Equatable, Sendable {
    case none
    case possible
    case visibleDrops
}

public struct StrengthObservation: Equatable, Sendable {
    public let avgHeartRate: Double?
    public let highHrSustainedRatio: Double
    public let recoveryDropHint: RecoveryDropHint
    public let sampleQuality: SampleQuality

    public init(
        avgHeartRate: Double?,
        highHrSustainedRatio: Double,
        recoveryDropHint: RecoveryDropHint,
        sampleQuality: SampleQuality
    ) {
        self.avgHeartRate = avgHeartRate
        self.highHrSustainedRatio = highHrSustainedRatio
        self.recoveryDropHint = recoveryDropHint
        self.sampleQuality = sampleQuality
    }
}

public enum ActivityMovementType: String, Codable, Equatable, Sendable {
    case steady
    case intermittent
    case mixed
}

public struct ActivityObservation: Equatable, Sendable {
    public let zoneDistribution: ZoneDistribution
    public let movementType: ActivityMovementType
    public let duration: TimeInterval
    public let sampleQuality: SampleQuality

    public init(
        zoneDistribution: ZoneDistribution,
        movementType: ActivityMovementType,
        duration: TimeInterval,
        sampleQuality: SampleQuality
    ) {
        self.zoneDistribution = zoneDistribution
        self.movementType = movementType
        self.duration = duration
        self.sampleQuality = sampleQuality
    }
}

public struct LabeledWorkoutCase: Equatable, Sendable {
    public let name: String
    public let summary: String
    public let workout: WorkoutInput
    public let expectedVerdict: AnalysisVerdict
    public let expectedReasonSnippets: [String]

    public init(
        name: String,
        summary: String,
        workout: WorkoutInput,
        expectedVerdict: AnalysisVerdict,
        expectedReasonSnippets: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.workout = workout
        self.expectedVerdict = expectedVerdict
        self.expectedReasonSnippets = expectedReasonSnippets
    }
}

public typealias WorkoutIntent = TrainingIntent
public typealias WorkoutKind = WorkoutType
public typealias AnalysisStatus = AnalysisVerdict
public typealias WorkoutSummary = WorkoutInput

public struct CalibrationSuggestion: Equatable, Sendable {
    public let currentBounds: ZoneBounds
    public let suggestedBounds: ZoneBounds
    public let reason: String
    public let confidence: Double
    public let sourceSessionIDs: [UUID]

    public init(
        currentBounds: ZoneBounds,
        suggestedBounds: ZoneBounds,
        reason: String,
        confidence: Double,
        sourceSessionIDs: [UUID]
    ) {
        self.currentBounds = currentBounds
        self.suggestedBounds = suggestedBounds
        self.reason = reason
        self.confidence = confidence
        self.sourceSessionIDs = sourceSessionIDs
    }
}

public struct WeeklyWorkoutSummary: Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let workoutCount: Int
    public let totalDurationMinutes: Double
    public let totalActiveCalories: Double?
    public let intentDistribution: [TrainingIntent: Int]
    public let intentSourceDistribution: [IntentSource: Int]
    public let zoneDistribution: ZoneDistribution
    public let highIntensityDays: Int
    public let strengthDays: Int
    public let restDays: Int
    public let elapsedDays: Int
    public let consecutiveTrainingDays: Int
    public let hrvSampledWorkoutCount: Int
    public let hrvCoverageRatio: Double
    public let averageHRVSDNNMilliseconds: Double?

    public init(
        weekStart: Date,
        weekEnd: Date,
        workoutCount: Int,
        totalDurationMinutes: Double,
        totalActiveCalories: Double?,
        intentDistribution: [TrainingIntent: Int],
        intentSourceDistribution: [IntentSource: Int] = [:],
        zoneDistribution: ZoneDistribution,
        highIntensityDays: Int,
        strengthDays: Int,
        restDays: Int,
        elapsedDays: Int,
        consecutiveTrainingDays: Int,
        hrvSampledWorkoutCount: Int = 0,
        hrvCoverageRatio: Double = 0,
        averageHRVSDNNMilliseconds: Double? = nil
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.workoutCount = workoutCount
        self.totalDurationMinutes = totalDurationMinutes
        self.totalActiveCalories = totalActiveCalories
        self.intentDistribution = intentDistribution
        self.intentSourceDistribution = intentSourceDistribution
        self.zoneDistribution = zoneDistribution
        self.highIntensityDays = highIntensityDays
        self.strengthDays = strengthDays
        self.restDays = restDays
        self.elapsedDays = elapsedDays
        self.consecutiveTrainingDays = consecutiveTrainingDays
        self.hrvSampledWorkoutCount = hrvSampledWorkoutCount
        self.hrvCoverageRatio = hrvCoverageRatio
        self.averageHRVSDNNMilliseconds = averageHRVSDNNMilliseconds
    }
}

public enum RecoveryConcernLevel: String, Codable, Equatable, Sendable {
    case low
    case moderate
    case elevated
    case high
}

public enum LoadTendency: String, Codable, Equatable, Sendable {
    case balanced
    case highIntensityFocused
    case aerobicFocused
    case mixed
    case underloaded
}

public struct WeeklyLoadPolicy: Equatable, Sendable {
    public let recoveryConcernLevel: RecoveryConcernLevel
    public let loadTendency: LoadTendency
    public let keyFindings: [String]
    public let nextAction: String
    public let confidence: Double

    public init(
        recoveryConcernLevel: RecoveryConcernLevel,
        loadTendency: LoadTendency,
        keyFindings: [String],
        nextAction: String,
        confidence: Double
    ) {
        self.recoveryConcernLevel = recoveryConcernLevel
        self.loadTendency = loadTendency
        self.keyFindings = keyFindings
        self.nextAction = nextAction
        self.confidence = confidence
    }
}

public enum InferenceType: String, Codable, Equatable, Sendable {
    case directObservation = "direct_observation"
    case boundedSynthesis = "bounded_synthesis"
    case sparseInference = "sparse_inference"
}

public enum InferenceAuthorityCeiling: String, Codable, Equatable, Sendable {
    case nonInterventional = "non_interventional"
}

public enum MissingEvidence: String, Codable, Equatable, Sendable, CaseIterable {
    case sleep
    case hrv
    case nutrition
    case illness
    case stress
    case deviceQuality = "device_quality"
    case other
}

public enum DerivedFromSignal: String, Codable, Equatable, Sendable, CaseIterable {
    case workoutCount = "workout_count"
    case dataFreshness = "data_freshness"
    case hrvCoverage = "hrv_coverage"
    case restDays = "rest_days"
    case intentDistribution = "intent_distribution"
    case highIntensityDays = "high_intensity_days"
    case consecutiveTrainingDays = "consecutive_training_days"
    case recoveryConcernLevel = "recovery_concern_level"
    case zoneDistribution = "zone_distribution"
}

public enum InferenceStrength: String, Codable, Equatable, Sendable {
    case direct
    case bounded
    case sparse
}

public struct InferenceProvenance: Equatable, Sendable, Codable {
    public let inferenceType: InferenceType
    public let derivedFrom: [DerivedFromSignal]
    public let missingEvidence: [MissingEvidence]
    public let authorityCeiling: InferenceAuthorityCeiling

    public init(
        inferenceType: InferenceType,
        derivedFrom: [DerivedFromSignal],
        missingEvidence: [MissingEvidence],
        authorityCeiling: InferenceAuthorityCeiling
    ) {
        self.inferenceType = inferenceType
        self.derivedFrom = Array(Set(derivedFrom)).sorted { $0.rawValue < $1.rawValue }
        self.missingEvidence = Array(Set(missingEvidence)).sorted { $0.rawValue < $1.rawValue }
        self.authorityCeiling = authorityCeiling
    }

    public func isValidFailClosed(strength: InferenceStrength) -> Bool {
        guard authorityCeiling == .nonInterventional else { return false }
        guard !derivedFrom.isEmpty else { return false }
        if strength == .bounded && missingEvidence.isEmpty {
            return false
        }
        return true
    }
}

public enum InferenceProvenanceFactory {
    public static func weekly(
        strength: InferenceStrength,
        derivedFrom: [DerivedFromSignal],
        workoutCount: Int,
        hrvSampledWorkoutCount: Int
    ) -> InferenceProvenance {
        let type: InferenceType
        switch strength {
        case .direct: type = .directObservation
        case .bounded: type = .boundedSynthesis
        case .sparse: type = .sparseInference
        }

        var missing: [MissingEvidence] = [.sleep]
        if workoutCount == 0 || hrvSampledWorkoutCount == 0 {
            missing.append(.hrv)
        }

        return InferenceProvenance(
            inferenceType: type,
            derivedFrom: derivedFrom,
            missingEvidence: missing,
            authorityCeiling: .nonInterventional
        )
    }
}
