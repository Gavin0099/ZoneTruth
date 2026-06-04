import Foundation
import ZoneTruthCore

struct AppEnvironment {
    let repository: WorkoutRepository
    let intentOverrideStore: WorkoutIntentOverrideStore
    let stravaCallbackHandler: StravaCallbackHandler?
    let stravaAuthorizationURL: URL?
    let bodyCompositionLedger: BodyCompositionLedger?

    static func live(fileManager: FileManager = .default) -> AppEnvironment {
        let sessionStore = FileStravaSessionStore(
            fileURL: defaultStravaSessionURL(fileManager: fileManager),
            fileManager: fileManager
        )
        let stravaConfig = StravaOAuthConfiguration.appDefault
        let healthKitRepository = HealthKitWorkoutRepository(
            store: SystemHealthKitWorkoutStore()
        )
        let stravaRepository = StravaActivityRepository(
            client: SystemStravaClient(
                sessionStore: sessionStore,
                configuration: stravaConfig
            )
        )
        let importedRepository = JSONWorkoutRepository(
            fileURL: defaultImportURL(fileManager: fileManager),
            fileManager: fileManager
        )
        let callbackHandler = stravaConfig.map {
            StravaCallbackHandler(configuration: $0, sessionStore: sessionStore)
        }

        let compositionRepo = BodyCompositionRepository(
            fileURL: bodyCompositionFileURL(fileManager: fileManager),
            fileManager: fileManager
        )
        let resolvedLedger = compositionRepo.loadLedger() ?? BodyCompositionRepository.defaultSeedLedger()

        return AppEnvironment(
            repository: CompositeWorkoutRepository(
                repositories: [
                    healthKitRepository,
                    stravaRepository,
                    importedRepository,
                    MockWorkoutRepository(),
                ]
            ),
            intentOverrideStore: FileWorkoutIntentOverrideStore(
                fileURL: documentsDirectory(fileManager: fileManager)
                    .appendingPathComponent("intent-overrides.json"),
                fileManager: fileManager
            ),
            stravaCallbackHandler: callbackHandler,
            stravaAuthorizationURL: stravaConfig?.mobileAuthorizationURL,
            bodyCompositionLedger: resolvedLedger
        )
    }

    private static func defaultImportURL(fileManager: FileManager) -> URL {
        documentsDirectory(fileManager: fileManager)
            .appendingPathComponent("workouts.json")
    }

    private static func defaultStravaSessionURL(fileManager: FileManager) -> URL {
        documentsDirectory(fileManager: fileManager)
            .appendingPathComponent("strava-session.json")
    }

    private static func documentsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
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

    private func deduplicate(_ workouts: [WorkoutInput]) -> [WorkoutInput] {
        var result: [WorkoutInput] = []
        for workout in workouts {
            if let idx = result.firstIndex(where: {
                $0.workoutType == workout.workoutType &&
                abs($0.startDate.timeIntervalSince(workout.startDate)) < 300
            }) {
                if workout.heartRateSamples.count > result[idx].heartRateSamples.count {
                    result[idx] = workout
                }
            } else {
                result.append(workout)
            }
        }
        return result
    }

    func requestHealthAccess() async -> WorkoutLoadResult {
        for repository in repositories where repository.supportsHealthAuthorization {
            _ = await repository.requestHealthAccess()
            break
        }
        return await refreshResult()
    }

    private func resolve(results: [WorkoutLoadResult]) -> WorkoutLoadResult {
        var realResults: [WorkoutLoadResult] = []
        var mockResult: WorkoutLoadResult?

        for result in results {
            if result.source == .mockSamples {
                if mockResult == nil { mockResult = result }
            } else if !result.workouts.isEmpty {
                realResults.append(result)
            }
        }

        guard !realResults.isEmpty else {
            return mockResult ?? WorkoutLoadResult(workouts: [], source: .none, statusMessage: "尚未連接任何資料來源。")
        }

        let merged = deduplicate(
            realResults
                .flatMap(\.workouts)
                .sorted { $0.startDate > $1.startDate }
        ).prefix(100)

        let activeSources = realResults.map(\.source)
        let source: WorkoutDataSource
        let label: String
        if activeSources.contains(.healthKit) && activeSources.contains(.strava) {
            source = .combined
            label = "Apple Health + Strava"  // 品牌名稱保留英文
        } else {
            source = activeSources[0]
            label = activeSources[0].rawValue
        }

        let statusMsg = "\(label)：共 \(merged.count) 筆活動"

        return WorkoutLoadResult(
            workouts: Array(merged),
            source: source,
            statusMessage: statusMsg
        )
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
                statusMessage: "找不到 JSON 匯入檔（Documents/workouts.json）。"
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder.zoneTruth.decode(ImportedWorkoutPayload.self, from: data)
            return WorkoutLoadResult(
                workouts: payload.workouts.map(\.toDomainWorkout),
                source: .jsonImport,
                statusMessage: "已從 JSON 檔案載入訓練紀錄。"
            )
        } catch {
            return WorkoutLoadResult(
                workouts: [],
                source: .jsonImport,
                statusMessage: "JSON 格式無法解析，已略過此來源。"
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
    let intent: TrainingIntent?
    let intentSource: IntentSource?
    let heartRateSamples: [ImportedHeartRateSample]
    let vo2MaxEstimate: VO2MaxEstimate?

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples.map(\.toDomainSample),
            intent: intent,
            intentSource: intentSource,
            vo2MaxEstimate: vo2MaxEstimate
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
