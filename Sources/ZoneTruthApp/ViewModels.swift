import Foundation
import ZoneTruthCore

@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published var workouts: [WorkoutInput] = []
    @Published var selectedWorkout: WorkoutInput?
    @Published var selectedIntent: TrainingIntent = .zone2
    @Published var isRefreshing = false

    private let repository: WorkoutRepository

    init(repository: WorkoutRepository) {
        self.repository = repository
        self.workouts = repository.loadWorkouts()
        self.selectedWorkout = workouts.first
        if let intent = workouts.first?.intent {
            self.selectedIntent = intent
        }
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
        let refreshed = await repository.refreshWorkouts()
        workouts = refreshed
        selectedWorkout = refreshed.first
        if let intent = refreshed.first?.intent {
            selectedIntent = intent
        }
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
}

protocol WorkoutRepository {
    func loadWorkouts() -> [WorkoutInput]
    func refreshWorkouts() async -> [WorkoutInput]
}

extension WorkoutRepository {
    func refreshWorkouts() async -> [WorkoutInput] {
        loadWorkouts()
    }
}

struct MockWorkoutRepository: WorkoutRepository {
    func loadWorkouts() -> [WorkoutInput] {
        SampleWorkoutCases.previewWorkouts()
    }
}
