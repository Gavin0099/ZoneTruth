import Foundation
import ZoneTruthCore

enum MigrationMode: String, Codable, CaseIterable, Sendable {
    case observeOnly = "observe_only"
    case dualRun = "dual_run"
    case policyPrimary = "policy_primary"
}

enum DualRunReviewStatus: String, Codable, Equatable, Sendable {
    case minorDrift = "minor_drift"
    case reviewRequired = "review_required"
    case blockingDrift = "blocking_drift"
    case invalidReport = "invalid_report"
}

struct EvaluationDiff: Codable, Equatable, Sendable {
    let workoutID: UUID
    let intent: String
    let legacyGoalFitScore: Int
    let shadowGoalFitScore: Int
    let goalFitDelta: Int
    let legacyTendency: String
    let shadowTendency: String
    let tendencyChanged: Bool
    let reviewStatus: DualRunReviewStatus
}

struct DualRunReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let migrationMode: MigrationMode
    let totalWorkouts: Int
    let schemaVersion: String
    let userFacingOverrideApplied: Bool
    let reviewStatus: DualRunReviewStatus
    let diffs: [EvaluationDiff]
}

enum ObservationPolicyShadowEvaluator {
    static func evaluate(
        workout: WorkoutInput,
        policy: AnalysisPolicy
    ) -> WorkoutEvaluation {
        let primitives = WorkoutObservationPrimitiveBuilder.build(workout: workout, policy: policy)
        let intent = ObservationBridge.intent(from: workout.intent)
        let observation = ObservationBridge.observation(from: primitives, intent: intent)
        return WorkoutEvaluationPolicyFactory.make(for: intent).evaluate(observation)
    }
}

enum DualRunComparator {
    static func buildReport(
        workouts: [WorkoutInput],
        policy: AnalysisPolicy,
        mode: MigrationMode
    ) -> DualRunReport {
        let diffs = workouts.map { workout -> EvaluationDiff in
            let legacy = WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
                primaryIntentBaseline: workout.intent,
                legacy: WorkoutIntentAnalyzer.analyze(workout, policy: policy)
            )
            let shadow = ObservationPolicyShadowEvaluator.evaluate(workout: workout, policy: policy)
            let delta = shadow.goalFitScore - legacy.goalFitScore
            let tendencyChanged = legacy.trainingTendency != shadow.trainingTendency
            return EvaluationDiff(
                workoutID: workout.id,
                intent: workout.intent.rawValue,
                legacyGoalFitScore: legacy.goalFitScore,
                shadowGoalFitScore: shadow.goalFitScore,
                goalFitDelta: delta,
                legacyTendency: legacy.trainingTendency,
                shadowTendency: shadow.trainingTendency,
                tendencyChanged: tendencyChanged,
                reviewStatus: classifyDiff(goalFitDelta: delta, tendencyChanged: tendencyChanged)
            )
        }
        let reportStatus = classifyReportStatus(
            diffs: diffs,
            userFacingOverrideApplied: false
        )
        return DualRunReport(
            generatedAt: Date(),
            migrationMode: mode,
            totalWorkouts: workouts.count,
            schemaVersion: "1.0",
            userFacingOverrideApplied: false,
            reviewStatus: reportStatus,
            diffs: diffs
        )
    }

    static func classifyDiff(goalFitDelta: Int, tendencyChanged: Bool) -> DualRunReviewStatus {
        if tendencyChanged { return .reviewRequired }
        let magnitude = abs(goalFitDelta)
        if magnitude <= 5 { return .minorDrift }
        if magnitude <= 15 { return .reviewRequired }
        return .blockingDrift
    }

    static func classifyReportStatus(
        diffs: [EvaluationDiff],
        userFacingOverrideApplied: Bool
    ) -> DualRunReviewStatus {
        if userFacingOverrideApplied { return .invalidReport }
        if diffs.contains(where: { $0.reviewStatus == .blockingDrift }) { return .blockingDrift }
        if diffs.contains(where: { $0.reviewStatus == .reviewRequired }) { return .reviewRequired }
        return .minorDrift
    }

    static func writeReport(
        _ report: DualRunReport,
        projectRoot: URL,
        fileManager: FileManager = .default
    ) {
        let dir = projectRoot
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("migration", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let ts = formatter.string(from: report.generatedAt).replacingOccurrences(of: ":", with: "-")
            let fileURL = dir.appendingPathComponent("dual_run_\(ts).json", isDirectory: false)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: fileURL)
        } catch {
            // Non-fatal: report emission should not break app flow.
        }
    }
}
