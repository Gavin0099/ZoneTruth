import Foundation
import ZoneTruthCore

enum WorkoutDataSource: String, Equatable, Sendable {
    case healthKit = "Apple Health"
    case strava = "Strava"
    case jsonImport = "匯入的 JSON"
    case mockSamples = "預覽樣本"
    case none = "沒有資料"
}

struct WorkoutLoadResult: Equatable, Sendable {
    let workouts: [WorkoutInput]
    let source: WorkoutDataSource
    let statusMessage: String?

    init(
        workouts: [WorkoutInput],
        source: WorkoutDataSource,
        statusMessage: String? = nil
    ) {
        self.workouts = workouts
        self.source = source
        self.statusMessage = statusMessage
    }
}

@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published var workouts: [WorkoutInput] = []
    @Published var selectedWorkout: WorkoutInput?
    @Published var selectedIntent: TrainingIntent = .zone2
    @Published var isRefreshing = false
    @Published var isRequestingAuthorization = false
    @Published private(set) var currentSource: WorkoutDataSource = .none
    @Published private(set) var statusMessage: String?

    let stravaAuthorizationURL: URL?
    private let repository: WorkoutRepository
    private let settingsManager: SettingsManager

    init(repository: WorkoutRepository, settingsManager: SettingsManager, stravaAuthorizationURL: URL? = nil) {
        self.repository = repository
        self.settingsManager = settingsManager
        self.stravaAuthorizationURL = stravaAuthorizationURL
        apply(repository.loadResult())
    }

    var canConnectStrava: Bool {
        stravaAuthorizationURL != nil && currentSource != .strava
    }

    func selectWorkout(_ workout: WorkoutInput) {
        selectedWorkout = workout
        selectedIntent = workout.intent
    }

    func updateIntent(_ intent: TrainingIntent) {
        selectedIntent = intent
    }

    func refreshWorkouts() async {
        isRefreshing = true
        let refreshed = await repository.refreshResult()
        apply(refreshed)
        isRefreshing = false
        triggerCalibrationCheck()
        emitMigrationReportIfNeeded()
    }

    func requestHealthAccess() async {
        guard repository.supportsHealthAuthorization else { return }
        isRequestingAuthorization = true
        let result = await repository.requestHealthAccess()
        apply(result)
        isRequestingAuthorization = false
    }

    func analysisResult(for workout: WorkoutInput) -> AnalysisResult {
        let rewritten = WorkoutInput(
            id: workout.id,
            workoutType: workout.workoutType,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.durationSeconds,
            heartRateSamples: workout.heartRateSamples,
            intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent
        )
        return WorkoutIntentAnalyzer.analyze(rewritten, policy: settingsManager.policy)
    }

    func evaluationResult(for workout: WorkoutInput) -> WorkoutEvaluation {
        let rewritten = WorkoutInput(
            id: workout.id,
            workoutType: workout.workoutType,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.durationSeconds,
            heartRateSamples: workout.heartRateSamples,
            intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent
        )
        let legacy = WorkoutIntentAnalyzer.analyze(rewritten, policy: settingsManager.policy)
        return WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: rewritten.intent,
            legacy: legacy
        )
    }

    private func apply(_ result: WorkoutLoadResult) {
        workouts = result.workouts
        currentSource = result.source
        statusMessage = result.statusMessage
        selectedWorkout = result.workouts.first
        if let intent = result.workouts.first?.intent {
            selectedIntent = intent
        }
        triggerCalibrationCheck()
    }

    private func triggerCalibrationCheck() {
        let analyses = workouts.map { ($0, analysisResult(for: $0)) }
        settingsManager.updateCalibrationSuggestion(analyses: analyses)
    }

    private func emitMigrationReportIfNeeded() {
        guard settingsManager.migrationMode == .dualRun else { return }
        let report = DualRunComparator.buildReport(
            workouts: workouts.map { workout in
                WorkoutInput(
                    id: workout.id,
                    workoutType: workout.workoutType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationSeconds: workout.durationSeconds,
                    heartRateSamples: workout.heartRateSamples,
                    intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent
                )
            },
            policy: settingsManager.policy,
            mode: settingsManager.migrationMode
        )
        DualRunComparator.writeReport(
            report,
            projectRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
    }

    var canRequestHealthAccess: Bool {
        repository.supportsHealthAuthorization && currentSource != .healthKit
    }
}

protocol WorkoutRepository {
    func loadResult() -> WorkoutLoadResult
    func refreshResult() async -> WorkoutLoadResult
    var supportsHealthAuthorization: Bool { get }
    func requestHealthAccess() async -> WorkoutLoadResult
}

extension WorkoutRepository {
    var supportsHealthAuthorization: Bool { false }

    func loadWorkouts() -> [WorkoutInput] {
        loadResult().workouts
    }

    func refreshWorkouts() async -> [WorkoutInput] {
        await refreshResult().workouts
    }

    func refreshResult() async -> WorkoutLoadResult {
        loadResult()
    }

    func requestHealthAccess() async -> WorkoutLoadResult {
        await refreshResult()
    }
}

struct MockWorkoutRepository: WorkoutRepository {
    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(
            workouts: SampleWorkoutCases.previewWorkouts(),
            source: .mockSamples,
            statusMessage: "在連接 Apple Health 或匯入資料之前，暫時顯示預覽樣本。"
        )
    }
}
