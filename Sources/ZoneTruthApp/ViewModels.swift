import Foundation
import AuthenticationServices
import ZoneTruthCore

enum IntentApplyScope: String, CaseIterable, Identifiable, Sendable {
    case allLoaded
    case last4Weeks
    case sameSource

    var id: String { rawValue }
}

enum WorkoutDataSource: String, Equatable, Sendable {
    case healthKit = "Apple Health"
    case strava = "Strava"
    case combined = "Apple Health + Strava"
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

struct WeeklyIntentOverrideInsight: Equatable, Sendable {
    let overrideCount: Int
    let workoutCount: Int
    let topOverriddenType: WorkoutType?
    let topOverriddenTypeCount: Int

    var overrideRate: Double {
        guard workoutCount > 0 else { return 0 }
        return Double(overrideCount) / Double(workoutCount)
    }

    static let empty = WeeklyIntentOverrideInsight(
        overrideCount: 0,
        workoutCount: 0,
        topOverriddenType: nil,
        topOverriddenTypeCount: 0
    )
}

protocol WorkoutIntentOverrideStore {
    func load() -> [UUID: TrainingIntent]
    func save(_ overrides: [UUID: TrainingIntent]) throws
}

struct FileWorkoutIntentOverrideStore: WorkoutIntentOverrideStore {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> [UUID: TrainingIntent] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([UUID: TrainingIntent].self, from: data)) ?? [:]
    }

    func save(_ overrides: [UUID: TrainingIntent]) throws {
        let data = try JSONEncoder().encode(overrides)
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: fileURL, options: .atomic)
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
    @Published private(set) var weeklySummary: WeeklyWorkoutSummary
    @Published private(set) var weeklyPolicy: WeeklyLoadPolicy
    @Published private(set) var weeklyOverrideInsight: WeeklyIntentOverrideInsight
    @Published private(set) var adaptationTrend28d: AdaptationTrend28d?
    let bodyCompositionLedger: BodyCompositionLedger?

    let stravaAuthorizationURL: URL?
    let feedbackStore: any TrainingClassificationFeedbackStoring
    private let repository: WorkoutRepository
    private let intentOverrideStore: WorkoutIntentOverrideStore
    private let settingsManager: SettingsManager
    private let callbackHandler: StravaCallbackHandler?
    private var oauthCoordinator: StravaOAuthCoordinator?
    private var intentOverrides: [UUID: TrainingIntent]

    init(
        repository: WorkoutRepository,
        intentOverrideStore: WorkoutIntentOverrideStore = InMemoryWorkoutIntentOverrideStore(),
        feedbackStore: any TrainingClassificationFeedbackStoring = InMemoryTrainingClassificationFeedbackStore(),
        settingsManager: SettingsManager,
        stravaAuthorizationURL: URL? = nil,
        callbackHandler: StravaCallbackHandler? = nil,
        bodyCompositionLedger: BodyCompositionLedger? = nil
    ) {
        self.repository = repository
        self.intentOverrideStore = intentOverrideStore
        self.feedbackStore = feedbackStore
        self.settingsManager = settingsManager
        self.stravaAuthorizationURL = stravaAuthorizationURL
        self.callbackHandler = callbackHandler
        self.bodyCompositionLedger = bodyCompositionLedger
        let monday = Self.currentWeekMonday()
        let emptySummary = WeeklyObservationBuilder.build(workouts: [], weekStart: monday)
        self.weeklySummary = emptySummary
        self.weeklyPolicy = WeeklyLoadPolicyEngine.evaluate(summary: emptySummary)
        self.weeklyOverrideInsight = .empty
        self.adaptationTrend28d = nil
        self.intentOverrides = intentOverrideStore.load()
        apply(repository.loadResult())
    }

    var canConnectStrava: Bool {
        stravaAuthorizationURL != nil && currentSource != .strava && currentSource != .combined
    }

    var canDisconnectStrava: Bool {
        callbackHandler != nil && (currentSource == .strava || currentSource == .combined)
    }

    func connectStrava() async {
        guard let url = stravaAuthorizationURL, let handler = callbackHandler else { return }
        let coordinator = StravaOAuthCoordinator()
        oauthCoordinator = coordinator
        defer { oauthCoordinator = nil }
        do {
            let callbackURL = try await coordinator.authenticate(url: url, callbackScheme: "zonetruth")
            let handled = await handler.handle(callbackURL)
            // Always refresh so the UI reflects the latest state,
            // even if handle returned false (e.g. token exchange failed).
            if handled {
                statusMessage = "Strava 授權成功，正在載入活動…"
            } else {
                statusMessage = "Strava 授權收到但 token 交換失敗，請重試。"
            }
            await refreshWorkouts()
        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                statusMessage = "已取消 Strava 登入。"
            } else {
                statusMessage = "Strava 登入失敗：\(nsError.localizedDescription)"
            }
        }
    }

    func disconnectStrava() async {
        callbackHandler?.disconnect()
        await refreshWorkouts()
    }

    func selectWorkout(_ workout: WorkoutInput) {
        selectedWorkout = workout
        selectedIntent = workout.intent
    }

    func updateIntent(_ intent: TrainingIntent) {
        selectedIntent = intent
        guard let workout = selectedWorkout else { return }
        if intent == settingsManager.defaultIntent(for: workout.workoutType) {
            intentOverrides.removeValue(forKey: workout.id)
        } else {
            intentOverrides[workout.id] = intent
        }
        try? intentOverrideStore.save(intentOverrides)
        let refreshed = workouts.map { current -> WorkoutInput in
            guard current.id == workout.id else { return current }
            return WorkoutInput(
                id: current.id,
                workoutType: current.workoutType,
                startDate: current.startDate,
                endDate: current.endDate,
                durationSeconds: current.durationSeconds,
                heartRateSamples: current.heartRateSamples,
                hrvSDNNMilliseconds: current.hrvSDNNMilliseconds,
                intent: intent,
                intentSource: intent == settingsManager.defaultIntent(for: current.workoutType) ? .auto : .userOverride,
                dataSource: current.dataSource,
                activeCaloriesKcal: current.activeCaloriesKcal,
                totalDistanceMeters: current.totalDistanceMeters,
                vo2MaxEstimate: current.vo2MaxEstimate,
                strengthMetrics: current.strengthMetrics
            )
        }
        apply(
            WorkoutLoadResult(
                workouts: refreshed,
                source: currentSource,
                statusMessage: statusMessage
            )
        )
    }

    func applySelectedIntentToSameWorkoutType() {
        applySelectedIntentToSameWorkoutType(scope: .allLoaded)
    }

    func impactedCountForSelectedIntent(scope: IntentApplyScope) -> Int {
        guard let workout = selectedWorkout else { return 0 }
        return workouts.filter { matchesScope($0, selected: workout, scope: scope) }.count
    }

    func applySelectedIntentToSameWorkoutType(scope: IntentApplyScope) {
        guard let workout = selectedWorkout else { return }
        let targetType = workout.workoutType
        let targetIntent = selectedIntent

        for candidate in workouts where matchesScope(candidate, selected: workout, scope: scope) && candidate.workoutType == targetType {
            if targetIntent == settingsManager.defaultIntent(for: candidate.workoutType) {
                intentOverrides.removeValue(forKey: candidate.id)
            } else {
                intentOverrides[candidate.id] = targetIntent
            }
        }
        try? intentOverrideStore.save(intentOverrides)
        apply(
            WorkoutLoadResult(
                workouts: workouts,
                source: currentSource,
                statusMessage: statusMessage
            )
        )
    }

    private func matchesScope(_ candidate: WorkoutInput, selected: WorkoutInput, scope: IntentApplyScope) -> Bool {
        guard candidate.workoutType == selected.workoutType else { return false }
        switch scope {
        case .allLoaded:
            return true
        case .last4Weeks:
            let windowStart = selected.startDate.addingTimeInterval(-28 * 24 * 60 * 60)
            return candidate.startDate >= windowStart && candidate.startDate <= selected.startDate
        case .sameSource:
            return candidate.dataSource == selected.dataSource
        }
    }

    func applyDefaultIntentOverridesToCurrentWorkouts() {
        apply(
            WorkoutLoadResult(
                workouts: workouts,
                source: currentSource,
                statusMessage: statusMessage
            )
        )
    }

    func refreshDerivedDataForCurrentPolicy() {
        updateWeeklyData(workouts: workouts)
        triggerCalibrationCheck()
    }

    func effectiveIntentSource(for workout: WorkoutInput) -> IntentSource {
        guard selectedWorkout?.id == workout.id else { return workout.intentSource }
        return selectedIntent == workout.intent ? workout.intentSource : .userOverride
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
            hrvSDNNMilliseconds: workout.hrvSDNNMilliseconds,
            intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent,
            intentSource: effectiveIntentSource(for: workout),
            dataSource: workout.dataSource,
            activeCaloriesKcal: workout.activeCaloriesKcal,
            totalDistanceMeters: workout.totalDistanceMeters,
            vo2MaxEstimate: workout.vo2MaxEstimate,
            strengthMetrics: workout.strengthMetrics
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
            hrvSDNNMilliseconds: workout.hrvSDNNMilliseconds,
            intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent,
            intentSource: effectiveIntentSource(for: workout),
            dataSource: workout.dataSource,
            activeCaloriesKcal: workout.activeCaloriesKcal,
            totalDistanceMeters: workout.totalDistanceMeters,
            vo2MaxEstimate: workout.vo2MaxEstimate,
            strengthMetrics: workout.strengthMetrics
        )
        let legacy = WorkoutIntentAnalyzer.analyze(rewritten, policy: settingsManager.policy)
        return WorkoutEvaluationAdapter.mapLegacyAnalysisToEvaluation(
            primaryIntentBaseline: rewritten.intent,
            legacy: legacy
        )
    }

    func analysisZoneContextSummary(for workout: WorkoutInput) -> String {
        let bounds = settingsManager.policy.zoneBounds
        let sourceLabel: String
        if settingsManager.zoneBoundsSource == .restingHeartRateHeuristic {
            sourceLabel = "Resting HR 建議已套用"
        } else if settingsManager.zoneBoundsSource == .driftTrend {
            sourceLabel = "歷史飄移校正已套用"
        } else if settingsManager.isUsingCustomZoneBounds {
            sourceLabel = "自訂界線"
        } else {
            sourceLabel = "預設界線"
        }
        return "\(sourceLabel) · Zone 2 \(Int(bounds.zone2LowerBound.rounded()))-\(Int(bounds.zone2UpperBound.rounded())) bpm"
    }

    private func apply(_ result: WorkoutLoadResult) {
        workouts = result.workouts.map { base in
            guard let overriddenIntent = intentOverrides[base.id] else { return base }
            return WorkoutInput(
                id: base.id,
                workoutType: base.workoutType,
                startDate: base.startDate,
                endDate: base.endDate,
                durationSeconds: base.durationSeconds,
                heartRateSamples: base.heartRateSamples,
                hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
                intent: overriddenIntent,
                intentSource: .userOverride,
                dataSource: base.dataSource,
                activeCaloriesKcal: base.activeCaloriesKcal,
                totalDistanceMeters: base.totalDistanceMeters,
                vo2MaxEstimate: base.vo2MaxEstimate,
                strengthMetrics: base.strengthMetrics
            )
        }.map { base in
            guard base.intentSource == .auto else { return base }
            let defaultIntent = settingsManager.defaultIntent(for: base.workoutType)
            return WorkoutInput(
                id: base.id,
                workoutType: base.workoutType,
                startDate: base.startDate,
                endDate: base.endDate,
                durationSeconds: base.durationSeconds,
                heartRateSamples: base.heartRateSamples,
                hrvSDNNMilliseconds: base.hrvSDNNMilliseconds,
                intent: defaultIntent,
                intentSource: .auto,
                dataSource: base.dataSource,
                activeCaloriesKcal: base.activeCaloriesKcal,
                totalDistanceMeters: base.totalDistanceMeters,
                vo2MaxEstimate: base.vo2MaxEstimate,
                strengthMetrics: base.strengthMetrics
            )
        }
        currentSource = result.source
        statusMessage = result.statusMessage
        // If current selection is no longer in the new list, clear it (don't auto-pick first).
        if let current = selectedWorkout, !result.workouts.contains(where: { $0.id == current.id }) {
            selectedWorkout = nil
        }
        if selectedWorkout == nil, let intent = result.workouts.first?.intent {
            selectedIntent = intent
        }
        updateWeeklyData(workouts: result.workouts)
        triggerCalibrationCheck()
    }

    private func updateWeeklyData(workouts: [WorkoutInput]) {
        let monday = Self.currentWeekMonday()
        let summary = WeeklyObservationBuilder.build(
            workouts: workouts,
            weekStart: monday,
            policy: settingsManager.policy
        )
        weeklySummary = summary
        weeklyPolicy = WeeklyLoadPolicyEngine.evaluate(summary: summary)
        weeklyOverrideInsight = buildWeeklyOverrideInsight(workouts: workouts, weekStart: monday)

        // 28d trend: last 4 weeks including current week
        let cal = Calendar.current
        let last4 = (0..<4).map { offset -> WeeklyWorkoutSummary in
            let weekMonday = cal.date(byAdding: .day, value: -7 * offset, to: monday) ?? monday
            return WeeklyObservationBuilder.build(
                workouts: workouts,
                weekStart: weekMonday,
                policy: settingsManager.policy
            )
        }
        adaptationTrend28d = MultiWeekAdaptationAnalyzer.analyze(summaries: last4)
    }

    private func buildWeeklyOverrideInsight(workouts: [WorkoutInput], weekStart: Date) -> WeeklyIntentOverrideInsight {
        let cal = Calendar.current
        let nextWeekStart = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let effectiveEnd = min(nextWeekStart, Date())
        let weekWorkouts = workouts.filter { $0.startDate >= weekStart && $0.startDate < effectiveEnd }
        let overrideCount = weekWorkouts.filter { $0.intentSource == .userOverride }.count

        var overriddenTypeCounts: [WorkoutType: Int] = [:]
        for workout in weekWorkouts where workout.intentSource == .userOverride {
            overriddenTypeCounts[workout.workoutType, default: 0] += 1
        }
        let top = overriddenTypeCounts.max(by: { $0.value < $1.value })

        return WeeklyIntentOverrideInsight(
            overrideCount: overrideCount,
            workoutCount: weekWorkouts.count,
            topOverriddenType: top?.key,
            topOverriddenTypeCount: top?.value ?? 0
        )
    }

    private static func currentWeekMonday() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = weekday == 1 ? 6 : (weekday - 2)
        return cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
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
                    hrvSDNNMilliseconds: workout.hrvSDNNMilliseconds,
                    intent: selectedWorkout?.id == workout.id ? selectedIntent : workout.intent,
                    intentSource: effectiveIntentSource(for: workout),
                    dataSource: workout.dataSource,
                    activeCaloriesKcal: workout.activeCaloriesKcal,
                    totalDistanceMeters: workout.totalDistanceMeters,
                    vo2MaxEstimate: workout.vo2MaxEstimate,
                    strengthMetrics: workout.strengthMetrics
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
        repository.supportsHealthAuthorization && currentSource != .healthKit && currentSource != .combined
    }
}

private struct InMemoryWorkoutIntentOverrideStore: WorkoutIntentOverrideStore {
    func load() -> [UUID: TrainingIntent] { [:] }
    func save(_ overrides: [UUID: TrainingIntent]) throws {}
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

private final class StravaOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { $0.windows.first { $0.isKeyWindow } }
            .first ?? ASPresentationAnchor()
        #else
        NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        #endif
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.activeSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            // activeSession must be set before start() so the session stays alive.
            // We let the completion handler exclusively own the continuation resume —
            // never calling resume in the else-branch avoids double-resume crashes.
            activeSession = session
            _ = session.start()
        }
    }
}
