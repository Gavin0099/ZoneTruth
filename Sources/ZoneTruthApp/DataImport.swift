import Foundation
import ZoneTruthCore

struct AppEnvironment {
    let repository: WorkoutRepository
    let stravaCallbackHandler: StravaCallbackHandler?

    static func live(fileManager: FileManager = .default) -> AppEnvironment {
        let sessionStore = FileStravaSessionStore(
            fileURL: defaultStravaSessionURL(fileManager: fileManager),
            fileManager: fileManager
        )
        let healthKitRepository = HealthKitWorkoutRepository(
            store: SystemHealthKitWorkoutStore()
        )
        let stravaRepository = StravaActivityRepository(
            client: SystemStravaClient(sessionStore: sessionStore)
        )
        let importedRepository = JSONWorkoutRepository(
            fileURL: defaultImportURL(fileManager: fileManager),
            fileManager: fileManager
        )
        let callbackHandler = StravaOAuthConfiguration.appDefault.map {
            StravaCallbackHandler(configuration: $0, sessionStore: sessionStore)
        }

        return AppEnvironment(
            repository: CompositeWorkoutRepository(
                repositories: [
                    healthKitRepository,
                    stravaRepository,
                    importedRepository,
                    MockWorkoutRepository(),
                ]
            ),
            stravaCallbackHandler: callbackHandler
        )
    }

    private static func defaultImportURL(fileManager: FileManager) -> URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("SampleData", isDirectory: true)
            .appendingPathComponent("workouts.json")
    }

    private static func defaultStravaSessionURL(fileManager: FileManager) -> URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("SampleData", isDirectory: true)
            .appendingPathComponent("strava-session.json")
    }
}

struct CompositeWorkoutRepository: WorkoutRepository {
    let repositories: [WorkoutRepository]

    var supportsHealthAuthorization: Bool {
        repositories.contains { $0.supportsHealthAuthorization }
    }

    func loadResult() -> WorkoutLoadResult {
        resolve(results: repositories.map { $0.loadResult() })
    }

    func refreshResult() async -> WorkoutLoadResult {
        var results: [WorkoutLoadResult] = []
        for repository in repositories {
            results.append(await repository.refreshResult())
        }
        return resolve(results: results)
    }

    func requestHealthAccess() async -> WorkoutLoadResult {
        for repository in repositories where repository.supportsHealthAuthorization {
            let result = await repository.requestHealthAccess()
            if !result.workouts.isEmpty || result.source == .healthKit {
                return result
            }
            break
        }

        return await refreshResult()
    }

    private func resolve(results: [WorkoutLoadResult]) -> WorkoutLoadResult {
        var notices: [String] = []

        for result in results {
            if let statusMessage = result.statusMessage {
                notices.append(statusMessage)
            }

            if !result.workouts.isEmpty {
                return WorkoutLoadResult(
                    workouts: result.workouts,
                    source: result.source,
                    statusMessage: mergedMessage(for: result, notices: notices)
                )
            }
        }

        return WorkoutLoadResult(
            workouts: [],
            source: .none,
            statusMessage: notices.isEmpty ? "No workouts are available yet." : notices.joined(separator: " ")
        )
    }

    private func mergedMessage(for result: WorkoutLoadResult, notices: [String]) -> String? {
        let unique = notices.reduce(into: [String]()) { partial, item in
            if !partial.contains(item) {
                partial.append(item)
            }
        }

        guard !unique.isEmpty else { return result.statusMessage }
        guard result.source != .healthKit else { return result.statusMessage ?? unique.first }
        return unique.joined(separator: " ")
    }
}

struct JSONWorkoutRepository: WorkoutRepository {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadResult() -> WorkoutLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return WorkoutLoadResult(
                workouts: [],
                source: .jsonImport,
                statusMessage: "No imported JSON file was found at SampleData/workouts.json."
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder.zoneTruth.decode(ImportedWorkoutPayload.self, from: data)
            return WorkoutLoadResult(
                workouts: payload.workouts.map(\.toDomainWorkout),
                source: .jsonImport,
                statusMessage: "Loaded workouts from SampleData/workouts.json."
            )
        } catch {
            return WorkoutLoadResult(
                workouts: [],
                source: .jsonImport,
                statusMessage: "Imported JSON could not be parsed, so this source was skipped."
            )
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

extension JSONDecoder {
    static var zoneTruth: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
