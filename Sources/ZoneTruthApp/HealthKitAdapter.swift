import Foundation
import ZoneTruthCore

#if canImport(HealthKit)
import HealthKit
#endif

enum HealthAuthorizationStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case sharingDenied
    case sharingAuthorized
}

enum HealthKitStoreError: Error, Equatable, Sendable {
    case unavailable
    case unauthorized
    case queryNotSupported
}

struct HealthKitWorkoutSnapshot: Equatable, Sendable {
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    let heartRateSamples: [HeartRateSample]
    let hrvSDNNMilliseconds: Double?
    let defaultIntent: TrainingIntent

    init(
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        heartRateSamples: [HeartRateSample],
        hrvSDNNMilliseconds: Double? = nil,
        defaultIntent: TrainingIntent = .activityReview
    ) {
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.heartRateSamples = heartRateSamples
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.defaultIntent = defaultIntent
    }

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples,
            hrvSDNNMilliseconds: hrvSDNNMilliseconds,
            intent: defaultIntent,
            dataSource: "healthkit"
        )
    }
}

protocol HealthKitWorkoutStore {
    var isAvailable: Bool { get }
    var authorizationStatus: HealthAuthorizationStatus { get }

    func requestAuthorization() async -> HealthAuthorizationStatus
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkoutSnapshot]
}

final class HealthKitWorkoutRepository: WorkoutRepository {
    let store: HealthKitWorkoutStore
    private let workoutLimit: Int
    private var cachedWorkouts: [WorkoutInput]

    init(
        store: HealthKitWorkoutStore,
        workoutLimit: Int = 30,
        cachedWorkouts: [WorkoutInput] = []
    ) {
        self.store = store
        self.workoutLimit = workoutLimit
        self.cachedWorkouts = cachedWorkouts
    }

    var supportsHealthAuthorization: Bool {
        store.isAvailable
    }

    func loadResult() -> WorkoutLoadResult {
        WorkoutLoadResult(
            workouts: cachedWorkouts,
            source: cachedWorkouts.isEmpty ? .healthKit : .healthKit,
            statusMessage: statusMessage(for: store.authorizationStatus, workoutCount: cachedWorkouts.count)
        )
    }

    func requestAuthorizationIfNeeded() async -> HealthAuthorizationStatus {
        guard store.isAvailable else { return .unavailable }
        let currentStatus = store.authorizationStatus
        guard currentStatus == .notDetermined else { return currentStatus }
        return await store.requestAuthorization()
    }

    func requestHealthAccess() async -> WorkoutLoadResult {
        _ = await requestAuthorizationIfNeeded()

        do {
            cachedWorkouts = try await store.fetchRecentWorkouts(limit: workoutLimit).map(\.toDomainWorkout)
            return WorkoutLoadResult(
                workouts: cachedWorkouts,
                source: .healthKit,
                statusMessage: cachedWorkouts.isEmpty ? "Apple Health 已授權，但找不到近期的運動紀錄。" : "已從 Apple Health 載入運動紀錄。"
            )
        } catch {
            cachedWorkouts = []
            return WorkoutLoadResult(
                workouts: [],
                source: .healthKit,
                statusMessage: "Apple Health 授權成功，但無法載入運動資料。"
            )
        }
    }

    func refreshResult() async -> WorkoutLoadResult {
        guard store.isAvailable else {
            cachedWorkouts = []
            return WorkoutLoadResult(
                workouts: [],
                source: .healthKit,
                statusMessage: "此裝置不支援 Apple Health。"
            )
        }

        do {
            cachedWorkouts = try await store.fetchRecentWorkouts(limit: workoutLimit).map(\.toDomainWorkout)
        } catch {
            cachedWorkouts = []
            return WorkoutLoadResult(
                workouts: [],
                source: .healthKit,
                statusMessage: "Apple Health 已授權，但無法載入運動資料。"
            )
        }

        return WorkoutLoadResult(
            workouts: cachedWorkouts,
            source: .healthKit,
            statusMessage: cachedWorkouts.isEmpty ? "尚未取得 Apple Health 授權，或找不到運動紀錄。" : "已從 Apple Health 載入運動紀錄。"
        )
    }

    private func statusMessage(for authorizationStatus: HealthAuthorizationStatus, workoutCount: Int) -> String {
        switch authorizationStatus {
        case .unavailable:
            return "此裝置不支援 Apple Health。"
        case .notDetermined:
            return "尚未取得 Apple Health 授權。"
        case .sharingDenied:
            return "Apple Health 存取被拒絕，將使用備用資料。"
        case .sharingAuthorized:
            return workoutCount > 0
                ? "已從 Apple Health 載入運動紀錄。"
                : "Apple Health 已授權，但找不到近期的運動紀錄。"
        }
    }
}

struct SystemHealthKitWorkoutStore: HealthKitWorkoutStore {
    var isAvailable: Bool {
        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            return HKHealthStore.isHealthDataAvailable()
        }
        return false
        #else
        return false
        #endif
    }

    var authorizationStatus: HealthAuthorizationStatus {
        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            let workoutType = HKObjectType.workoutType()

            guard isAvailable else {
                return .unavailable
            }

            switch store.authorizationStatus(for: workoutType) {
            case .notDetermined:
                return .notDetermined
            case .sharingDenied:
                return .sharingDenied
            case .sharingAuthorized:
                return .sharingAuthorized
            @unknown default:
                return .notDetermined
            }
        }
        return .unavailable
        #else
        return .unavailable
        #endif
    }

    func requestAuthorization() async -> HealthAuthorizationStatus {
        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            guard isAvailable else { return .unavailable }

            let store = HKHealthStore()
            guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                return .unavailable
            }
            let readTypes = Set([
                HKObjectType.workoutType(),
                heartRateType,
                HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            ].compactMap { $0 })

            do {
                try await store.requestAuthorization(toShare: [], read: readTypes)
            } catch {
                return authorizationStatus
            }

            return authorizationStatus
        }
        return .unavailable
        #else
        return .unavailable
        #endif
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkoutSnapshot] {
        guard isAvailable else { throw HealthKitStoreError.unavailable }

        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            let workouts = try await recentWorkouts(from: store, limit: limit)

            return try await workouts.asyncMap { workout in
                let heartRateSamples = try await heartRateSamples(for: workout, from: store)
                let hrvSDNNMilliseconds = try await averageHRVSDNN(for: workout, from: store)
                return HealthKitWorkoutSnapshot(
                    workoutType: domainWorkoutType(for: workout.workoutActivityType),
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    heartRateSamples: heartRateSamples,
                    hrvSDNNMilliseconds: hrvSDNNMilliseconds
                )
            }
        }
        throw HealthKitStoreError.unavailable
        #else
        _ = limit
        throw HealthKitStoreError.unavailable
        #endif
    }
}

#if canImport(HealthKit)
@available(iOS 17.0, macOS 14.0, *)
private func recentWorkouts(from store: HKHealthStore, limit: Int) async throws -> [HKWorkout] {
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: nil,
            limit: limit,
            sortDescriptors: sortDescriptors
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }

            continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
        }

        store.execute(query)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func heartRateSamples(for workout: HKWorkout, from store: HKHealthStore) async throws -> [HeartRateSample] {
    guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
        throw HealthKitStoreError.queryNotSupported
    }

    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: [.strictStartDate, .strictEndDate]
    )
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    let beatsPerMinuteUnit = HKUnit.count().unitDivided(by: HKUnit.minute())

    let quantitySamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: sortDescriptors
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }

            continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
        }

        store.execute(query)
    }

    return quantitySamples.map { sample in
        HeartRateSample(
            timestamp: sample.startDate,
            bpm: sample.quantity.doubleValue(for: beatsPerMinuteUnit)
        )
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func averageHRVSDNN(for workout: HKWorkout, from store: HKHealthStore) async throws -> Double? {
    guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
        return nil
    }

    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: [.strictStartDate, .strictEndDate]
    )
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    let unit = HKUnit.secondUnit(with: .milli)

    let quantitySamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: sortDescriptors
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }

            continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
        }

        store.execute(query)
    }

    guard !quantitySamples.isEmpty else {
        return nil
    }

    let sum = quantitySamples.reduce(0.0) { partial, sample in
        partial + sample.quantity.doubleValue(for: unit)
    }
    return sum / Double(quantitySamples.count)
}

@available(iOS 17.0, macOS 14.0, *)
private func domainWorkoutType(for activityType: HKWorkoutActivityType) -> WorkoutType {
    switch activityType {
    case .running:
        return .running
    case .cycling:
        return .cycling
    case .swimming:
        return .swimming
    case .walking, .hiking:
        return .walking
    case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
        return .strengthTraining
    case .mixedCardio, .highIntensityIntervalTraining, .kickboxing, .martialArts:
        return .mixed
    default:
        return .other
    }
}
#endif

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
