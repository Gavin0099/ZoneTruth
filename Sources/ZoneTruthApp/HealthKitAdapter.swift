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
    case queryNotImplemented
}

struct HealthKitWorkoutSnapshot: Equatable, Sendable {
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    let heartRateSamples: [HeartRateSample]
    let defaultIntent: TrainingIntent

    init(
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        heartRateSamples: [HeartRateSample],
        defaultIntent: TrainingIntent = .activityReview
    ) {
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.heartRateSamples = heartRateSamples
        self.defaultIntent = defaultIntent
    }

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples,
            intent: defaultIntent
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

    func loadWorkouts() -> [WorkoutInput] {
        cachedWorkouts
    }

    func requestAuthorizationIfNeeded() async -> HealthAuthorizationStatus {
        guard store.isAvailable else { return .unavailable }
        let currentStatus = store.authorizationStatus
        guard currentStatus == .notDetermined else { return currentStatus }
        return await store.requestAuthorization()
    }

    func refreshWorkouts() async -> [WorkoutInput] {
        guard store.isAvailable else {
            cachedWorkouts = []
            return []
        }

        let authorizationStatus = store.authorizationStatus
        guard authorizationStatus == .sharingAuthorized else {
            cachedWorkouts = []
            return []
        }

        do {
            cachedWorkouts = try await store.fetchRecentWorkouts(limit: workoutLimit).map(\.toDomainWorkout)
        } catch {
            cachedWorkouts = []
        }

        return cachedWorkouts
    }
}

struct SystemHealthKitWorkoutStore: HealthKitWorkoutStore {
    var isAvailable: Bool {
        #if canImport(HealthKit)
        if #available(iOS 17.0, *) {
            return HKHealthStore.isHealthDataAvailable()
        }
        return false
        #else
        return false
        #endif
    }

    var authorizationStatus: HealthAuthorizationStatus {
        #if canImport(HealthKit)
        if #available(iOS 17.0, *) {
            let store = HKHealthStore()
            guard let workoutType = HKObjectType.workoutType() as HKObjectType? else {
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
        if #available(iOS 17.0, *) {
            guard isAvailable else { return .unavailable }

            let store = HKHealthStore()
            let readTypes: Set<HKObjectType> = [
                HKObjectType.workoutType(),
                HKQuantityType(.heartRate),
            ]

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
        guard authorizationStatus == .sharingAuthorized else { throw HealthKitStoreError.unauthorized }

        // Real HK queries live here later. Keeping the adapter boundary in place now
        // prevents domain logic from depending on HealthKit types.
        _ = limit
        throw HealthKitStoreError.queryNotImplemented
    }
}
