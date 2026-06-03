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

    private let userDefaults: UserDefaults
    private let policyKey = "com.zonetruth.analysisPolicy"
    private let migrationModeKey = "com.zonetruth.migrationMode"
    private let trainingGoalKey = "com.zonetruth.trainingGoal"
    private let defaultIntentOverridesKey = "com.zonetruth.defaultIntentOverrides"
    private let restingHeartRateKey = "com.zonetruth.restingHeartRate"

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
            currentPolicy: policy
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
            resting
        ].joined(separator: "|")
    }

    var isUsingCustomZoneBounds: Bool {
        policy.zoneBounds != AnalysisPolicy.default.zoneBounds
    }

    private func saveDefaultIntentOverrides() {
        let rawMap = Dictionary(uniqueKeysWithValues: defaultIntentOverrides.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(rawMap) {
            userDefaults.set(encoded, forKey: defaultIntentOverridesKey)
        }
    }
}
