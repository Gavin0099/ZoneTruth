import Foundation
import ZoneTruthCore

enum WorkoutDataSource: String, Equatable, Sendable {
    case healthKit = "Apple Health"
    case jsonImport = "Imported JSON"
    case mockSamples = "Preview Samples"
    case none = "No Data"
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
    @Published private(set) var currentSource: WorkoutDataSource = .none
    @Published private(set) var statusMessage: String?

    private let repository: WorkoutRepository

    init(repository: WorkoutRepository) {
        self.repository = repository
        apply(repository.loadResult())
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
        return WorkoutIntentAnalyzer.analyze(rewritten)
    }

    private func apply(_ result: WorkoutLoadResult) {
        workouts = result.workouts
        currentSource = result.source
        statusMessage = result.statusMessage
        selectedWorkout = result.workouts.first
        if let intent = result.workouts.first?.intent {
            selectedIntent = intent
        }
    }
}

protocol WorkoutRepository {
    func loadResult() -> WorkoutLoadResult
    func refreshResult() async -> WorkoutLoadResult
}

extension WorkoutRepository {
    func loadWorkouts() -> [WorkoutInput] {
        loadResult().workouts
    }

    func refreshWorkouts() async -> [WorkoutInput] {
        await refreshResult().workouts
    }

    func refreshResult() async -> WorkoutLoadResult {
        loadResult()
    }
}

struct MockWorkoutRepository: WorkoutRepository {
    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(
            workouts: SampleWorkoutCases.previewWorkouts(),
            source: .mockSamples,
            statusMessage: "Showing preview samples until imported or Apple Health data is available."
        )
    }
}
