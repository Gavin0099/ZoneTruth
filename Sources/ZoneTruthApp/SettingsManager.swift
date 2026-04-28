import Foundation
import ZoneTruthCore

@MainActor
final class SettingsManager: ObservableObject {
    @Published var policy: AnalysisPolicy

    private let userDefaults: UserDefaults
    private let policyKey = "com.zonetruth.analysisPolicy"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        if let data = userDefaults.data(forKey: policyKey),
           let decoded = try? JSONDecoder().decode(AnalysisPolicy.self, from: data) {
            self.policy = decoded
        } else {
            self.policy = .default
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
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(policy) {
            userDefaults.set(encoded, forKey: policyKey)
        }
    }
}
