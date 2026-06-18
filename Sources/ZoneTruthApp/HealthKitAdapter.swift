import Foundation
import ZoneTruthCore

#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreLocation)
import CoreLocation
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
    let vo2MaxEstimate: VO2MaxEstimate?
    let heartRateRecoveryOneMinute: HeartRateRecoveryObservation?
    let runningPower: RunningPowerObservation?
    let cyclingPower: CyclingPowerObservation?
    let workoutRoute: WorkoutRouteObservation?
    let externalLoadDecoupling: ExternalLoadDecouplingObservation?
    let debugSignalSnapshot: HealthKitWorkoutDebugSignalSnapshot?
    let defaultIntent: TrainingIntent
    let activeCaloriesKcal: Double?
    let totalDistanceMeters: Double?

    init(
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date,
        heartRateSamples: [HeartRateSample],
        hrvSDNNMilliseconds: Double? = nil,
        vo2MaxEstimate: VO2MaxEstimate? = nil,
        heartRateRecoveryOneMinute: HeartRateRecoveryObservation? = nil,
        runningPower: RunningPowerObservation? = nil,
        cyclingPower: CyclingPowerObservation? = nil,
        workoutRoute: WorkoutRouteObservation? = nil,
        externalLoadDecoupling: ExternalLoadDecouplingObservation? = nil,
        debugSignalSnapshot: HealthKitWorkoutDebugSignalSnapshot? = nil,
        defaultIntent: TrainingIntent? = nil,
        activeCaloriesKcal: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.heartRateSamples = heartRateSamples
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.vo2MaxEstimate = vo2MaxEstimate
        self.heartRateRecoveryOneMinute = heartRateRecoveryOneMinute
        self.runningPower = runningPower
        self.cyclingPower = cyclingPower
        self.workoutRoute = workoutRoute
        self.externalLoadDecoupling = externalLoadDecoupling
        self.debugSignalSnapshot = debugSignalSnapshot
        self.defaultIntent = defaultIntent ?? WorkoutInput.defaultIntent(for: workoutType)
        self.activeCaloriesKcal = activeCaloriesKcal
        self.totalDistanceMeters = totalDistanceMeters
    }

    var toDomainWorkout: WorkoutInput {
        WorkoutInput(
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            heartRateSamples: heartRateSamples,
            hrvSDNNMilliseconds: hrvSDNNMilliseconds,
            intent: defaultIntent,
            intentSource: .auto,
            dataSource: "healthkit",
            activeCaloriesKcal: activeCaloriesKcal,
            totalDistanceMeters: totalDistanceMeters,
            vo2MaxEstimate: vo2MaxEstimate,
            heartRateRecoveryOneMinute: heartRateRecoveryOneMinute,
            runningPower: runningPower,
            cyclingPower: cyclingPower,
            workoutRoute: workoutRoute,
            externalLoadDecoupling: externalLoadDecoupling
        )
    }
}

struct HealthKitWorkoutDebugSignalSnapshot: Equatable, Sendable {
    let recoveryCandidateCount: Int
}

struct TimedPowerSample: Equatable, Sendable {
    let timestamp: Date
    let watts: Double
}

protocol HealthKitWorkoutStore {
    var isAvailable: Bool { get }
    var authorizationStatus: HealthAuthorizationStatus { get }

    func requestAuthorization() async -> HealthAuthorizationStatus
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkoutSnapshot]
    func fetchRecentSleepContext(days: Int) async throws -> HealthKitSleepContextQueryResult
    func fetchRestingHeartRateBaseline() async throws -> Double?
    func debugAuthorizationDetails() async -> HealthKitAuthorizationDebugDetails?
    func debugGlobalRecoveryProbe(limit: Int) async -> HealthKitRecoveryProbeSummary?
}

struct HealthKitSleepContextQueryResult: Equatable, Sendable {
    let context: WeeklySleepContext?
    let lookbackDays: Int
    let rawSampleCount: Int
    let asleepSampleCount: Int

    init(
        context: WeeklySleepContext?,
        lookbackDays: Int,
        rawSampleCount: Int,
        asleepSampleCount: Int
    ) {
        self.context = context
        self.lookbackDays = lookbackDays
        self.rawSampleCount = rawSampleCount
        self.asleepSampleCount = asleepSampleCount
    }
}

struct HealthKitSleepInterval: Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }
}

final class WorkoutRouteQueryBatchCollector<Location>: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [Location] = []
    private var isFinished = false

    func record(
        locations locationsOrNil: [Location]?,
        done: Bool,
        error: Error?
    ) -> Result<[Location], Error>? {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else { return nil }

        if let error {
            isFinished = true
            return .failure(error)
        }

        if let locationsOrNil {
            locations.append(contentsOf: locationsOrNil)
        }

        if done {
            isFinished = true
            return .success(locations)
        }

        return nil
    }
}

func aggregateWeeklySleepContext(
    from intervals: [HealthKitSleepInterval],
    lookbackDays: Int,
    startDate: Date,
    now: Date,
    source: TrainingMetricMethodSource = .apple,
    sourceLabel: String? = "Apple Health sleep analysis"
) -> WeeklySleepContext? {
    let clippedSegments = intervals
        .compactMap { interval -> HealthKitSleepInterval? in
            let clippedStart = max(interval.startDate, startDate)
            let clippedEnd = min(interval.endDate, now)
            guard clippedEnd.timeIntervalSince(clippedStart) > 0 else { return nil }
            return HealthKitSleepInterval(startDate: clippedStart, endDate: clippedEnd)
        }
        .sorted { $0.startDate < $1.startDate }

    guard !clippedSegments.isEmpty else { return nil }

    let normalizedSegments = clippedSegments.reduce(into: [HealthKitSleepInterval]()) { result, segment in
        guard let last = result.last else {
            result.append(segment)
            return
        }
        if segment.startDate <= last.endDate {
            result[result.index(before: result.endIndex)] = HealthKitSleepInterval(
                startDate: last.startDate,
                endDate: max(last.endDate, segment.endDate)
            )
        } else {
            result.append(segment)
        }
    }

    struct SleepEpisode {
        var endDate: Date
        var sleepSeconds: TimeInterval
    }

    let maxEpisodeGap: TimeInterval = 2 * 60 * 60
    let minimumNightDuration: TimeInterval = 2 * 60 * 60
    let episodes = normalizedSegments.reduce(into: [SleepEpisode]()) { result, segment in
        let duration = segment.endDate.timeIntervalSince(segment.startDate)
        guard duration > 0 else { return }

        guard let last = result.last else {
            result.append(SleepEpisode(endDate: segment.endDate, sleepSeconds: duration))
            return
        }

        let gap = segment.startDate.timeIntervalSince(last.endDate)
        if gap <= maxEpisodeGap {
            result[result.index(before: result.endIndex)] = SleepEpisode(
                endDate: max(last.endDate, segment.endDate),
                sleepSeconds: last.sleepSeconds + duration
            )
        } else {
            result.append(SleepEpisode(endDate: segment.endDate, sleepSeconds: duration))
        }
    }
    let nightEpisodes = episodes.filter { $0.sleepSeconds >= minimumNightDuration }

    guard !nightEpisodes.isEmpty else { return nil }

    let totalSleepHours = nightEpisodes.map(\.sleepSeconds).reduce(0, +) / 3_600
    return WeeklySleepContext(
        lookbackDays: max(1, lookbackDays),
        nightsWithSleep: nightEpisodes.count,
        averageSleepHours: totalSleepHours / Double(nightEpisodes.count),
        source: source,
        sourceLabel: sourceLabel
    )
}

final class HealthKitWorkoutRepository: WorkoutRepository {
    let store: HealthKitWorkoutStore
    private let workoutLimit: Int
    private var cachedWorkouts: [WorkoutInput]
    private var cachedSleepContext: WeeklySleepContext?
    private let debugLogger: @Sendable (String) -> Void

    init(
        store: HealthKitWorkoutStore,
        workoutLimit: Int = 30,
        cachedWorkouts: [WorkoutInput] = [],
        debugLogger: @escaping @Sendable (String) -> Void = healthKitDebugLogger
    ) {
        self.store = store
        self.workoutLimit = workoutLimit
        self.cachedWorkouts = cachedWorkouts
        self.cachedSleepContext = nil
        self.debugLogger = debugLogger
    }

    var supportsHealthAuthorization: Bool {
        store.isAvailable
    }

    func loadResult() -> WorkoutLoadResult {
        let authorizationStatus = effectiveAuthorizationStatus(
            rawStatus: store.authorizationStatus,
            workouts: cachedWorkouts
        )
        return WorkoutLoadResult(
            workouts: cachedWorkouts,
            source: cachedWorkouts.isEmpty ? .healthKit : .healthKit,
            statusMessage: statusMessage(for: authorizationStatus, workoutCount: cachedWorkouts.count),
            sleepContext: cachedSleepContext
        )
    }

    func requestAuthorizationIfNeeded() async -> HealthAuthorizationStatus {
        guard store.isAvailable else { return .unavailable }
        let currentStatus = store.authorizationStatus
        guard currentStatus == .notDetermined else { return currentStatus }
        let requestedStatus = await store.requestAuthorization()
        debugLogger("[HealthKit] requestAuthorizationIfNeeded status=\(requestedStatus.debugLabel)")
        return requestedStatus
    }

    func healthAuthorizationDetails() async -> HealthKitAuthorizationDebugDetails? {
        await store.debugAuthorizationDetails()
    }

    func requestHealthAccess() async -> WorkoutLoadResult {
        guard store.isAvailable else {
            debugLogger("[HealthKit] requestHealthAccess unavailable")
            return WorkoutLoadResult(workouts: [], source: .healthKit, statusMessage: "此裝置不支援 Apple Health。")
        }
        // Always call requestAuthorization directly. iOS shows the dialog only for
        // types not yet decided by the user; it silently no-ops for already-determined
        // types. Using the "if needed" guard caused the dialog to never appear after
        // the first auth because HK returns .sharingDenied for read-only types.
        let authorizationStatus = await store.requestAuthorization()
        debugLogger("[HealthKit] requestHealthAccess authorization=\(authorizationStatus.debugLabel)")
        await logAuthorizationDetails(context: "requestHealthAccess")
        await logGlobalRecoveryProbe(context: "requestHealthAccess")

        do {
            let snapshots = try await store.fetchRecentWorkouts(limit: workoutLimit)
            cachedWorkouts = snapshots.map(\.toDomainWorkout)
            await loadSleepContext(context: "requestHealthAccess", days: 7)
            let effectiveStatus = effectiveAuthorizationStatus(
                rawStatus: authorizationStatus,
                workouts: cachedWorkouts
            )
            debugLogger("[HealthKit] requestHealthAccess authorization=\(effectiveStatus.debugLabel) raw_authorization=\(authorizationStatus.debugLabel)")
            logWorkoutLoadSummary(context: "requestHealthAccess", snapshots: snapshots, workouts: cachedWorkouts)
            return WorkoutLoadResult(
                workouts: cachedWorkouts,
                source: .healthKit,
                statusMessage: statusMessage(for: effectiveStatus, workoutCount: cachedWorkouts.count),
                sleepContext: cachedSleepContext
            )
        } catch {
            cachedWorkouts = []
            cachedSleepContext = nil
            debugLogger("[HealthKit] requestHealthAccess fetch_failed error=\(String(describing: error))")
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
            debugLogger("[HealthKit] refreshResult unavailable")
            return WorkoutLoadResult(
                workouts: [],
                source: .healthKit,
                statusMessage: "此裝置不支援 Apple Health。"
            )
        }

        do {
            let snapshots = try await store.fetchRecentWorkouts(limit: workoutLimit)
            cachedWorkouts = snapshots.map(\.toDomainWorkout)
            await loadSleepContext(context: "refreshResult", days: 7)
            let rawStatus = store.authorizationStatus
            let effectiveStatus = effectiveAuthorizationStatus(rawStatus: rawStatus, workouts: cachedWorkouts)
            debugLogger("[HealthKit] refreshResult authorization=\(effectiveStatus.debugLabel) raw_authorization=\(rawStatus.debugLabel)")
            await logAuthorizationDetails(context: "refreshResult")
            await logGlobalRecoveryProbe(context: "refreshResult")
            logWorkoutLoadSummary(context: "refreshResult", snapshots: snapshots, workouts: cachedWorkouts)
        } catch {
            cachedWorkouts = []
            cachedSleepContext = nil
            debugLogger("[HealthKit] refreshResult fetch_failed error=\(String(describing: error))")
            return WorkoutLoadResult(
                workouts: [],
                source: .healthKit,
                statusMessage: "Apple Health 已授權，但無法載入運動資料。"
            )
        }

        return WorkoutLoadResult(
            workouts: cachedWorkouts,
            source: .healthKit,
            statusMessage: cachedWorkouts.isEmpty ? "尚未取得 Apple Health 授權，或找不到運動紀錄。" : "已從 Apple Health 載入運動紀錄。",
            sleepContext: cachedSleepContext
        )
    }

    private func loadSleepContext(context: String, days: Int) async {
        do {
            let result = try await store.fetchRecentSleepContext(days: days)
            cachedSleepContext = result.context
            logSleepContext(context: context, result: result)
        } catch {
            cachedSleepContext = nil
            debugLogger(
                "[HealthKit] \(context) sleep_context error=\(healthKitSleepErrorLabel(error)) " +
                "lookback_days=\(max(1, days))"
            )
        }
    }

    private func logSleepContext(context: String, result: HealthKitSleepContextQueryResult) {
        let base = "[HealthKit] \(context) sleep_context " +
            "lookback_days=\(result.lookbackDays) " +
            "raw_samples=\(result.rawSampleCount) " +
            "asleep_samples=\(result.asleepSampleCount)"
        guard let sleepContext = result.context, sleepContext.hasSleepData else {
            debugLogger("\(base) status=missing")
            return
        }
        let avg = sleepContext.averageSleepHours.map { String(format: "%.1f", $0) } ?? "unknown"
        debugLogger(
            "\(base) status=available " +
            "nights=\(sleepContext.nightsWithSleep)/\(sleepContext.lookbackDays) " +
            "avg_hours=\(avg)"
        )
    }

    private func logWorkoutLoadSummary(
        context: String,
        snapshots: [HealthKitWorkoutSnapshot],
        workouts: [WorkoutInput]
    ) {
        debugLogger("[HealthKit] \(context) workout_count=\(workouts.count)")
        for (index, workout) in workouts.enumerated() {
            let debugSnapshot = index < snapshots.count ? snapshots[index].debugSignalSnapshot : nil
            debugLogger(healthKitWorkoutDebugSummary(workout: workout, debugSnapshot: debugSnapshot, index: index))
        }
    }

    private func logAuthorizationDetails(context: String) async {
        guard let details = await store.debugAuthorizationDetails() else { return }
        debugLogger(
            "[HealthKit] \(context) type_authorization " +
            "workout=\(details.workout.debugLabel) " +
            "heartRate=\(details.heartRate.debugLabel) " +
            "vo2=\(details.vo2Max.debugLabel) " +
            "recovery=\(details.heartRateRecoveryOneMinute.debugLabel) " +
            "runningPower=\(details.runningPower.debugLabel) " +
            "cyclingPower=\(details.cyclingPower.debugLabel) " +
            "route=\(details.workoutRoute.debugLabel) " +
            "sleepAnalysis=\(details.sleepAnalysis.debugLabel)"
        )
    }

    private func logGlobalRecoveryProbe(context: String) async {
        guard let summary = await store.debugGlobalRecoveryProbe(limit: 5) else { return }
        debugLogger("[HealthKit] \(context) global_recovery_probe count=\(summary.count)")

        if summary.count == 0 {
            let fallback = workoutAssociatedRecoveryFallbackSummary(from: cachedWorkouts)
            let topTypesLabel = fallback.topWorkoutTypes.joined(separator: ",")
            debugLogger(
                "[HealthKit] \(context) global_recovery_fallback " +
                "workout_count=\(fallback.workoutCount) " +
                "top_types=\(topTypesLabel) " +
                "with_route=\(fallback.routeCount) with_vo2=\(fallback.vo2Count)"
            )
            return
        }

        for (index, record) in summary.records.enumerated() {
            let dateLabel = record.measuredAt.map(healthKitProbeDateFormatter.string(from:)) ?? "unknown"
            let sourceLabel = record.sourceLabel ?? record.source.rawValue
            debugLogger(
                "[HealthKit] \(context) global_recovery_probe[\(index)] " +
                "value=\(Int(record.value.rounded())) " +
                "measured_at=\(dateLabel) " +
                "source=\(sourceLabel)"
            )
        }
    }

    private func effectiveAuthorizationStatus(
        rawStatus: HealthAuthorizationStatus,
        workouts: [WorkoutInput]
    ) -> HealthAuthorizationStatus {
        guard rawStatus == .sharingDenied else { return rawStatus }
        return workouts.isEmpty ? rawStatus : .sharingAuthorized
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

private let healthKitDebugLogger: @Sendable (String) -> Void = { message in
#if DEBUG
    print(message)
#else
    _ = message
#endif
}

private func healthKitWorkoutDebugSummary(
    workout: WorkoutInput,
    debugSnapshot: HealthKitWorkoutDebugSignalSnapshot?,
    index: Int
) -> String {
    let flags = [
        "vo2=\(debugPresenceLabel(workout.vo2MaxEstimate))",
        "recovery=\(debugPresenceLabel(workout.heartRateRecoveryOneMinute))",
        "runningPower=\(debugPresenceLabel(workout.runningPower))",
        "cyclingPower=\(debugPresenceLabel(workout.cyclingPower))",
        "route=\(debugPresenceLabel(workout.workoutRoute))",
        "decoupling=\(debugPresenceLabel(workout.externalLoadDecoupling))",
        "recovery_candidates=\(debugSnapshot?.recoveryCandidateCount ?? -1)"
    ].joined(separator: " ")
    return "[HealthKit] workout[\(index)] type=\(workout.workoutType.rawValue) hr_samples=\(workout.heartRateSamples.count) \(flags)"
}

private func healthKitSleepErrorLabel(_ error: Error) -> String {
    if let storeError = error as? HealthKitStoreError {
        switch storeError {
        case .unavailable: return "unavailable"
        case .unauthorized: return "unauthorized"
        case .queryNotSupported: return "query_not_supported"
        }
    }
    return String(describing: error)
}

private func debugPresenceLabel(_ value: Any?) -> String {
    value == nil ? "missing" : "ok"
}

private struct WorkoutAssociatedRecoveryFallbackSummary: Equatable {
    let workoutCount: Int
    let topWorkoutTypes: [String]
    let routeCount: Int
    let vo2Count: Int
}

private func workoutAssociatedRecoveryFallbackSummary(from workouts: [WorkoutInput]) -> WorkoutAssociatedRecoveryFallbackSummary {
    var counts: [String: Int] = [:]
    for workout in workouts {
        counts[workout.workoutType.rawValue, default: 0] += 1
    }

    let topWorkoutTypes = counts
        .sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        .prefix(3)
        .map { "\($0.key):\($0.value)" }

    return WorkoutAssociatedRecoveryFallbackSummary(
        workoutCount: workouts.count,
        topWorkoutTypes: topWorkoutTypes,
        routeCount: workouts.filter { $0.workoutRoute != nil }.count,
        vo2Count: workouts.filter { $0.vo2MaxEstimate != nil }.count
    )
}

private let healthKitProbeDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension HealthAuthorizationStatus {
    var debugLabel: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .notDetermined:
            return "not_determined"
        case .sharingDenied:
            return "sharing_denied"
        case .sharingAuthorized:
            return "sharing_authorized"
        }
    }

    var localizedStatusLabel: String {
        switch self {
        case .unavailable:
            return "不可用"
        case .notDetermined:
            return "尚未決定"
        case .sharingDenied:
            return "未授權"
        case .sharingAuthorized:
            return "已授權"
        }
    }
}

#if canImport(HealthKit)
@available(iOS 17.0, macOS 14.0, *)
private func mapAuthorizationStatus(_ status: HKAuthorizationStatus) -> HealthAuthorizationStatus {
    switch status {
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
#endif

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
            let readTypes = Set(healthKitReadObjectTypes(heartRateType: heartRateType))

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

            return await workouts.asyncMapResilient { workout in
                // Per-workout resilience: if HR or HRV query fails for one workout,
                // return it with empty samples rather than failing the entire batch.
                let hrSamples = (try? await heartRateSamples(for: workout, from: store)) ?? []
                let postWorkoutHRSamples = (try? await postWorkoutHeartRateSamples(for: workout, from: store)) ?? []
                let hrvSDNNMilliseconds = try? await averageHRVSDNN(for: workout, from: store)
                let vo2MaxEstimate = try? await latestVO2MaxEstimate(near: workout.endDate, from: store)
                let recoveryCandidates = (try? await heartRateRecoveryCandidates(near: workout.endDate, from: store)) ?? []
                let importedRecovery = bestMatchingHeartRateRecoveryObservation(
                    near: workout.endDate,
                    candidates: recoveryCandidates
                )
                let heartRateRecoveryOneMinute = importedRecovery ?? derivedHeartRateRecoveryObservation(
                    workoutEndDate: workout.endDate,
                    inWorkoutSamples: hrSamples,
                    postWorkoutSamples: postWorkoutHRSamples
                )
                let runningPowerSamples = (try? await powerSamples(for: workout, identifier: .runningPower, from: store)) ?? []
                let cyclingPowerSamples = (try? await powerSamples(for: workout, identifier: .cyclingPower, from: store)) ?? []
                let runningPower = runningPowerObservation(from: runningPowerSamples, measuredAt: workout.endDate)
                let cyclingPower = cyclingPowerObservation(from: cyclingPowerSamples, measuredAt: workout.endDate)
                let workoutRoute = try? await summarizeWorkoutRoute(for: workout, from: store)
                let externalLoadDecoupling = externalLoadDecouplingObservation(
                    workoutType: workout.workoutActivityType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    heartRateSamples: hrSamples,
                    runningPowerSamples: runningPowerSamples,
                    cyclingPowerSamples: cyclingPowerSamples
                )
                let wType = domainWorkoutType(for: workout.workoutActivityType)
                let calories = workoutActiveCalories(workout)
                let distance = workoutDistance(workout, workoutType: wType)
                return HealthKitWorkoutSnapshot(
                    workoutType: wType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    heartRateSamples: hrSamples,
                    hrvSDNNMilliseconds: hrvSDNNMilliseconds,
                    vo2MaxEstimate: vo2MaxEstimate,
                    heartRateRecoveryOneMinute: heartRateRecoveryOneMinute,
                    runningPower: runningPower,
                    cyclingPower: cyclingPower,
                    workoutRoute: workoutRoute,
                    externalLoadDecoupling: externalLoadDecoupling,
                    debugSignalSnapshot: HealthKitWorkoutDebugSignalSnapshot(
                        recoveryCandidateCount: recoveryCandidates.count
                    ),
                    activeCaloriesKcal: calories,
                    totalDistanceMeters: distance
                )
            }
        }
        throw HealthKitStoreError.unavailable
        #else
        _ = limit
        throw HealthKitStoreError.unavailable
        #endif
    }

    func fetchRecentSleepContext(days: Int) async throws -> HealthKitSleepContextQueryResult {
        guard isAvailable else { throw HealthKitStoreError.unavailable }

        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            return try await recentSleepContext(days: days, from: store)
        }
        throw HealthKitStoreError.unavailable
        #else
        _ = days
        throw HealthKitStoreError.unavailable
        #endif
    }

    func fetchRestingHeartRateBaseline() async throws -> Double? {
        guard isAvailable else { throw HealthKitStoreError.unavailable }

        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            return try await recentRestingHeartRateBaseline(from: store)
        }
        throw HealthKitStoreError.unavailable
        #else
        throw HealthKitStoreError.unavailable
        #endif
    }

    func debugAuthorizationDetails() async -> HealthKitAuthorizationDebugDetails? {
        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            guard
                let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
                let vo2MaxType = HKObjectType.quantityType(forIdentifier: .vo2Max),
                let recoveryType = HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute),
                let runningPowerType = HKObjectType.quantityType(forIdentifier: .runningPower),
                let cyclingPowerType = HKObjectType.quantityType(forIdentifier: .cyclingPower),
                let sleepAnalysisType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
            else {
                return nil
            }

            return HealthKitAuthorizationDebugDetails(
                workout: mapAuthorizationStatus(store.authorizationStatus(for: HKObjectType.workoutType())),
                heartRate: mapAuthorizationStatus(store.authorizationStatus(for: heartRateType)),
                vo2Max: mapAuthorizationStatus(store.authorizationStatus(for: vo2MaxType)),
                heartRateRecoveryOneMinute: mapAuthorizationStatus(store.authorizationStatus(for: recoveryType)),
                runningPower: mapAuthorizationStatus(store.authorizationStatus(for: runningPowerType)),
                cyclingPower: mapAuthorizationStatus(store.authorizationStatus(for: cyclingPowerType)),
                workoutRoute: mapAuthorizationStatus(store.authorizationStatus(for: HKSeriesType.workoutRoute())),
                sleepAnalysis: mapAuthorizationStatus(store.authorizationStatus(for: sleepAnalysisType))
            )
        }
        return nil
        #else
        return nil
        #endif
    }

    func debugGlobalRecoveryProbe(limit: Int) async -> HealthKitRecoveryProbeSummary? {
        #if canImport(HealthKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            let store = HKHealthStore()
            let records = (try? await recentGlobalHeartRateRecoverySamples(limit: limit, from: store)) ?? []
            return HealthKitRecoveryProbeSummary(count: records.count, records: records)
        }
        return nil
        #else
        _ = limit
        return nil
        #endif
    }
}

let healthKitReadTypeIdentifiers: [String] = [
    "workout",
    "heartRate",
    "restingHeartRate",
    "heartRateVariabilitySDNN",
    "sleepAnalysis",
    "activeEnergyBurned",
    "distanceWalkingRunning",
    "distanceCycling",
    "distanceSwimming",
    "vo2Max",
    "heartRateRecoveryOneMinute",
    "runningPower",
    "cyclingPower",
    "workoutRoute",
]

let heartRateRecoveryPostWorkoutMatchingWindow: TimeInterval = 10 * 60
let derivedHeartRateRecoveryFallbackWindow: TimeInterval = 2 * 60

struct HealthKitAuthorizationDebugDetails: Equatable, Sendable {
    let workout: HealthAuthorizationStatus
    let heartRate: HealthAuthorizationStatus
    let vo2Max: HealthAuthorizationStatus
    let heartRateRecoveryOneMinute: HealthAuthorizationStatus
    let runningPower: HealthAuthorizationStatus
    let cyclingPower: HealthAuthorizationStatus
    let workoutRoute: HealthAuthorizationStatus
    let sleepAnalysis: HealthAuthorizationStatus
}

struct HealthKitRecoveryProbeRecord: Equatable, Sendable {
    let value: Double
    let measuredAt: Date?
    let source: TrainingMetricMethodSource
    let sourceLabel: String?
}

struct HealthKitRecoveryProbeSummary: Equatable, Sendable {
    let count: Int
    let records: [HealthKitRecoveryProbeRecord]
}

#if canImport(HealthKit)
@available(iOS 17.0, macOS 14.0, *)
private func healthKitReadObjectTypes(heartRateType: HKQuantityType) -> [HKObjectType] {
    [
        HKObjectType.workoutType(),
        heartRateType,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate),
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
        HKObjectType.quantityType(forIdentifier: .distanceCycling),
        HKObjectType.quantityType(forIdentifier: .distanceSwimming),
        HKObjectType.quantityType(forIdentifier: .vo2Max),
        HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute),
        HKObjectType.quantityType(forIdentifier: .runningPower),
        HKObjectType.quantityType(forIdentifier: .cyclingPower),
        HKSeriesType.workoutRoute(),
    ].compactMap { $0 }
}
#endif

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

    return try await heartRateSamples(
        from: workout.startDate,
        to: workout.endDate,
        options: [.strictStartDate, .strictEndDate],
        heartRateType: heartRateType,
        store: store
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func postWorkoutHeartRateSamples(for workout: HKWorkout, from store: HKHealthStore) async throws -> [HeartRateSample] {
    guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
        throw HealthKitStoreError.queryNotSupported
    }

    return try await heartRateSamples(
        from: workout.endDate,
        to: workout.endDate.addingTimeInterval(derivedHeartRateRecoveryFallbackWindow),
        options: [.strictStartDate],
        heartRateType: heartRateType,
        store: store
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func heartRateSamples(
    from startDate: Date,
    to endDate: Date,
    options: HKQueryOptions,
    heartRateType: HKQuantityType,
    store: HKHealthStore
) async throws -> [HeartRateSample] {
    let predicate = HKQuery.predicateForSamples(
        withStart: startDate,
        end: endDate,
        options: options
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

    let strictWorkoutPredicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: [.strictStartDate, .strictEndDate]
    )
    let strictSamples = try await queryHRVSamples(from: store, hrvType: hrvType, predicate: strictWorkoutPredicate)
    if let value = averageHRV(samples: strictSamples) {
        return value
    }

    // Fallback: many Apple Health HRV samples are recorded outside workout intervals.
    // If strict workout window has no samples, use same-day HRV observation as bounded fallback.
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: workout.startDate)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return nil
    }
    let sameDayPredicate = HKQuery.predicateForSamples(
        withStart: dayStart,
        end: dayEnd,
        options: [.strictStartDate]
    )
    let sameDaySamples = try await queryHRVSamples(from: store, hrvType: hrvType, predicate: sameDayPredicate)
    return averageHRV(samples: sameDaySamples)
}

@available(iOS 17.0, macOS 14.0, *)
private func queryHRVSamples(
    from store: HKHealthStore,
    hrvType: HKQuantityType,
    predicate: NSPredicate
) async throws -> [HKQuantitySample] {
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    return try await withCheckedThrowingContinuation { continuation in
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
}

@available(iOS 17.0, macOS 14.0, *)
private func averageHRV(samples: [HKQuantitySample]) -> Double? {
    guard !samples.isEmpty else { return nil }
    let unit = HKUnit.secondUnit(with: .milli)
    let sum = samples.reduce(0.0) { partial, sample in
        partial + sample.quantity.doubleValue(for: unit)
    }
    return sum / Double(samples.count)
}

@available(iOS 17.0, macOS 14.0, *)
private func recentSleepContext(
    days: Int,
    now: Date = Date(),
    from store: HKHealthStore,
    calendar: Calendar = .current
) async throws -> HealthKitSleepContextQueryResult {
    guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
        throw HealthKitStoreError.queryNotSupported
    }

    let lookbackDays = max(1, days)
    let startDate = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now.addingTimeInterval(-Double(lookbackDays) * 86_400)
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: [])
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

    let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: sortDescriptors
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
        }
        store.execute(query)
    }

    let asleepSamples = samples.filter(isAsleepSleepAnalysisSample)

    let sleepContext = aggregateWeeklySleepContext(
        from: asleepSamples.map {
            HealthKitSleepInterval(startDate: $0.startDate, endDate: $0.endDate)
        },
        lookbackDays: lookbackDays,
        startDate: startDate,
        now: now
    )

    guard let sleepContext else {
        return HealthKitSleepContextQueryResult(
            context: nil,
            lookbackDays: lookbackDays,
            rawSampleCount: samples.count,
            asleepSampleCount: asleepSamples.count
        )
    }

    return HealthKitSleepContextQueryResult(
        context: sleepContext,
        lookbackDays: lookbackDays,
        rawSampleCount: samples.count,
        asleepSampleCount: asleepSamples.count
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func isAsleepSleepAnalysisSample(_ sample: HKCategorySample) -> Bool {
    let nonSleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.inBed.rawValue,
        HKCategoryValueSleepAnalysis.awake.rawValue
    ]
    return !nonSleepValues.contains(sample.value)
}

@available(iOS 17.0, macOS 14.0, *)
private func workoutActiveCalories(_ workout: HKWorkout) -> Double? {
    guard let statsType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
    return workout.statistics(for: statsType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
}

@available(iOS 17.0, macOS 14.0, *)
private func workoutDistance(_ workout: HKWorkout, workoutType: WorkoutType) -> Double? {
    let identifier: HKQuantityTypeIdentifier
    switch workoutType {
    case .cycling:
        identifier = .distanceCycling
    case .swimming:
        identifier = .distanceSwimming
    default:
        identifier = .distanceWalkingRunning
    }
    guard let statsType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
    return workout.statistics(for: statsType)?.sumQuantity()?.doubleValue(for: .meter())
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

@available(iOS 17.0, macOS 14.0, *)
private func latestVO2MaxEstimate(near date: Date, from store: HKHealthStore) async throws -> VO2MaxEstimate? {
    guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
        return nil
    }

    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -30, to: date) ?? date
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: date, options: .strictEndDate)
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
    let unit = HKUnit(from: "ml/kg*min")

    let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: vo2Type,
            predicate: predicate,
            limit: 1,
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

    guard let sample = samples.first else { return nil }
    return VO2MaxEstimate(
        value: sample.quantity.doubleValue(for: unit),
        source: .apple,
        sourceLabel: "Apple Health VO2 max",
        measuredAt: sample.endDate
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func latestHeartRateRecoveryOneMinute(near date: Date, from store: HKHealthStore) async throws -> HeartRateRecoveryObservation? {
    let candidates = try await heartRateRecoveryCandidates(near: date, from: store)
    return bestMatchingHeartRateRecoveryObservation(
        near: date,
        candidates: candidates
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func heartRateRecoveryCandidates(near date: Date, from store: HKHealthStore) async throws -> [HeartRateRecoveryObservation] {
    guard let recoveryType = HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) else {
        return []
    }

    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -30, to: date) ?? date
    let endDate = date.addingTimeInterval(heartRateRecoveryPostWorkoutMatchingWindow)
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

    let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: recoveryType,
            predicate: predicate,
            limit: 10,
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

    return samples.map { sample in
        HeartRateRecoveryObservation(
            value: sample.quantity.doubleValue(for: unit),
            source: .apple,
            sourceLabel: "Apple Health 1-minute heart-rate recovery",
            measuredAt: sample.endDate
        )
    }
}

func bestMatchingHeartRateRecoveryObservation(
    near workoutEndDate: Date,
    candidates: [HeartRateRecoveryObservation],
    postWorkoutWindow: TimeInterval = heartRateRecoveryPostWorkoutMatchingWindow
) -> HeartRateRecoveryObservation? {
    let lowerBound = workoutEndDate.addingTimeInterval(-30 * 24 * 60 * 60)
    let upperBound = workoutEndDate.addingTimeInterval(postWorkoutWindow)

    return candidates
        .filter { candidate in
            guard let measuredAt = candidate.measuredAt else { return false }
            return measuredAt >= lowerBound && measuredAt <= upperBound
        }
        .min { lhs, rhs in
            let lhsDistance = abs((lhs.measuredAt ?? .distantFuture).timeIntervalSince(workoutEndDate))
            let rhsDistance = abs((rhs.measuredAt ?? .distantFuture).timeIntervalSince(workoutEndDate))
            if lhsDistance == rhsDistance {
                return (lhs.measuredAt ?? .distantPast) > (rhs.measuredAt ?? .distantPast)
            }
            return lhsDistance < rhsDistance
        }
}

func derivedHeartRateRecoveryObservation(
    workoutEndDate: Date,
    inWorkoutSamples: [HeartRateSample],
    postWorkoutSamples: [HeartRateSample]
) -> HeartRateRecoveryObservation? {
    guard !postWorkoutSamples.isEmpty else { return nil }

    let baselineWindowStart = workoutEndDate.addingTimeInterval(-30)
    let baselineCandidates = inWorkoutSamples.filter { $0.timestamp >= baselineWindowStart && $0.timestamp <= workoutEndDate }
    let baselineSample = postWorkoutSamples.first ?? baselineCandidates.max(by: { $0.timestamp < $1.timestamp })
    guard let baselineSample else { return nil }

    let targetDate = workoutEndDate.addingTimeInterval(60)
    let oneMinuteCandidates = postWorkoutSamples.filter {
        abs($0.timestamp.timeIntervalSince(targetDate)) <= 30
    }
    guard
        let oneMinuteSample = oneMinuteCandidates.min(by: {
            abs($0.timestamp.timeIntervalSince(targetDate)) < abs($1.timestamp.timeIntervalSince(targetDate))
        })
    else {
        return nil
    }

    return HeartRateRecoveryObservation(
        value: baselineSample.bpm - oneMinuteSample.bpm,
        source: .apple,
        sourceLabel: "Derived from Apple Health post-workout heart rate",
        measuredAt: oneMinuteSample.timestamp
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func recentGlobalHeartRateRecoverySamples(
    limit: Int,
    from store: HKHealthStore
) async throws -> [HealthKitRecoveryProbeRecord] {
    guard let recoveryType = HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) else {
        return []
    }

    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

    let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: recoveryType,
            predicate: nil,
            limit: limit,
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

    return samples.map { sample in
        HealthKitRecoveryProbeRecord(
            value: sample.quantity.doubleValue(for: unit),
            measuredAt: sample.endDate,
            source: .apple,
            sourceLabel: sample.sourceRevision.source.name
        )
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func powerSamples(
    for workout: HKWorkout,
    identifier: HKQuantityTypeIdentifier,
    from store: HKHealthStore
) async throws -> [TimedPowerSample] {
    guard let powerType = HKObjectType.quantityType(forIdentifier: identifier) else {
        return []
    }

    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: [.strictStartDate, .strictEndDate]
    )
    let unit = HKUnit.watt()
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

    let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: powerType,
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

    return samples.map { sample in
        TimedPowerSample(
            timestamp: sample.startDate,
            watts: sample.quantity.doubleValue(for: unit)
        )
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func averageRunningPower(for workout: HKWorkout, from store: HKHealthStore) async throws -> RunningPowerObservation? {
    runningPowerObservation(
        from: try await powerSamples(for: workout, identifier: .runningPower, from: store),
        measuredAt: workout.endDate
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func averageCyclingPower(for workout: HKWorkout, from store: HKHealthStore) async throws -> CyclingPowerObservation? {
    cyclingPowerObservation(
        from: try await powerSamples(for: workout, identifier: .cyclingPower, from: store),
        measuredAt: workout.endDate
    )
}

func runningPowerObservation(
    from samples: [TimedPowerSample],
    measuredAt: Date?
) -> RunningPowerObservation? {
    guard !samples.isEmpty else { return nil }
    let total = samples.reduce(0.0) { partial, sample in
        partial + sample.watts
    }
    return RunningPowerObservation(
        averageWatts: total / Double(samples.count),
        source: .runningHRSpeed,
        sourceLabel: "Apple Health running power",
        measuredAt: measuredAt
    )
}

func cyclingPowerObservation(
    from samples: [TimedPowerSample],
    measuredAt: Date?
) -> CyclingPowerObservation? {
    guard !samples.isEmpty else { return nil }
    let total = samples.reduce(0.0) { partial, sample in
        partial + sample.watts
    }
    return CyclingPowerObservation(
        averageWatts: total / Double(samples.count),
        source: .cyclingPowerHR,
        sourceLabel: "Apple Health cycling power",
        measuredAt: measuredAt
    )
}

func externalLoadDecouplingObservation(
    workoutType: HKWorkoutActivityType? = nil,
    startDate: Date,
    endDate: Date,
    heartRateSamples: [HeartRateSample],
    runningPowerSamples: [TimedPowerSample],
    cyclingPowerSamples: [TimedPowerSample]
) -> ExternalLoadDecouplingObservation? {
    let selectedSource: TrainingMetricMethodSource
    let selectedLabel: String
    let selectedPowerSamples: [TimedPowerSample]

    switch workoutType {
    case .cycling:
        selectedSource = .cyclingPowerHR
        selectedLabel = "Apple Health cycling power + HR decoupling"
        selectedPowerSamples = cyclingPowerSamples
    case .running, .walking, .hiking:
        selectedSource = .runningHRSpeed
        selectedLabel = "Apple Health running power + HR decoupling"
        selectedPowerSamples = runningPowerSamples
    default:
        if !runningPowerSamples.isEmpty {
            selectedSource = .runningHRSpeed
            selectedLabel = "Apple Health running power + HR decoupling"
            selectedPowerSamples = runningPowerSamples
        } else {
            selectedSource = .cyclingPowerHR
            selectedLabel = "Apple Health cycling power + HR decoupling"
            selectedPowerSamples = cyclingPowerSamples
        }
    }

    guard !selectedPowerSamples.isEmpty, heartRateSamples.count >= 4 else { return nil }
    let midpoint = startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)

    let firstHalfHeartRate = heartRateSamples.filter { $0.timestamp < midpoint }
    let secondHalfHeartRate = heartRateSamples.filter { $0.timestamp >= midpoint }
    let firstHalfPower = selectedPowerSamples.filter { $0.timestamp < midpoint }
    let secondHalfPower = selectedPowerSamples.filter { $0.timestamp >= midpoint }

    guard
        firstHalfHeartRate.count >= 2,
        secondHalfHeartRate.count >= 2,
        !firstHalfPower.isEmpty,
        !secondHalfPower.isEmpty
    else {
        return nil
    }

    let firstHalfAverageHeartRate = average(firstHalfHeartRate.map(\.bpm))
    let secondHalfAverageHeartRate = average(secondHalfHeartRate.map(\.bpm))
    let firstHalfAverageWatts = average(firstHalfPower.map(\.watts))
    let secondHalfAverageWatts = average(secondHalfPower.map(\.watts))

    guard firstHalfAverageWatts > 0, secondHalfAverageWatts > 0 else { return nil }

    let firstHalfRatio = firstHalfAverageHeartRate / firstHalfAverageWatts
    let secondHalfRatio = secondHalfAverageHeartRate / secondHalfAverageWatts
    guard firstHalfRatio > 0 else { return nil }

    return ExternalLoadDecouplingObservation(
        decouplingRatio: (secondHalfRatio - firstHalfRatio) / firstHalfRatio,
        firstHalfAverageHeartRate: firstHalfAverageHeartRate,
        secondHalfAverageHeartRate: secondHalfAverageHeartRate,
        firstHalfAverageWatts: firstHalfAverageWatts,
        secondHalfAverageWatts: secondHalfAverageWatts,
        source: selectedSource,
        sourceLabel: selectedLabel,
        measuredAt: endDate
    )
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

@available(iOS 17.0, macOS 14.0, *)
private func summarizeWorkoutRoute(for workout: HKWorkout, from store: HKHealthStore) async throws -> WorkoutRouteObservation? {
    let routes = try await workoutRoutes(for: workout, from: store)
    guard !routes.isEmpty else { return nil }

    var pointCount = 0
    var elevationGain = 0.0
    var previousAltitude: Double?

    for route in routes {
        let locations = try await routeLocations(for: route, from: store)
        pointCount += locations.count
        for location in locations where location.verticalAccuracy >= 0 {
            let altitude = location.altitude
            if let previousAltitude, altitude > previousAltitude {
                elevationGain += altitude - previousAltitude
            }
            previousAltitude = altitude
        }
    }

    guard pointCount > 0 else { return nil }
    return WorkoutRouteObservation(
        pointCount: pointCount,
        elevationGainMeters: elevationGain > 0 ? elevationGain : nil,
        source: .workoutRoute,
        sourceLabel: "Apple Health workout route"
    )
}

@available(iOS 17.0, macOS 14.0, *)
private func workoutRoutes(for workout: HKWorkout, from store: HKHealthStore) async throws -> [HKWorkoutRoute] {
    try await withCheckedThrowingContinuation { continuation in
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
        }
        store.execute(query)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func routeLocations(for route: HKWorkoutRoute, from store: HKHealthStore) async throws -> [CLLocation] {
    try await withCheckedThrowingContinuation { continuation in
        let collector = WorkoutRouteQueryBatchCollector<CLLocation>()
        let query = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, error in
            if let completion = collector.record(locations: locationsOrNil, done: done, error: error) {
                continuation.resume(with: completion)
            }
        }
        store.execute(query)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private func recentRestingHeartRateBaseline(from store: HKHealthStore) async throws -> Double? {
    guard let restingType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
        throw HealthKitStoreError.queryNotSupported
    }

    let calendar = Calendar.current
    let endDate = Date()
    let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
    let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

    let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: restingType,
            predicate: predicate,
            limit: 14,
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

    guard !samples.isEmpty else { return nil }
    let total = samples.reduce(0.0) { partial, sample in
        partial + sample.quantity.doubleValue(for: unit)
    }
    return total / Double(samples.count)
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

    func asyncMapResilient<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
