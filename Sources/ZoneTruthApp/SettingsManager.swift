import Foundation
import ZoneTruthCore

@MainActor
final class SettingsManager: ObservableObject {
    @Published var policy: AnalysisPolicy
    @Published var pendingSuggestion: CalibrationSuggestion?
    @Published var migrationMode: MigrationMode
    @Published var trainingGoal: UserTrainingGoal?
    @Published var defaultIntentOverrides: [WorkoutType: TrainingIntent]
    @Published var restingHeartRate: Double?
    @Published var restingHeartRateSuggestionOffsets: RestingHeartRateSuggestionOffsets
    @Published private(set) var zoneBoundsSource: CalibrationSuggestionSource?

    private let userDefaults: UserDefaults
    private let policyKey = "com.zonetruth.analysisPolicy"
    private let migrationModeKey = "com.zonetruth.migrationMode"
    private let trainingGoalKey = "com.zonetruth.trainingGoal"
    private let defaultIntentOverridesKey = "com.zonetruth.defaultIntentOverrides"
    private let restingHeartRateKey = "com.zonetruth.restingHeartRate"
    private let restingHeartRateSuggestionOffsetsKey = "com.zonetruth.restingHeartRateSuggestionOffsets"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: policyKey),
           let decoded = try? JSONDecoder().decode(AnalysisPolicy.self, from: data) {
            self.policy = decoded
        } else {
            self.policy = .default
        }

        if let raw = userDefaults.string(forKey: migrationModeKey),
           let decoded = MigrationMode(rawValue: raw) {
            self.migrationMode = decoded
        } else {
            self.migrationMode = .observeOnly
        }

        if let raw = userDefaults.string(forKey: trainingGoalKey),
           let decoded = UserTrainingGoal(rawValue: raw) {
            self.trainingGoal = decoded
        } else {
            self.trainingGoal = nil
        }

        if let data = userDefaults.data(forKey: defaultIntentOverridesKey),
           let rawMap = try? JSONDecoder().decode([String: TrainingIntent].self, from: data) {
            var resolved: [WorkoutType: TrainingIntent] = [:]
            for (key, value) in rawMap {
                if let type = WorkoutType(rawValue: key) {
                    resolved[type] = value
                }
            }
            self.defaultIntentOverrides = resolved
        } else {
            self.defaultIntentOverrides = [:]
        }

        let storedRestingHeartRate = userDefaults.object(forKey: restingHeartRateKey) as? Double
        if let storedRestingHeartRate, storedRestingHeartRate > 0 {
            self.restingHeartRate = storedRestingHeartRate
        } else {
            self.restingHeartRate = nil
        }

        if let data = userDefaults.data(forKey: restingHeartRateSuggestionOffsetsKey),
           let decoded = try? JSONDecoder().decode(RestingHeartRateSuggestionOffsets.self, from: data) {
            self.restingHeartRateSuggestionOffsets = Self.validOffsets(decoded) ?? .default
        } else {
            self.restingHeartRateSuggestionOffsets = .default
        }
        self.zoneBoundsSource = nil
    }

    func updatePolicy(_ newPolicy: AnalysisPolicy) {
        self.policy = newPolicy
        save()
    }

    func updateZone2Bounds(lower: Double, upper: Double) {
        let newBounds = ZoneBounds(
            zone2LowerBound: lower,
            zone2UpperBound: upper,
            zone4Threshold: policy.zoneBounds.zone4Threshold,
            zone5Threshold: policy.zoneBounds.zone5Threshold
        )
        let newPolicy = AnalysisPolicy(
            warmupExclusionSeconds: policy.warmupExclusionSeconds,
            cooldownExclusionSeconds: policy.cooldownExclusionSeconds,
            minimumDurationSeconds: policy.minimumDurationSeconds,
            minimumSampleCount: policy.minimumSampleCount,
            abnormalSpikeDeltaBPM: policy.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: policy.lowStabilityStdDev,
            mediumStabilityStdDev: policy.mediumStabilityStdDev,
            zoneBounds: newBounds
        )
        updatePolicy(newPolicy)
        
        // Clear suggestion if manually updated
        pendingSuggestion = nil
        zoneBoundsSource = nil
    }

    func resetZone2BoundsToDefault() {
        let defaultBounds = AnalysisPolicy.default.zoneBounds
        updateZone2Bounds(
            lower: defaultBounds.zone2LowerBound,
            upper: defaultBounds.zone2UpperBound
        )
    }

    func updateCalibrationSuggestion(analyses: [(WorkoutInput, AnalysisResult)]) {
        pendingSuggestion = CalibrationEngine.analyzeDriftTrend(analyses: analyses, currentPolicy: policy)
    }

    func generateRestingHeartRateSuggestion() {
        guard let restingHeartRate else {
            pendingSuggestion = nil
            return
        }
        pendingSuggestion = CalibrationEngine.suggestZoneBounds(
            restingHeartRate: restingHeartRate,
            currentPolicy: policy,
            offsets: restingHeartRateSuggestionOffsets
        )
    }

    func applySuggestion() {
        guard let suggestion = pendingSuggestion else { return }
        let newPolicy = AnalysisPolicy(
            warmupExclusionSeconds: policy.warmupExclusionSeconds,
            cooldownExclusionSeconds: policy.cooldownExclusionSeconds,
            minimumDurationSeconds: policy.minimumDurationSeconds,
            minimumSampleCount: policy.minimumSampleCount,
            abnormalSpikeDeltaBPM: policy.abnormalSpikeDeltaBPM,
            lowStabilityStdDev: policy.lowStabilityStdDev,
            mediumStabilityStdDev: policy.mediumStabilityStdDev,
            zoneBounds: suggestion.suggestedBounds
        )
        updatePolicy(newPolicy)
        zoneBoundsSource = suggestion.source
        pendingSuggestion = nil
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(policy) {
            userDefaults.set(encoded, forKey: policyKey)
        }
    }

    func updateTrainingGoal(_ goal: UserTrainingGoal?) {
        trainingGoal = goal
        if let goal {
            userDefaults.set(goal.rawValue, forKey: trainingGoalKey)
        } else {
            userDefaults.removeObject(forKey: trainingGoalKey)
        }
    }

    func updateRestingHeartRate(_ bpm: Double?) {
        let sanitized: Double?
        if let bpm, bpm > 0 {
            sanitized = bpm
        } else {
            sanitized = nil
        }
        restingHeartRate = sanitized
        if let sanitized {
            userDefaults.set(sanitized, forKey: restingHeartRateKey)
        } else {
            userDefaults.removeObject(forKey: restingHeartRateKey)
        }
    }

    func updateRestingHeartRateSuggestionOffsets(lowerOffset: Double, upperOffset: Double) {
        let offsets = RestingHeartRateSuggestionOffsets(
            lowerOffset: lowerOffset,
            upperOffset: upperOffset
        )
        guard let validOffsets = Self.validOffsets(offsets) else { return }
        restingHeartRateSuggestionOffsets = validOffsets
        if let encoded = try? JSONEncoder().encode(validOffsets) {
            userDefaults.set(encoded, forKey: restingHeartRateSuggestionOffsetsKey)
        }
        pendingSuggestion = nil
    }

    func updateMigrationMode(_ mode: MigrationMode) {
        // P1j guard: policy_primary is reserved until migration gates are explicitly unlocked.
        let effectiveMode: MigrationMode = (mode == .policyPrimary) ? .observeOnly : mode
        migrationMode = effectiveMode
        userDefaults.set(effectiveMode.rawValue, forKey: migrationModeKey)
    }

    func defaultIntent(for workoutType: WorkoutType) -> TrainingIntent {
        defaultIntentOverrides[workoutType] ?? WorkoutInput.defaultIntent(for: workoutType)
    }

    func setDefaultIntent(_ intent: TrainingIntent, for workoutType: WorkoutType) {
        if intent == WorkoutInput.defaultIntent(for: workoutType) {
            defaultIntentOverrides.removeValue(forKey: workoutType)
        } else {
            defaultIntentOverrides[workoutType] = intent
        }
        saveDefaultIntentOverrides()
    }

    var defaultIntentOverrideSignature: String {
        defaultIntentOverrides
            .map { "\($0.key.rawValue)=\($0.value.rawValue)" }
            .sorted()
            .joined(separator: "|")
    }

    var zoneProfileSignature: String {
        let bounds = policy.zoneBounds
        let resting = restingHeartRate.map { String(format: "%.1f", $0) } ?? "nil"
        return [
            String(format: "%.1f", bounds.zone2LowerBound),
            String(format: "%.1f", bounds.zone2UpperBound),
            String(format: "%.1f", bounds.zone4Threshold),
            String(format: "%.1f", bounds.zone5Threshold),
            resting,
            String(format: "%.1f", restingHeartRateSuggestionOffsets.lowerOffset),
            String(format: "%.1f", restingHeartRateSuggestionOffsets.upperOffset)
        ].joined(separator: "|")
    }

    var isUsingCustomZoneBounds: Bool {
        policy.zoneBounds != AnalysisPolicy.default.zoneBounds
    }

    var zone2ProfileStatusSummary: String {
        let bounds = policy.zoneBounds
        let sourceLabel: String
        if zoneBoundsSource == .restingHeartRateHeuristic {
            sourceLabel = "靜息心率建議已套用"
        } else if zoneBoundsSource == .driftTrend {
            sourceLabel = "歷史飄移校正已套用"
        } else if isUsingCustomZoneBounds {
            sourceLabel = "自訂界線"
        } else {
            sourceLabel = "預設界線"
        }

        let restingLabel = restingHeartRate
            .map { "靜息心率 \(Self.formattedBPM($0)) bpm" } ?? "靜息心率未設定"
        let offsetsLabel = "偏移 +\(Self.formattedBPM(restingHeartRateSuggestionOffsets.lowerOffset))/+\(Self.formattedBPM(restingHeartRateSuggestionOffsets.upperOffset))"
        let pendingLabel: String
        if let pendingSuggestion {
            if pendingSuggestion.zone2RangeMatchesCurrent {
                pendingLabel = "目前設定已符合初步參考範圍"
            } else {
                pendingLabel = "可套用初步參考範圍 \(Self.formattedBPM(pendingSuggestion.suggestedBounds.zone2LowerBound))-\(Self.formattedBPM(pendingSuggestion.suggestedBounds.zone2UpperBound)) bpm"
            }
        } else {
            pendingLabel = "沒有待處理參考範圍"
        }

        return "\(sourceLabel) · Zone 2 \(Self.formattedBPM(bounds.zone2LowerBound))-\(Self.formattedBPM(bounds.zone2UpperBound)) bpm · \(restingLabel) · \(offsetsLabel) · \(pendingLabel)"
    }

    private func saveDefaultIntentOverrides() {
        let rawMap = Dictionary(uniqueKeysWithValues: defaultIntentOverrides.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(rawMap) {
            userDefaults.set(encoded, forKey: defaultIntentOverridesKey)
        }
    }

    private static func validOffsets(_ offsets: RestingHeartRateSuggestionOffsets) -> RestingHeartRateSuggestionOffsets? {
        guard offsets.lowerOffset >= 35,
              offsets.upperOffset <= 95,
              offsets.upperOffset > offsets.lowerOffset else {
            return nil
        }
        return offsets
    }

    private static func formattedBPM(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
