import Foundation
import ZoneTruthCore

struct AppEnvironment {
    let repository: WorkoutRepository

    static func live(fileManager: FileManager = .default) -> AppEnvironment {
        let healthKitRepository = HealthKitWorkoutRepository(
            store: SystemHealthKitWorkoutStore()
        )
        let importedRepository = JSONWorkoutRepository(
            fileURL: defaultImportURL(fileManager: fileManager),
            fileManager: fileManager
        )

        return AppEnvironment(
            repository: CompositeWorkoutRepository(
                repositories: [
                    healthKitRepository,
                    importedRepository,
                    MockWorkoutRepository(),
                ]
            )
        )
    }

    private static func defaultImportURL(fileManager: FileManager) -> URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("SampleData", isDirectory: true)
            .appendingPathComponent("workouts.json")
    }
}

struct CompositeWorkoutRepository: WorkoutRepository {
    let repositories: [WorkoutRepository]

    func loadWorkouts() -> [WorkoutInput] {
        for repository in repositories {
            let workouts = repository.loadWorkouts()
            if !workouts.isEmpty {
                return workouts
            }
        }

        return []
    }

    func refreshWorkouts() async -> [WorkoutInput] {
        for repository in repositories {
            let workouts = await repository.refreshWorkouts()
            if !workouts.isEmpty {
                return workouts
            }
        }

        return []
    }
}

struct JSONWorkoutRepository: WorkoutRepository {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadWorkouts() -> [WorkoutInput] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder.zoneTruth.decode(ImportedWorkoutPayload.self, from: data)
            return payload.workouts.map(\.toDomainWorkout)
        } catch {
            return []
        }
    }
}

private struct ImportedWorkoutPayload: Decodable {
    let workouts: [ImportedWorkoutRecord]
}

private struct ImportedWorkoutRecord: Decodable {
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    let intent: TrainingIntent
    let heartRateSamples: [ImportedHeartRateSample]

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples.map(\.toDomainSample),
            intent: intent
        )
    }
}

private struct ImportedHeartRateSample: Decodable {
    let timestamp: Date
    let bpm: Double

    var toDomainSample: HeartRateSample {
        HeartRateSample(timestamp: timestamp, bpm: bpm)
    }
}

private extension JSONDecoder {
    static var zoneTruth: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
