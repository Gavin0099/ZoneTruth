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
        switch workout.intent {
        case .zone2:
            let obs = Zone2ObservationAnalyzer.analyze(workout: workout, policy: policy)
            let score: Int = {
                let zone3 = obs.zoneDistribution.ratio(for: .zone3)
                if obs.sampleQuality != .sufficient { return 35 }
                if zone3 >= 0.20 { return 45 }
                if zone3 >= 0.10 { return 58 }
                return 82
            }()
            let tendency: String = {
                let zone3 = obs.zoneDistribution.ratio(for: .zone3)
                if zone3 >= 0.20 { return "偏混合有氧訓練" }
                if zone3 >= 0.10 { return "偏 Zone 2 但強度略高" }
                return "偏穩定有氧訓練"
            }()
            return makeEvaluation(intent: .zone2, tendency: tendency, score: score, sampleQuality: obs.sampleQuality)

        case .vo2Interval:
            let obs = VO2ObservationAnalyzer.analyze(workout: workout, policy: policy)
            let score: Int = {
                if obs.sampleQuality != .sufficient { return 40 }
                if obs.highIntensityRatio > 0.10 { return 84 }
                if obs.highIntensityRatio >= 0.05 { return 63 }
                return 45
            }()
            let tendency: String = {
                if obs.highIntensityRatio > 0.10 { return "偏高強度間歇訓練" }
                if obs.highIntensityRatio >= 0.05 { return "偏中高強度有氧訓練" }
                return "偏穩態有氧訓練"
            }()
            return makeEvaluation(intent: .vo2Max, tendency: tendency, score: score, sampleQuality: obs.sampleQuality)

        case .strength:
            let obs = StrengthObservationAnalyzer.analyze(workout: workout, policy: policy)
            let score: Int = {
                if obs.sampleQuality != .sufficient { return 40 }
                if obs.highHrSustainedRatio > 0.50 { return 48 }
                return 76
            }()
            let tendency = obs.highHrSustainedRatio > 0.50 ? "偏代謝循環訓練" : "偏傳統肌力訓練"
            return makeEvaluation(intent: .strength, tendency: tendency, score: score, sampleQuality: obs.sampleQuality)

        case .activityReview:
            let obs = ActivityObservationAnalyzer.analyze(workout: workout, policy: policy)
            return makeEvaluation(intent: .activity, tendency: "偏一般活動訓練", score: 72, sampleQuality: obs.sampleQuality)
        }
    }

    private static func makeEvaluation(
        intent: PrimaryIntent,
        tendency: String,
        score: Int,
        sampleQuality: SampleQuality
    ) -> WorkoutEvaluation {
        let confidence = sampleQuality == .sufficient ? 75 : 55
        return WorkoutEvaluation(
            primaryIntent: intent,
            trainingTendency: tendency,
            goalFitScore: score,
            classificationConfidence: confidence,
            evaluationConfidence: confidence,
            keyFindings: [],
            nextAction: "",
            secondarySignals: [],
            legacyPassFail: score >= 70
        )
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
