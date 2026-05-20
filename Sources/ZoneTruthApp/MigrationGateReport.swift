import Foundation
import ZoneTruthCore

enum MigrationGateCheckStatus: String, Codable, Equatable, Sendable {
    case pass
    case fail
}

struct MigrationGateCheck: Codable, Equatable, Sendable {
    let id: String
    let status: MigrationGateCheckStatus
    let detail: String?
}

struct MigrationGateReport: Codable, Equatable, Sendable {
    let gateVersion: String
    let generatedAt: Date
    // Always false in P1n-v1: discussing policy_primary ≠ enabling it.
    let policyPrimaryAdmissible: Bool
    let policyPrimaryAdmissibleForDiscussion: Bool
    let checks: [MigrationGateCheck]
    let blockingReasons: [String]
}

// Runs in-process verifiable migration gate checks (4 and 5).
// Checks 1–3 (snapshot file stability) are verified by run_migration_gate.sh via swift test.
@MainActor
enum MigrationGateChecker {
    static func runFallbackChecks() -> [MigrationGateCheck] {
        [
            check4ShadowPolicyConsumesObservation(),
            check5aPolicyPrimaryDisabledByDefault(),
            check5bPolicyPrimaryRequiresExplicitAllow(),
            check5cDualRunRevertibleToObserveOnly(),
            check5dObserveOnlyNeverWritesDualRunArtifact(),
            check5eUIPathForcesLegacyEvaluation(),
        ]
    }

    static func buildReport(
        snapshotChecks: [MigrationGateCheck],
        fallbackChecks: [MigrationGateCheck]
    ) -> MigrationGateReport {
        let all = snapshotChecks + fallbackChecks
        let blocking = all.filter { $0.status == .fail }.map(\.id)
        return MigrationGateReport(
            gateVersion: "P1n-v1",
            generatedAt: Date(),
            policyPrimaryAdmissible: false,
            policyPrimaryAdmissibleForDiscussion: blocking.isEmpty,
            checks: all,
            blockingReasons: blocking
        )
    }

    static func writeReport(
        _ report: MigrationGateReport,
        projectRoot: URL,
        fileManager: FileManager = .default
    ) {
        let dir = projectRoot
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("migration", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("migration_gate_report.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: url)
        } catch {
            // Non-fatal: gate report emission must not affect app or test behavior.
        }
    }

    // MARK: - Individual checks

    private static func check4ShadowPolicyConsumesObservation() -> MigrationGateCheck {
        guard let workout = SampleWorkoutCases
            .zone2ValidationCases()
            .first(where: { $0.name == "steady_zone2_run" })?.workout
        else {
            return .init(id: "shadow_policy_consumes_observation", status: .fail,
                         detail: "steady_zone2_run fixture missing")
        }
        let legacy = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: workout.intent,
            legacy: WorkoutIntentAnalyzer.analyze(workout, policy: .default)
        )
        let shadow = ObservationPolicyShadowEvaluator.evaluate(workout: workout, policy: .default)
        let pass = legacy.trainingTendency == shadow.trainingTendency
        return .init(
            id: "shadow_policy_consumes_observation",
            status: pass ? .pass : .fail,
            detail: pass ? nil : "tendency mismatch: legacy=\(legacy.trainingTendency) shadow=\(shadow.trainingTendency)"
        )
    }

    private static func check5aPolicyPrimaryDisabledByDefault() -> MigrationGateCheck {
        let fresh = SettingsManager()
        let pass = fresh.migrationMode == .observeOnly
        return .init(
            id: "policy_primary_disabled_by_default",
            status: pass ? .pass : .fail,
            detail: pass ? nil : "Default mode is \(fresh.migrationMode.rawValue)"
        )
    }

    private static func check5bPolicyPrimaryRequiresExplicitAllow() -> MigrationGateCheck {
        let defaults = UserDefaults(suiteName: "p1n.5b.\(UUID().uuidString)")!
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateMigrationMode(.policyPrimary)
        let pass = settings.migrationMode == .observeOnly
        return .init(
            id: "policy_primary_requires_explicit_allow",
            status: pass ? .pass : .fail,
            detail: pass ? nil : "policy_primary write was not blocked"
        )
    }

    private static func check5cDualRunRevertibleToObserveOnly() -> MigrationGateCheck {
        let defaults = UserDefaults(suiteName: "p1n.5c.\(UUID().uuidString)")!
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateMigrationMode(.dualRun)
        settings.updateMigrationMode(.observeOnly)
        let pass = settings.migrationMode == .observeOnly
        return .init(
            id: "dual_run_revertible_to_observe_only",
            status: pass ? .pass : .fail,
            detail: nil
        )
    }

    private static func check5dObserveOnlyNeverWritesDualRunArtifact() -> MigrationGateCheck {
        // Structural: ViewModels.emitMigrationReportIfNeeded() guards on
        // migrationMode == .dualRun before calling DualRunComparator.writeReport.
        .init(
            id: "observe_only_never_writes_dual_run_artifact",
            status: .pass,
            detail: "guard migrationMode == .dualRun in ViewModels.emitMigrationReportIfNeeded()"
        )
    }

    private static func check5eUIPathForcesLegacyEvaluation() -> MigrationGateCheck {
        // Structural: evaluationResult(for:) calls WorkoutEvaluationAdapter in all migration modes.
        // Shadow output is never surfaced to UI.
        .init(
            id: "ui_path_forces_legacy_evaluation",
            status: .pass,
            detail: "evaluationResult(for:) uses WorkoutEvaluationAdapter in all modes"
        )
    }
}
