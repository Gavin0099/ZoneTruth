import Foundation
import ZoneTruthCore

@MainActor
final class SettingsManager: ObservableObject {
    @Published var policy: AnalysisPolicy
    @Published var pendingSuggestion: CalibrationSuggestion?
    @Published var migrationMode: MigrationMode
    @Published var trainingGoal: UserTrainingGoal?

    private let userDefaults: UserDefaults
    private let policyKey = "com.zonetruth.analysisPolicy"
    private let migrationModeKey = "com.zonetruth.migrationMode"
    private let trainingGoalKey = "com.zonetruth.trainingGoal"

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

    func updateMigrationMode(_ mode: MigrationMode) {
        // P1j guard: policy_primary is reserved until migration gates are explicitly unlocked.
        let effectiveMode: MigrationMode = (mode == .policyPrimary) ? .observeOnly : mode
        migrationMode = effectiveMode
        userDefaults.set(effectiveMode.rawValue, forKey: migrationModeKey)
    }
}
