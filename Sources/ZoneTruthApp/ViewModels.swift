import Foundation
import ZoneTruthCore

@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published var workouts: [WorkoutInput] = []
    @Published var selectedWorkout: WorkoutInput?
    @Published var selectedIntent: TrainingIntent = .zone2

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
}

struct MockWorkoutRepository: WorkoutRepository {
    func loadWorkouts() -> [WorkoutInput] {
        let base = Date(timeIntervalSince1970: 1_713_916_800)

        return [
            WorkoutInput(
                workoutType: .swimming,
                startDate: base,
                endDate: base.addingTimeInterval(45 * 60),
                heartRateSamples: makeSamples(
                    start: base,
                    values: [112, 114, 116, 117, 118, 119, 120, 121, 122, 123, 124, 126, 127, 128, 129, 130, 130, 131, 132, 132, 133, 134, 134, 135]
                ),
                intent: .zone2
            ),
            WorkoutInput(
                workoutType: .walking,
                startDate: base.addingTimeInterval(86_400),
                endDate: base.addingTimeInterval(86_400 + 28 * 60),
                heartRateSamples: makeSamples(
                    start: base.addingTimeInterval(86_400),
                    values: [88, 92, 96, 99, 101, 103, 106, 104, 102, 100, 98, 97, 96, 98, 100, 102, 103, 101, 99, 98, 97, 96, 95, 94]
                ),
                intent: .activityReview
            ),
        ]
    }

    private func makeSamples(start: Date, values: [Double]) -> [HeartRateSample] {
        values.enumerated().map { index, bpm in
            HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(index * 60)), bpm: bpm)
        }
    }
}
