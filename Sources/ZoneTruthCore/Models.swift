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

public enum TrainingMetricKind: String, Codable, CaseIterable, Sendable {
    case vo2Max = "vo2max"
    case heartRateRecovery = "heart_rate_recovery"
    case runningPower = "running_power"
    case cyclingPower = "cycling_power"
    case workoutRoute = "workout_route"
    case externalLoadDecoupling = "external_load_decoupling"
    case vo2IntervalQuality = "vo2_interval_quality"
    case zone2HeartRateRange = "zone2_hr_range"
    case strength
}

public enum TrainingMetricMethodTier: String, Codable, CaseIterable, Sendable {
    case goldStandardAnchor = "gold_standard_anchor"
    case fieldEstimator = "field_estimator"
    case productReference = "product_reference"
    case weakHeuristic = "weak_heuristic"
}

public enum TrainingMetricMethodSource: String, Codable, CaseIterable, Sendable {
    case cpet
    case lactateTest = "lactate_test"
    case ventilatoryThreshold = "ventilatory_threshold"
    case apple
    case garmin
    case firstbeat
    case runningHRSpeed = "running_hr_speed"
    case cyclingPowerHR = "cycling_power_hr"
    case workoutRoute = "workout_route"
    case hrDrift = "hr_drift"
    case hrvThreshold = "hrv_threshold"
    case talkTest = "talk_test"
    case percentHRMax = "percent_hrmax"
    case policyZoneBounds = "policy_zone_bounds"
    case heartRatePattern = "heart_rate_pattern"
    case e1RM = "e1rm"
    case direct1RM = "direct_1rm"
    case gripStrength = "grip_strength"
    case userInput = "user_input"
    case unknown
}

public struct VO2MaxEstimate: Codable, Equatable, Hashable, Sendable {
    public let value: Double
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let measuredAt: Date?

    public init(
        value: Double,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.value = value
        self.source = source
        self.sourceLabel = sourceLabel
        self.measuredAt = measuredAt
    }
}

public struct StrengthMetric: Codable, Equatable, Hashable, Sendable {
    public let exerciseName: String
    public let value: Double
    public let unit: String
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let repetitions: Int?
    public let loadValue: Double?
    public let loadUnit: String?
    public let measuredAt: Date?

    public init(
        exerciseName: String,
        value: Double,
        unit: String = "kg",
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        repetitions: Int? = nil,
        loadValue: Double? = nil,
        loadUnit: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.exerciseName = exerciseName
        self.value = value
        self.unit = unit
        self.source = source
        self.sourceLabel = sourceLabel
        self.repetitions = repetitions
        self.loadValue = loadValue
        self.loadUnit = loadUnit
        self.measuredAt = measuredAt
    }
}

public struct HeartRateRecoveryObservation: Codable, Equatable, Hashable, Sendable {
    public let value: Double
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let measuredAt: Date?

    public init(
        value: Double,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.value = value
        self.source = source
        self.sourceLabel = sourceLabel
        self.measuredAt = measuredAt
    }
}

public struct RunningPowerObservation: Codable, Equatable, Hashable, Sendable {
    public let averageWatts: Double
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let measuredAt: Date?

    public init(
        averageWatts: Double,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.averageWatts = averageWatts
        self.source = source
        self.sourceLabel = sourceLabel
        self.measuredAt = measuredAt
    }
}

public struct CyclingPowerObservation: Codable, Equatable, Hashable, Sendable {
    public let averageWatts: Double
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let measuredAt: Date?

    public init(
        averageWatts: Double,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.averageWatts = averageWatts
        self.source = source
        self.sourceLabel = sourceLabel
        self.measuredAt = measuredAt
    }
}

public struct WorkoutRouteObservation: Codable, Equatable, Hashable, Sendable {
    public let pointCount: Int
    public let elevationGainMeters: Double?
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?

    public init(
        pointCount: Int,
        elevationGainMeters: Double? = nil,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil
    ) {
        self.pointCount = pointCount
        self.elevationGainMeters = elevationGainMeters
        self.source = source
        self.sourceLabel = sourceLabel
    }
}

public struct ExternalLoadDecouplingObservation: Codable, Equatable, Hashable, Sendable {
    public let decouplingRatio: Double
    public let firstHalfAverageHeartRate: Double
    public let secondHalfAverageHeartRate: Double
    public let firstHalfAverageWatts: Double
    public let secondHalfAverageWatts: Double
    public let source: TrainingMetricMethodSource
    public let sourceLabel: String?
    public let measuredAt: Date?

    public init(
        decouplingRatio: Double,
        firstHalfAverageHeartRate: Double,
        secondHalfAverageHeartRate: Double,
        firstHalfAverageWatts: Double,
        secondHalfAverageWatts: Double,
        source: TrainingMetricMethodSource,
        sourceLabel: String? = nil,
        measuredAt: Date? = nil
    ) {
        self.decouplingRatio = decouplingRatio
        self.firstHalfAverageHeartRate = firstHalfAverageHeartRate
        self.secondHalfAverageHeartRate = secondHalfAverageHeartRate
        self.firstHalfAverageWatts = firstHalfAverageWatts
        self.secondHalfAverageWatts = secondHalfAverageWatts
        self.source = source
        self.sourceLabel = sourceLabel
        self.measuredAt = measuredAt
    }
}

public enum ReferenceStandardDistance: String, Codable, CaseIterable, Sendable {
    case direct
    case oneLevelBelow = "one_level_below"
    case twoOrMoreLevelsBelow = "two_or_more_levels_below"
    case unknown
}

public enum TrainingMetricConfidenceLevel: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case mediumLow = "medium_low"
    case low
    case unknown
}

public enum TrainingMetricClaimCeiling: String, Codable, CaseIterable, Sendable {
    case measuredIfDirect = "measured_if_direct"
    case estimateOnly = "estimate_only"
    case startingPointOnly = "starting_point_only"
    case unsupported

    public static func defaultCeiling(for method: TrainingMetricMethod) -> TrainingMetricClaimCeiling {
        if method.tier == .goldStandardAnchor && method.referenceStandardDistance == .direct {
            return .measuredIfDirect
        }

        switch method.tier {
        case .goldStandardAnchor, .fieldEstimator, .productReference:
            return .estimateOnly
        case .weakHeuristic:
            return .startingPointOnly
        }
    }
}

public struct TrainingMetricMethod: Codable, Equatable, Hashable, Sendable {
    public let tier: TrainingMetricMethodTier
    public let source: TrainingMetricMethodSource
    public let name: String
    public let referenceStandardDistance: ReferenceStandardDistance

    public init(
        tier: TrainingMetricMethodTier,
        source: TrainingMetricMethodSource,
        name: String,
        referenceStandardDistance: ReferenceStandardDistance
    ) {
        self.tier = tier
        self.source = source
        self.name = name
        self.referenceStandardDistance = referenceStandardDistance
    }
}

public struct TrainingMetricConfidence: Codable, Equatable, Hashable, Sendable {
    public let level: TrainingMetricConfidenceLevel
    public let basis: String
    public let limitingFactors: [String]

    public init(
        level: TrainingMetricConfidenceLevel,
        basis: String,
        limitingFactors: [String] = []
    ) {
        self.level = level
        self.basis = basis
        self.limitingFactors = limitingFactors
    }
}

public struct TrainingMetricClaim: Codable, Equatable, Hashable, Sendable {
    public let ceiling: TrainingMetricClaimCeiling
    public let allowedTerms: [String]
    public let forbiddenTerms: [String]

    public init(
        ceiling: TrainingMetricClaimCeiling,
        allowedTerms: [String] = [],
        forbiddenTerms: [String] = []
    ) {
        self.ceiling = ceiling
        self.allowedTerms = allowedTerms
        self.forbiddenTerms = forbiddenTerms
    }
}

public enum TrainingMetricClaimProfileKind: String, Codable, CaseIterable, Sendable {
    case vo2MaxEstimate = "vo2max_estimate"
    case heartRateRecoveryContext = "heart_rate_recovery_context"
    case runningPowerContext = "running_power_context"
    case cyclingPowerContext = "cycling_power_context"
    case workoutRouteContext = "workout_route_context"
    case externalLoadDecouplingContext = "external_load_decoupling_context"
    case vo2IntervalPattern = "vo2_interval_pattern"
    case zone2ThresholdRange = "zone2_threshold_range"
    case strengthMeasurement = "strength_measurement"
    case strengthSessionPattern = "strength_session_pattern"
    case genericObservation = "generic_observation"
}

public struct TrainingMetricClaimProfile: Codable, Equatable, Hashable, Sendable {
    public let kind: TrainingMetricClaimProfileKind
    public let displayName: String
    public let disclosure: String
    public let forbiddenTerms: [String]

    public init(
        kind: TrainingMetricClaimProfileKind,
        displayName: String,
        disclosure: String,
        forbiddenTerms: [String]
    ) {
        self.kind = kind
        self.displayName = displayName
        self.disclosure = disclosure
        self.forbiddenTerms = forbiddenTerms
    }

    public static func resolve(for metadata: TrainingMetricMetadata) -> TrainingMetricClaimProfile {
        switch metadata.metric {
        case .vo2Max:
            return TrainingMetricClaimProfile(
                kind: .vo2MaxEstimate,
                displayName: "最大攝氧量估算",
                disclosure: "VO2 max 需要 CPET / GXT 氣體分析才可視為直接測量；其他來源應維持估算或產品參考語氣。",
                forbiddenTerms: ["true VO2 max", "lab-equivalent", "VO2 max 實測"]
            )
        case .heartRateRecovery:
            return TrainingMetricClaimProfile(
                kind: .heartRateRecoveryContext,
                displayName: "恢復脈絡",
                disclosure: "1 分鐘心率恢復可作為恢復脈絡觀察，但不能等同最大攝氧量、臨床恢復診斷或完整心肺評估。",
                forbiddenTerms: ["recovery diagnosis", "VO2 max measurement", "clinical recovery diagnosis"]
            )
        case .runningPower:
            return TrainingMetricClaimProfile(
                kind: .runningPowerContext,
                displayName: "跑步功率脈絡",
                disclosure: "跑步功率可作為外部負荷與場地強度脈絡，但不能單獨視為閾值或 VO2 max 測量。",
                forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
            )
        case .cyclingPower:
            return TrainingMetricClaimProfile(
                kind: .cyclingPowerContext,
                displayName: "自行車功率脈絡",
                disclosure: "自行車功率可作為外部負荷與場地強度脈絡，但不能單獨視為閾值或 VO2 max 測量。",
                forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
            )
        case .workoutRoute:
            return TrainingMetricClaimProfile(
                kind: .workoutRouteContext,
                displayName: "路線脈絡",
                disclosure: "路線與地形資料可作為戶外訓練脈絡，但不能單獨視為閾值、VO2 max 或訓練品質結論。",
                forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
            )
        case .externalLoadDecoupling:
            return TrainingMetricClaimProfile(
                kind: .externalLoadDecouplingContext,
                displayName: "負荷一致性脈絡",
                disclosure: "前後半段心率與功率比例變化可作為外部負荷一致性線索，但不能單獨視為閾值、VO2 max 或訓練品質結論。",
                forbiddenTerms: ["threshold measurement", "VO2 max measurement", "exact Zone 2"]
            )
        case .vo2IntervalQuality:
            return TrainingMetricClaimProfile(
                kind: .vo2IntervalPattern,
                displayName: "VO2 間歇型態",
                disclosure: "目前只描述間歇訓練型態，不代表已推估或測量最大攝氧量數值。",
                forbiddenTerms: ["true VO2 max", "lab-equivalent", "VO2 max 實測"]
            )
        case .zone2HeartRateRange:
            return TrainingMetricClaimProfile(
                kind: .zone2ThresholdRange,
                displayName: "Zone 2 心率範圍",
                disclosure: "Zone 2 精準界線需由 LT1 / VT1 / GET 等閾值測試確認；未驗證來源只能作為估算或起始參考。",
                forbiddenTerms: ["exact Zone 2", "optimal Zone 2", "精準 Zone 2"]
            )
        case .strength:
            if metadata.method.source == .direct1RM || metadata.method.source == .e1RM || metadata.method.source == .gripStrength {
                return TrainingMetricClaimProfile(
                    kind: .strengthMeasurement,
                    displayName: "肌力指標",
                    disclosure: "肌力數值需保留動作、負重、次數、ROM 與測試協議脈絡。",
                    forbiddenTerms: ["whole-body strength", "clinical strength diagnosis", "全身肌力診斷"]
                )
            }
            return TrainingMetricClaimProfile(
                kind: .strengthSessionPattern,
                displayName: "肌力訓練型態",
                disclosure: "目前只描述心率型態，不能代表最大肌力、1RM 或力輸出測量。",
                forbiddenTerms: ["measured strength", "1RM", "force output", "肌力測量"]
            )
        }
    }
}

public struct TrainingMetricMetadata: Codable, Equatable, Hashable, Sendable {
    public let metric: TrainingMetricKind
    public let method: TrainingMetricMethod
    public let confidence: TrainingMetricConfidence
    public let claim: TrainingMetricClaim
    public let dataQualityFlags: [String]
    public let recommendedValidation: String?

    public init(
        metric: TrainingMetricKind,
        method: TrainingMetricMethod,
        confidence: TrainingMetricConfidence,
        claim: TrainingMetricClaim? = nil,
        dataQualityFlags: [String] = [],
        recommendedValidation: String? = nil
    ) {
        self.metric = metric
        self.method = method
        self.confidence = confidence
        self.claim = claim ?? TrainingMetricClaim(
            ceiling: TrainingMetricClaimCeiling.defaultCeiling(for: method)
        )
        self.dataQualityFlags = dataQualityFlags
        self.recommendedValidation = recommendedValidation
    }

    public var isClaimCeilingAdmissible: Bool {
        switch claim.ceiling {
        case .measuredIfDirect:
            guard method.tier == .goldStandardAnchor,
                  method.referenceStandardDistance == .direct
            else {
                return false
            }
        case .estimateOnly:
            guard method.tier != .weakHeuristic else { return false }
        case .startingPointOnly, .unsupported:
            break
        }

        if metric == .zone2HeartRateRange && method.source == .percentHRMax {
            let allowedConfidence = confidence.level == .low || confidence.level == .unknown
            let allowedClaim = claim.ceiling == .startingPointOnly || claim.ceiling == .unsupported
            return allowedConfidence && allowedClaim
        }

        return true
    }

    public var claimProfile: TrainingMetricClaimProfile {
        TrainingMetricClaimProfile.resolve(for: self)
    }
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
    public let vo2MaxEstimate: VO2MaxEstimate?
    public let heartRateRecoveryOneMinute: HeartRateRecoveryObservation?
    public let runningPower: RunningPowerObservation?
    public let cyclingPower: CyclingPowerObservation?
    public let workoutRoute: WorkoutRouteObservation?
    public let externalLoadDecoupling: ExternalLoadDecouplingObservation?
    public let strengthMetrics: [StrengthMetric]

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
        totalDistanceMeters: Double? = nil,
        vo2MaxEstimate: VO2MaxEstimate? = nil,
        heartRateRecoveryOneMinute: HeartRateRecoveryObservation? = nil,
        runningPower: RunningPowerObservation? = nil,
        cyclingPower: CyclingPowerObservation? = nil,
        workoutRoute: WorkoutRouteObservation? = nil,
        externalLoadDecoupling: ExternalLoadDecouplingObservation? = nil,
        strengthMetrics: [StrengthMetric] = []
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
        self.vo2MaxEstimate = vo2MaxEstimate
        self.heartRateRecoveryOneMinute = heartRateRecoveryOneMinute
        self.runningPower = runningPower
        self.cyclingPower = cyclingPower
        self.workoutRoute = workoutRoute
        self.externalLoadDecoupling = externalLoadDecoupling
        self.strengthMetrics = strengthMetrics
    }

    public static func defaultIntent(for workoutType: WorkoutType) -> TrainingIntent {
        switch workoutType {
        case .strengthTraining:
            return .strength
        case .running, .cycling, .swimming, .walking:
            return .zone2
        case .mixed:
            return .vo2Interval
        case .other:
            return .zone2
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
        case vo2MaxEstimate
        case heartRateRecoveryOneMinute
        case runningPower
        case cyclingPower
        case workoutRoute
        case externalLoadDecoupling
        case strengthMetrics
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
        let vo2MaxEstimate = try container.decodeIfPresent(VO2MaxEstimate.self, forKey: .vo2MaxEstimate)
        let heartRateRecoveryOneMinute = try container.decodeIfPresent(HeartRateRecoveryObservation.self, forKey: .heartRateRecoveryOneMinute)
        let runningPower = try container.decodeIfPresent(RunningPowerObservation.self, forKey: .runningPower)
        let cyclingPower = try container.decodeIfPresent(CyclingPowerObservation.self, forKey: .cyclingPower)
        let workoutRoute = try container.decodeIfPresent(WorkoutRouteObservation.self, forKey: .workoutRoute)
        let externalLoadDecoupling = try container.decodeIfPresent(ExternalLoadDecouplingObservation.self, forKey: .externalLoadDecoupling)
        let strengthMetrics = try container.decodeIfPresent([StrengthMetric].self, forKey: .strengthMetrics) ?? []

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
            totalDistanceMeters: totalDistanceMeters,
            vo2MaxEstimate: vo2MaxEstimate,
            heartRateRecoveryOneMinute: heartRateRecoveryOneMinute,
            runningPower: runningPower,
            cyclingPower: cyclingPower,
            workoutRoute: workoutRoute,
            externalLoadDecoupling: externalLoadDecoupling,
            strengthMetrics: strengthMetrics
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
        try container.encodeIfPresent(vo2MaxEstimate, forKey: .vo2MaxEstimate)
        try container.encodeIfPresent(heartRateRecoveryOneMinute, forKey: .heartRateRecoveryOneMinute)
        try container.encodeIfPresent(runningPower, forKey: .runningPower)
        try container.encodeIfPresent(cyclingPower, forKey: .cyclingPower)
        try container.encodeIfPresent(workoutRoute, forKey: .workoutRoute)
        try container.encodeIfPresent(externalLoadDecoupling, forKey: .externalLoadDecoupling)
        if !strengthMetrics.isEmpty {
            try container.encode(strengthMetrics, forKey: .strengthMetrics)
        }
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
    public let metricMetadata: [TrainingMetricMetadata]

    public init(
        verdict: AnalysisVerdict,
        confidence: Double,
        reasons: [String],
        recommendations: [String],
        zoneDistribution: ZoneDistribution,
        stabilityStandardDeviation: Double? = nil,
        driftRatio: Double? = nil,
        metricMetadata: [TrainingMetricMetadata] = []
    ) {
        self.verdict = verdict
        self.confidence = confidence
        self.reasons = reasons
        self.recommendations = recommendations
        self.zoneDistribution = zoneDistribution
        self.stabilityStandardDeviation = stabilityStandardDeviation
        self.driftRatio = driftRatio
        self.metricMetadata = metricMetadata
    }

    public func appendingMetricMetadata(_ extraMetadata: [TrainingMetricMetadata]) -> AnalysisResult {
        guard !extraMetadata.isEmpty else { return self }
        return AnalysisResult(
            verdict: verdict,
            confidence: confidence,
            reasons: reasons,
            recommendations: recommendations,
            zoneDistribution: zoneDistribution,
            stabilityStandardDeviation: stabilityStandardDeviation,
            driftRatio: driftRatio,
            metricMetadata: metricMetadata + extraMetadata
        )
    }
}

public enum TrainingMode: String, Codable, CaseIterable, Sendable {
    case zone2
    case vo2Stimulus = "vo2_stimulus"
    case strengthPattern = "strength_pattern"
    case conditioningLike = "conditioning_like"
    case generalLowIntensity = "general_low_intensity"
    case mixed
    case insufficientData = "insufficient_data"
}

public enum ClassificationConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case mediumHigh = "medium_high"
    case medium
    case low
    case insufficient
}

public enum TrainingDataQuality: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case insufficient
}

public enum TrainingClaimLevel: String, Codable, CaseIterable, Sendable {
    case primaryClassification = "primary_classification"
    case secondaryReference = "secondary_reference"
    case referenceOnly = "reference_only"
    case notApplicable = "not_applicable"
    case unsupported
}

public enum TrainingClassificationEvidenceDirection: String, Codable, CaseIterable, Sendable {
    case supports
    case weakens
    case neutral
}

public enum TrainingClassificationVisibility: String, Codable, CaseIterable, Sendable {
    case userVisible = "user_visible"
    case advancedUser = "advanced_user"
    case devOnly = "dev_only"
}

public struct TrainingClassificationEvidence: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let direction: TrainingClassificationEvidenceDirection
    public let explanation: String
    public let visibility: TrainingClassificationVisibility

    public init(
        label: String,
        value: String,
        direction: TrainingClassificationEvidenceDirection,
        explanation: String,
        visibility: TrainingClassificationVisibility = .userVisible
    ) {
        self.label = label
        self.value = value
        self.direction = direction
        self.explanation = explanation
        self.visibility = visibility
    }
}

public enum TrainingClassificationWarningType: String, Codable, CaseIterable, Sendable {
    case lowHeartRateQuality = "low_hr_quality"
    case insufficientDuration = "insufficient_duration"
    case ambiguousPattern = "ambiguous_pattern"
    case unsupportedClaim = "unsupported_claim"
    case missingPersonalZones = "missing_personal_zones"
    case unsupportedActivityType = "unsupported_activity_type"
}

public struct TrainingClassificationWarning: Codable, Equatable, Hashable, Sendable {
    public let type: TrainingClassificationWarningType
    public let message: String
    public let visibility: TrainingClassificationVisibility

    public init(
        type: TrainingClassificationWarningType,
        message: String,
        visibility: TrainingClassificationVisibility = .userVisible
    ) {
        self.type = type
        self.message = message
        self.visibility = visibility
    }
}

public enum TrainingNotApplicableModel: String, Codable, CaseIterable, Sendable {
    case zone2
    case vo2Stimulus = "vo2_stimulus"
    case strengthPattern = "strength_pattern"
    case hrDrift = "hr_drift"
}

public enum TrainingNotApplicableReasonCode: String, Codable, CaseIterable, Sendable {
    case activityTypeNotSupported = "activity_type_not_supported"
    case insufficientHeartRateData = "insufficient_hr_data"
    case noStableSegment = "no_stable_segment"
    case notSteadyStateActivity = "not_steady_state_activity"
    case missingRequiredData = "missing_required_data"
}

public struct TrainingNotApplicableReason: Codable, Equatable, Hashable, Sendable {
    public let model: TrainingNotApplicableModel
    public let reason: TrainingNotApplicableReasonCode
    public let message: String
    public let visibility: TrainingClassificationVisibility

    public init(
        model: TrainingNotApplicableModel,
        reason: TrainingNotApplicableReasonCode,
        message: String,
        visibility: TrainingClassificationVisibility = .advancedUser
    ) {
        self.model = model
        self.reason = reason
        self.message = message
        self.visibility = visibility
    }
}

public struct TrainingClassificationDebug: Codable, Equatable, Sendable {
    public let classificationVersion: String
    public let zoneConfigVersion: String?
    public let usedPersonalizedZones: Bool
    public let ruleScores: [String: Double]
    public let notes: [String]

    public init(
        classificationVersion: String,
        zoneConfigVersion: String? = nil,
        usedPersonalizedZones: Bool,
        ruleScores: [String: Double] = [:],
        notes: [String] = []
    ) {
        self.classificationVersion = classificationVersion
        self.zoneConfigVersion = zoneConfigVersion
        self.usedPersonalizedZones = usedPersonalizedZones
        self.ruleScores = ruleScores
        self.notes = notes
    }
}

public struct TrainingClassification: Codable, Equatable, Sendable {
    public let primaryMode: TrainingMode
    public let confidence: ClassificationConfidence
    public let dataQuality: TrainingDataQuality
    public let claimLevel: TrainingClaimLevel
    public let evidence: [TrainingClassificationEvidence]
    public let warnings: [TrainingClassificationWarning]
    public let notApplicableReasons: [TrainingNotApplicableReason]
    public let debug: TrainingClassificationDebug?

    public init(
        primaryMode: TrainingMode,
        confidence: ClassificationConfidence,
        dataQuality: TrainingDataQuality,
        claimLevel: TrainingClaimLevel,
        evidence: [TrainingClassificationEvidence],
        warnings: [TrainingClassificationWarning] = [],
        notApplicableReasons: [TrainingNotApplicableReason] = [],
        debug: TrainingClassificationDebug? = nil
    ) {
        self.primaryMode = primaryMode
        self.confidence = confidence
        self.dataQuality = dataQuality
        self.claimLevel = claimLevel
        self.evidence = evidence
        self.warnings = warnings
        self.notApplicableReasons = notApplicableReasons
        self.debug = debug
    }
}

public struct WeeklyTrainingModeDistributionItem: Codable, Equatable, Sendable {
    public let mode: TrainingMode
    public let count: Int
    public let ratio: Double

    public init(mode: TrainingMode, count: Int, ratio: Double) {
        self.mode = mode
        self.count = count
        self.ratio = ratio
    }
}

public struct WeeklyTrainingModeDistribution: Codable, Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let workoutCount: Int
    public let counts: [TrainingMode: Int]
    public let ratios: [TrainingMode: Double]
    public let items: [WeeklyTrainingModeDistributionItem]
    public let descriptiveLines: [String]

    public init(
        weekStart: Date,
        weekEnd: Date,
        workoutCount: Int,
        counts: [TrainingMode: Int],
        ratios: [TrainingMode: Double],
        items: [WeeklyTrainingModeDistributionItem],
        descriptiveLines: [String]
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.workoutCount = workoutCount
        self.counts = counts
        self.ratios = ratios
        self.items = items
        self.descriptiveLines = descriptiveLines
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

public enum CalibrationSuggestionSource: String, Codable, Equatable, Sendable {
    case restingHeartRateHeuristic
    case driftTrend

    public var displayLabel: String {
        switch self {
        case .restingHeartRateHeuristic:
            return "來源：Resting HR 起始建議"
        case .driftTrend:
            return "來源：歷史心率飄移校正"
        }
    }

    public var verificationLabel: String {
        switch self {
        case .restingHeartRateHeuristic:
            return "非驗證閾值"
        case .driftTrend:
            return "訓練觀測校正"
        }
    }
}

public struct RestingHeartRateSuggestionOffsets: Codable, Equatable, Hashable, Sendable {
    public let lowerOffset: Double
    public let upperOffset: Double

    public init(lowerOffset: Double, upperOffset: Double) {
        self.lowerOffset = lowerOffset
        self.upperOffset = upperOffset
    }

    public static let `default` = RestingHeartRateSuggestionOffsets(
        lowerOffset: 55,
        upperOffset: 70
    )
}

public struct CalibrationSuggestion: Equatable, Sendable {
    public let currentBounds: ZoneBounds
    public let suggestedBounds: ZoneBounds
    public let reason: String
    public let confidence: Double
    public let source: CalibrationSuggestionSource
    public let sourceSessionIDs: [UUID]

    public init(
        currentBounds: ZoneBounds,
        suggestedBounds: ZoneBounds,
        reason: String,
        confidence: Double,
        source: CalibrationSuggestionSource,
        sourceSessionIDs: [UUID]
    ) {
        self.currentBounds = currentBounds
        self.suggestedBounds = suggestedBounds
        self.reason = reason
        self.confidence = confidence
        self.source = source
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
