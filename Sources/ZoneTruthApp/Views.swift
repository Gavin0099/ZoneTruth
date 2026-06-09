import SwiftUI
import Charts
import ZoneTruthCore

// MARK: - Extensions for Localization

extension WorkoutType {
    var localizedName: String {
        switch self {
        case .running: return "跑步"
        case .cycling: return "自行車"
        case .swimming: return "游泳"
        case .walking: return "步行/健走"
        case .strengthTraining: return "肌力訓練"
        case .mixed: return "最大攝氧量 / 間歇型"
        case .other: return "Zone 2 / 一般有氧"
        }
    }
    
    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .strengthTraining: return "figure.strengthtraining.functional"
        case .mixed: return "bolt.heart.fill"
        case .other: return "figure.run"
        }
    }
}

extension TrainingIntent {
    static var uiVisibleCases: [TrainingIntent] {
        [.zone2, .vo2Interval, .strength]
    }

    var localizedName: String {
        switch self {
        case .zone2: return "Zone 2"
        case .activityReview: return "Zone 2"
        case .vo2Interval: return "最大攝氧量 / 間歇"
        case .strength: return "肌力"
        }
    }
}

extension AnalysisVerdict {
    var localizedName: String {
        switch self {
        case .pass: return "達標"
        case .warning: return "警告"
        case .fail: return "未達標"
        }
    }
}

// MARK: - Cross-Platform SwiftUI View Extensions

extension View {
    @ViewBuilder
    func iosNavigationBarStyling() -> some View {
        #if os(iOS)
        self
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(PremiumColor.bgDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func iosDetailNavigationBarStyling() -> some View {
        #if os(iOS)
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(PremiumColor.bgDark, for: .navigationBar)
        #else
        self
        #endif
    }
}

// MARK: - Color Palette Constants

enum PremiumColor {
    static let bgDark = Color(red: 24 / 255, green: 26 / 255, blue: 32 / 255)
    static let cardBg = Color(red: 36 / 255, green: 40 / 255, blue: 49 / 255)
    static let border = Color.white.opacity(0.08)
    
    static let emerald = Color(red: 46 / 255, green: 204 / 255, blue: 113 / 255)
    static let gold = Color(red: 241 / 255, green: 196 / 255, blue: 15 / 255)
    static let redOrange = Color(red: 231 / 255, green: 76 / 255, blue: 60 / 255)
    static let neonPurple = Color(red: 155 / 255, green: 89 / 255, blue: 182 / 255)
    static let skyBlue = Color(red: 52 / 255, green: 152 / 255, blue: 219 / 255)
}

// MARK: - Views

struct WorkoutListView: View {
    @ObservedObject var viewModel: WorkoutListViewModel
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            ZStack {
                PremiumColor.bgDark.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    WorkoutSourceBannerView(
                        source: viewModel.currentSource,
                        statusMessage: viewModel.statusMessage,
                        isRefreshing: viewModel.isRefreshing,
                        isRequestingAuthorization: viewModel.isRequestingAuthorization,
                        canRequestHealthAccess: viewModel.canRequestHealthAccess,
                        canDisconnectStrava: viewModel.canDisconnectStrava,
                        onRequestHealthAccess: {
                            Task { await viewModel.requestHealthAccess() }
                        },
                        onConnectStrava: viewModel.canConnectStrava ? {
                            Task { await viewModel.connectStrava() }
                        } : nil,
                        onDisconnectStrava: viewModel.canDisconnectStrava ? {
                            Task { await viewModel.disconnectStrava() }
                        } : nil
                    )
                    
                    if viewModel.workouts.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(PremiumColor.skyBlue.gradient)
                            Text("沒有運動紀錄")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("請確認 Apple Health 授權或等待資料載入")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        List(selection: $viewModel.selectedWorkout) {
                            ForEach(viewModel.workouts, id: \.id) { workout in
                                Button {
                                    viewModel.selectWorkout(workout)
                                } label: {
                                    WorkoutRowView(
                                        workout: workout,
                                        result: viewModel.analysisResult(for: workout),
                                        evaluation: viewModel.evaluationResult(for: workout)
                                    )
                                }
                                .listRowBackground(PremiumColor.bgDark)
                                .listRowSeparator(.hidden)
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.plain)
                        .background(PremiumColor.bgDark)
                    }
                }
            }
            .navigationTitle("ZoneTruth")
            .iosNavigationBarStyling()
        } detail: {
            ZStack {
                PremiumColor.bgDark.ignoresSafeArea()
                
                if let workout = viewModel.selectedWorkout {
                    WorkoutDetailView(
                        workout: workout,
                        selectedIntent: viewModel.selectedIntent,
                        selectedIntentSource: viewModel.effectiveIntentSource(for: workout),
                        result: viewModel.analysisResult(for: workout),
                        evaluation: viewModel.evaluationResult(for: workout),
                        onIntentChanged: viewModel.updateIntent,
                        onApplyToSameWorkoutType: viewModel.applySelectedIntentToSameWorkoutType(scope:),
                        impactedCountForScope: viewModel.impactedCountForSelectedIntent(scope:),
                        zoneContextSummary: viewModel.analysisZoneContextSummary(for: workout),
                        classificationFeedbackRecorder: viewModel.classificationFeedbackRecorder(for: workout),
                        settingsManager: settingsManager
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(PremiumColor.neonPurple.gradient)
                        Text("請選擇一筆運動紀錄以檢視分析詳情")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(PremiumColor.skyBlue)
        .task {
            await viewModel.refreshWorkouts()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !viewModel.isRequestingAuthorization else { return }
            Task { await viewModel.refreshWorkouts() }
        }
        .onChange(of: settingsManager.defaultIntentOverrideSignature) { _, _ in
            viewModel.applyDefaultIntentOverridesToCurrentWorkouts()
        }
        .onChange(of: settingsManager.zoneProfileSignature) { _, _ in
            viewModel.refreshDerivedDataForCurrentPolicy()
        }
    }
}

struct WorkoutSourceBannerView: View {
    let source: WorkoutDataSource
    let statusMessage: String?
    let isRefreshing: Bool
    let isRequestingAuthorization: Bool
    let canRequestHealthAccess: Bool
    let canDisconnectStrava: Bool
    let onRequestHealthAccess: () -> Void
    var onConnectStrava: (() -> Void)? = nil
    var onDisconnectStrava: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(source == .mockSamples ? PremiumColor.gold : PremiumColor.emerald)
                    .frame(width: 8, height: 8)
                
                Text(source.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                Spacer()
                
                if isRefreshing || isRequestingAuthorization {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if canRequestHealthAccess {
                    Button(action: onRequestHealthAccess) {
                        HStack {
                            Image(systemName: "heart.text.square")
                            Text(isRequestingAuthorization ? "正在要求 Apple Health 授權..." : "要求 Apple Health 授權")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(PremiumColor.skyBlue.gradient)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isRequestingAuthorization || isRefreshing)
                }

                if let connectStrava = onConnectStrava {
                    Button {
                        connectStrava()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("連結 Strava")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .disabled(isRefreshing)
                }

                if canDisconnectStrava, let disconnectStrava = onDisconnectStrava {
                    Button {
                        disconnectStrava()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("中斷 Strava")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(PremiumColor.redOrange.opacity(0.15))
                        .foregroundColor(PremiumColor.redOrange)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(PremiumColor.redOrange.opacity(0.3), lineWidth: 1))
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .background(PremiumColor.cardBg.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct WorkoutRowView: View {
    let workout: WorkoutInput
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    var body: some View {
        HStack(spacing: 16) {
            // Icon Badge
            ZStack {
                Circle()
                    .fill(PremiumColor.cardBg.opacity(0.8))
                    .frame(width: 46, height: 46)
                Image(systemName: workout.workoutType.iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(workout.workoutType.localizedName)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(.white)

                    Text(workout.intentSource == .auto ? "自動" : "手動")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(intentSourceColor.opacity(0.18))
                        .foregroundStyle(intentSourceColor)
                        .clipShape(Capsule())

                    if let badge = sourceBadge {
                        Text(badge.label)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(badge.color.opacity(0.2))
                            .foregroundStyle(badge.color)
                            .clipShape(Capsule())
                    }
                }

                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Verdict status capsule
            HStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(.caption.bold())
                Text("\(evaluation.goalFitScore)%")
                    .font(.caption2.bold())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.45), lineWidth: 1))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PremiumColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private struct SourceBadge { let label: String; let color: Color }
    private var sourceBadge: SourceBadge? {
        switch workout.dataSource {
        case "strava":   return SourceBadge(label: "S", color: Color(red: 252/255, green: 76/255, blue: 2/255))
        case "healthkit": return SourceBadge(label: "HK", color: Color(red: 255/255, green: 60/255, blue: 120/255))
        default: return nil
        }
    }

    private var statusSymbol: String {
        switch result.verdict {
        case .pass: return "checkmark"
        case .warning: return "exclamationmark.triangle"
        case .fail: return "xmark"
        }
    }

    private var statusColor: Color {
        switch result.verdict {
        case .pass: return PremiumColor.emerald
        case .warning: return PremiumColor.gold
        case .fail: return PremiumColor.redOrange
        }
    }

    private var intentSourceColor: Color {
        workout.intentSource == .auto ? PremiumColor.skyBlue : PremiumColor.gold
    }
}

struct MetricDisclosureItem: Equatable {
    let title: String
    let status: String
    let summary: String
    let method: String
    let confidenceReason: String
    let validationHint: String?
}

enum MetricDisclosurePresenter {
    static func render(_ metadata: [TrainingMetricMetadata]) -> [MetricDisclosureItem] {
        metadata.map(render(_:))
    }

    static func render(_ metadata: TrainingMetricMetadata) -> MetricDisclosureItem {
        MetricDisclosureItem(
            title: metadata.claimProfile.displayName,
            status: status(for: metadata.claim.ceiling),
            summary: summary(for: metadata),
            method: "方法：\(methodLabel(for: metadata))",
            confidenceReason: confidenceReason(for: metadata),
            validationHint: metadata.recommendedValidation.map { "驗證方向：\(validationLabel($0))" }
        )
    }

    private static func status(for ceiling: TrainingMetricClaimCeiling) -> String {
        switch ceiling {
        case .measuredIfDirect:
            return "直接資料"
        case .estimateOnly:
            return "估算參考"
        case .startingPointOnly:
            return "分析起點"
        case .unsupported:
            return "僅供參考"
        }
    }

    private static func summary(for metadata: TrainingMetricMetadata) -> String {
        switch metadata.claimProfile.kind {
        case .vo2MaxEstimate:
            return "這是裝置提供的最大攝氧量參考值，適合追蹤變化，不當成實驗室實測。"
        case .heartRateRecoveryContext:
            return "這裡用來看運動後心率回落情況，能幫助理解恢復，但不單獨下結論。"
        case .runningPowerContext:
            return "這裡補充跑步時的外部負荷，幫助判讀強度是否穩定。"
        case .cyclingPowerContext:
            return "這裡補充騎乘時的外部負荷，幫助判讀強度是否穩定。"
        case .workoutRouteContext:
            return "這裡補充路線與地形背景，避免把環境影響誤認成身體狀態變化。"
        case .externalLoadDecouplingContext:
            return "這裡看前後段心率和負荷是否大致一致，可作為穩定度的輔助線索。"
        case .vo2IntervalPattern:
            return "這裡描述的是高強度型態，不代表已直接量到最大攝氧量。"
        case .zone2ThresholdRange:
            return "這裡是本次分析採用的心率範圍，適合當起點，不代表已做閾值測試。"
        case .strengthMeasurement:
            return "這裡是帶有動作脈絡的肌力數值，較適合拿來追蹤同動作變化。"
        case .strengthSessionPattern:
            return "這裡描述的是肌力訓練節奏，不把心率型態直接當成最大肌力。"
        case .genericObservation:
            return "這裡只整理目前看得到的資料，不延伸成過度確定的結論。"
        }
    }

    private static func methodLabel(for metadata: TrainingMetricMetadata) -> String {
        if metadata.metric == .externalLoadDecoupling {
            return metadata.method.name
        }
        switch metadata.method.source {
        case .policyZoneBounds:
            return "目前設定的心率界線"
        case .heartRatePattern:
            return "心率區間與型態觀察"
        case .cpet:
            return "CPET / GXT 氣體分析"
        case .lactateTest:
            return "乳酸閾值測試"
        case .ventilatoryThreshold:
            return "換氣閾值測試"
        case .apple:
            return "Apple 產品估算"
        case .garmin:
            return "Garmin 產品估算"
        case .firstbeat:
            return "Firstbeat 方法參考"
        case .runningHRSpeed:
            return "跑步心率與速度估算"
        case .cyclingPowerHR:
            return "自行車功率與心率估算"
        case .workoutRoute:
            return metadata.method.name
        case .hrDrift:
            return "心率飄移觀察"
        case .hrvThreshold:
            return "HRV 閾值估算"
        case .talkTest:
            return "Talk test / RPE 線索"
        case .percentHRMax:
            return "最大心率百分比公式"
        case .e1RM:
            return "估算最大負重"
        case .direct1RM:
            return "標準化最大負重測試"
        case .gripStrength:
            return "握力測試"
        case .userInput:
            return "使用者輸入"
        case .unknown:
            return metadata.method.name
        }
    }

    private static func confidenceReason(for metadata: TrainingMetricMetadata) -> String {
        let level = confidenceLabel(for: metadata.confidence.level)
        let basis = basisLabel(metadata.confidence.basis)
        return "可靠度：\(level)。\(basis) \(profileDisclosureLabel(for: metadata.claimProfile.kind))"
    }

    private static func confidenceLabel(for level: TrainingMetricConfidenceLevel) -> String {
        switch level {
        case .high:
            return "高"
        case .medium:
            return "中"
        case .mediumLow:
            return "中低"
        case .low:
            return "低"
        case .unknown:
            return "未知"
        }
    }

    private static func basisLabel(_ basis: String) -> String {
        if basis.localizedCaseInsensitiveContains("Direct 1RM strength metric") {
            return "這是帶有動作脈絡的直接 1RM 肌力資料。"
        }
        if basis.localizedCaseInsensitiveContains("Estimated 1RM strength metric") {
            return "這是由負重與次數脈絡匯入的 e1RM 肌力估算。"
        }
        if basis.localizedCaseInsensitiveContains("Grip strength metric") {
            return "這是握力指標，可作為健康相關 proxy，不等同全身肌力。"
        }
        if basis.localizedCaseInsensitiveContains("limited method provenance") &&
            basis.localizedCaseInsensitiveContains("Strength metric") {
            return "肌力來源方法資訊有限，僅能作為低信心觀察。"
        }
        if basis.localizedCaseInsensitiveContains("Direct lab VO2 max source") {
            return "來源標示為實驗室氣體分析資料。"
        }
        if basis.localizedCaseInsensitiveContains("Structured field VO2 max estimate") {
            return "這是依運動資料推得的參考值，還沒有用實驗室氣體交換資料確認。"
        }
        if basis.localizedCaseInsensitiveContains("Product VO2 max estimate") {
            return "這是產品來源估算，未直接使用氣體交換資料。"
        }
        if basis.localizedCaseInsensitiveContains("Product heart-rate recovery context") {
            return "這是產品來源的 1 分鐘心率恢復脈絡，僅作為恢復觀察。"
        }
        if basis.localizedCaseInsensitiveContains("Derived post-workout heart-rate recovery context") {
            return "這是由運動結束後的心率點推得的 1 分鐘回復脈絡，僅作為恢復觀察。"
        }
        if basis.localizedCaseInsensitiveContains("Running power context was imported") {
            return "這是匯入的跑步功率資料，可補充外部負荷變化。"
        }
        if basis.localizedCaseInsensitiveContains("Cycling power context was imported") {
            return "這是匯入的自行車功率資料，可補充外部負荷變化。"
        }
        if basis.localizedCaseInsensitiveContains("Workout route context was imported") {
            return "這是匯入的路線與地形脈絡，可作為戶外訓練情境輔助。"
        }
        if basis.localizedCaseInsensitiveContains("External-load decoupling context was imported") {
            return "這是前後半段心率與功率比例變化摘要，可作為外部負荷是否穩定一致的輔助線索。"
        }
        if basis.localizedCaseInsensitiveContains("limited method provenance") {
            return "來源方法資訊有限，僅能作為低信心估算。"
        }
        if basis.localizedCaseInsensitiveContains("not estimate VO2 max") ||
            basis.localizedCaseInsensitiveContains("does not estimate VO2 max") {
            return "目前只描述間歇型態，尚未推估最大攝氧量數值。"
        }
        if basis.localizedCaseInsensitiveContains("not LT1") ||
            basis.localizedCaseInsensitiveContains("not LT1 or VT1") {
            return "目前使用設定界線作為分析起點，還沒有用閾值測試確認。"
        }
        if basis.localizedCaseInsensitiveContains("does not measure force") ||
            basis.localizedCaseInsensitiveContains("1RM") {
            return "目前主要描述訓練節奏，還沒有完整負重或力輸出資料。"
        }
        return basis
    }

    private static func validationLabel(_ value: String) -> String {
        if value.localizedCaseInsensitiveContains("LT1") ||
            value.localizedCaseInsensitiveContains("VT1") {
            return "若想把有氧範圍抓得更準，可再做乳酸或換氣閾值測試。"
        }
        if value.localizedCaseInsensitiveContains("CPET") {
            return "若想更精準了解最大攝氧量，可再做實驗室氣體分析測試。"
        }
        if value.localizedCaseInsensitiveContains("1RM") ||
            value.localizedCaseInsensitiveContains("force") {
            return "若想更準確追蹤肌力，可補上標準化負重、次數或力/速度測試。"
        }
        if value.localizedCaseInsensitiveContains("recovery") {
            return "若想更完整看恢復狀態，還需要搭配固定流程或更完整測試。"
        }
        if value.localizedCaseInsensitiveContains("metabolic precision") ||
            value.localizedCaseInsensitiveContains("threshold") {
            return "若想更精準看代謝或閾值，仍需搭配標準化閾值或實驗室測試。"
        }
        return value
    }

    private static func profileDisclosureLabel(for kind: TrainingMetricClaimProfileKind) -> String {
        switch kind {
        case .vo2MaxEstimate:
            return "這個數值適合看趨勢，不直接當成實驗室真值。"
        case .heartRateRecoveryContext:
            return "這裡只補充恢復線索，不延伸成完整恢復診斷。"
        case .runningPowerContext:
            return "這裡只補充跑步外部負荷，不等同閾值或最大攝氧量測量。"
        case .cyclingPowerContext:
            return "這裡只補充騎乘外部負荷，不等同閾值或最大攝氧量測量。"
        case .workoutRouteContext:
            return "這裡只補充路線與地形背景，不等同閾值或最大攝氧量測量。"
        case .externalLoadDecouplingContext:
            return "這裡只補充前後段一致性線索，不等同閾值或最大攝氧量測量。"
        case .vo2IntervalPattern:
            return "這裡只描述高強度型態，不代表已直接量到最大攝氧量。"
        case .zone2ThresholdRange:
            return "這裡先用可得資料設定有氧範圍，若想更準仍需閾值測試。"
        case .strengthMeasurement:
            return "肌力數值要和動作、負重、次數一起看，才比較有比較價值。"
        case .strengthSessionPattern:
            return "這裡只描述訓練節奏，不能直接代表最大肌力或力輸出。"
        case .genericObservation:
            return "這裡只整理可觀測資料，不延伸成未驗證結論。"
        }
    }
}

struct MetricDisclosureCardView: View {
    let metadata: [TrainingMetricMetadata]

    private var items: [MetricDisclosureItem] {
        MetricDisclosurePresenter.render(metadata)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("這次判讀怎麼來", systemImage: "checklist.checked")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(items, id: \.title) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                            Text(item.status)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(PremiumColor.skyBlue.opacity(0.16))
                                .foregroundStyle(PremiumColor.skyBlue)
                                .clipShape(Capsule())
                        }
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        DisclosureGroup("查看詳細說明") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.method)
                                Text(item.confidenceReason)
                                if let validationHint = item.validationHint {
                                    Text(validationHint)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.top, 6)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
    }
}

enum WorkoutDetailInformationArchitecture {
    static let header = "活動摘要"
    static let primaryResult = "本次結論"
    static let evidenceSummary = "判讀依據"
    static let heartRateContext = "本次使用的心率範圍"
    static let detailDisclosure = "更多內容與詳細數據"
    static let methodSettings = "本次分析設定"
    static let classificationConfidence = "判讀信心"
    static let technicalClassificationConfidence = "分類信心"
    static let technicalEvaluationConfidence = "評估信心"
    static let classificationFeedback = "這次判讀準確嗎？"
    static let feedbackSuggestedMode = "比較像"

    static let userFacingForbiddenLabels = [
        "本次意圖",
        "目的符合度",
        "舊版判定"
    ]

    static let heroSummaryLabels = [
        classificationConfidence
    ]

    static let technicalDetailLabels = [
        technicalClassificationConfidence,
        technicalEvaluationConfidence
    ]

    static let primaryVisibleLabels = [
        header,
        primaryResult,
        evidenceSummary,
        heartRateContext,
        detailDisclosure,
        classificationConfidence,
        classificationFeedback
    ]

    static let settingsOnlyLabels = [
        "Resting HR",
        "靜息心率",
        "偏移",
        "依 Resting HR 產生建議",
        "分析策略設定",
        methodSettings
    ]

    static func shouldShowVO2MaxMetric(on workoutType: WorkoutType) -> Bool {
        workoutType != .strengthTraining
    }
}

enum TrainingModeFeedbackPresenter {
    static let ratingOptions: [TrainingClassificationFeedbackRating] = [
        .accurate,
        .somewhatSimilar,
        .inaccurate
    ]

    static let suggestedModeOptions: [TrainingMode] = [
        .zone2,
        .vo2Stimulus,
        .strengthPattern,
        .conditioningLike,
        .generalLowIntensity,
        .mixed
    ]

    static func label(for rating: TrainingClassificationFeedbackRating) -> String {
        switch rating {
        case .accurate:
            return "準確"
        case .somewhatSimilar:
            return "有點像"
        case .inaccurate:
            return "不準"
        }
    }

    static func label(for mode: TrainingMode) -> String {
        switch mode {
        case .zone2:
            return "Zone 2"
        case .vo2Stimulus:
            return "VO2 刺激"
        case .strengthPattern:
            return "肌力"
        case .conditioningLike:
            return "高密度循環"
        case .generalLowIntensity:
            return "一般低強度"
        case .mixed:
            return "混合型態"
        case .insufficientData:
            return "資料不足"
        }
    }
}

enum WorkoutClassificationFeedbackRecordingResult: Equatable {
    case saved
    case duplicate
    case incomplete
}

struct WorkoutClassificationFeedbackRecorder {
    let workoutID: UUID
    let classification: TrainingClassification
    let store: any TrainingClassificationFeedbackStoring
    let makeRecordID: () -> UUID
    let now: () -> Date

    init(
        workoutID: UUID,
        classification: TrainingClassification,
        store: any TrainingClassificationFeedbackStoring,
        makeRecordID: @escaping () -> UUID = { UUID() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.workoutID = workoutID
        self.classification = classification
        self.store = store
        self.makeRecordID = makeRecordID
        self.now = now
    }

    @discardableResult
    func record(
        rating: TrainingClassificationFeedbackRating?,
        suggestedMode: TrainingMode?
    ) -> WorkoutClassificationFeedbackRecordingResult {
        guard let rating else { return .incomplete }
        if (rating == .somewhatSimilar || rating == .inaccurate), suggestedMode == nil {
            return .incomplete
        }
        let normalizedSuggestedMode = rating == .accurate ? nil : suggestedMode
        let isDuplicate = store.records(for: workoutID).contains { record in
            record.feedback.rating == rating &&
            record.feedback.userSuggestedMode == normalizedSuggestedMode
        }
        if isDuplicate {
            return .duplicate
        }

        let feedback = TrainingClassificationFeedback(
            workoutID: workoutID,
            recordedAt: now(),
            originalClassification: classification,
            rating: rating,
            userSuggestedMode: normalizedSuggestedMode
        )
        store.save(
            TrainingClassificationFeedbackRecord(
                id: makeRecordID(),
                feedback: feedback
            )
        )
        return .saved
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent
    let selectedIntentSource: IntentSource
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation
    let onIntentChanged: (TrainingIntent) -> Void
    let onApplyToSameWorkoutType: (IntentApplyScope) -> Void
    let impactedCountForScope: (IntentApplyScope) -> Int
    let zoneContextSummary: String
    let classificationFeedbackRecorder: WorkoutClassificationFeedbackRecorder?
    @ObservedObject var settingsManager: SettingsManager
    @State private var showDetailedData = false
    @State private var feedbackRating: TrainingClassificationFeedbackRating?
    @State private var feedbackSuggestedMode: TrainingMode?
    @State private var feedbackRecordingResult: WorkoutClassificationFeedbackRecordingResult?

    init(
        workout: WorkoutInput,
        selectedIntent: TrainingIntent,
        selectedIntentSource: IntentSource,
        result: AnalysisResult,
        evaluation: WorkoutEvaluation,
        onIntentChanged: @escaping (TrainingIntent) -> Void,
        onApplyToSameWorkoutType: @escaping (IntentApplyScope) -> Void,
        impactedCountForScope: @escaping (IntentApplyScope) -> Int,
        zoneContextSummary: String,
        classificationFeedbackRecorder: WorkoutClassificationFeedbackRecorder? = nil,
        settingsManager: SettingsManager
    ) {
        self.workout = workout
        self.selectedIntent = selectedIntent
        self.selectedIntentSource = selectedIntentSource
        self.result = result
        self.evaluation = evaluation
        self.onIntentChanged = onIntentChanged
        self.onApplyToSameWorkoutType = onApplyToSameWorkoutType
        self.impactedCountForScope = impactedCountForScope
        self.zoneContextSummary = zoneContextSummary
        self.classificationFeedbackRecorder = classificationFeedbackRecorder
        self.settingsManager = settingsManager
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkoutDetailHeaderView(workout: workout, selectedIntent: selectedIntent)
                HeroDecisionCardView(workout: workout, result: result, evaluation: evaluation)
                EvidenceSummarySectionView(result: result, evaluation: evaluation)
                TrainingClassificationFeedbackControl(
                    rating: $feedbackRating,
                    suggestedMode: $feedbackSuggestedMode,
                    recordingResult: feedbackRecordingResult,
                    onFeedbackChanged: { rating, suggestedMode in
                        let result = classificationFeedbackRecorder?.record(
                            rating: rating,
                            suggestedMode: suggestedMode
                        ) ?? .incomplete
                        feedbackRecordingResult = result
                        return result
                    }
                )
                AnalysisZoneContextCard(summary: zoneContextSummary)

                DisclosureGroup(isExpanded: $showDetailedData) {
                    VStack(alignment: .leading, spacing: 18) {
                        MetricDisclosureCardView(metadata: result.metricMetadata)

                        IntentPickerView(
                            selectedIntent: selectedIntent,
                            selectedIntentSource: selectedIntentSource,
                            onIntentChanged: onIntentChanged,
                            onApplyToSameWorkoutType: onApplyToSameWorkoutType,
                            impactedCountForScope: impactedCountForScope
                        )

                        MetricsGridSectionView(workout: workout, result: result, evaluation: evaluation)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("心率區間分佈", systemImage: "chart.bar.xaxis")
                                .font(.headline)
                                .foregroundStyle(.white)
                            ZoneDistributionChartView(distribution: result.zoneDistribution)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))

                        if !result.reasons.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("分析觀察依據", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(PremiumColor.skyBlue)
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(result.reasons, id: \.self) { reason in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•").foregroundStyle(PremiumColor.skyBlue)
                                            Text(reason).font(.caption).foregroundStyle(.white.opacity(0.85)).lineSpacing(4)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PremiumColor.skyBlue.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(PremiumColor.skyBlue.opacity(0.15), lineWidth: 1))
                        }

                        if !result.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("可參考的下一步", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(PremiumColor.emerald)
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(result.recommendations, id: \.self) { rec in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("💡")
                                            Text(rec).font(.caption).foregroundStyle(.white.opacity(0.85)).lineSpacing(4)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PremiumColor.emerald.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(PremiumColor.emerald.opacity(0.15), lineWidth: 1))
                        }

                        DisclosureGroup("原始數據與技術細節") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(WorkoutDetailInformationArchitecture.technicalClassificationConfidence)：\(evaluation.classificationConfidence)%")
                                Text("\(WorkoutDetailInformationArchitecture.technicalEvaluationConfidence)：\(evaluation.evaluationConfidence)%")
                                ForEach(evaluation.secondarySignals, id: \.self) { signal in
                                    Text("• \(signal)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 8)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)

                        DisclosureGroup(WorkoutDetailInformationArchitecture.methodSettings) {
                            SettingsView(settingsManager: settingsManager)
                                .padding(.top, 8)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                } label: {
                    Label(WorkoutDetailInformationArchitecture.detailDisclosure, systemImage: "chart.bar.doc.horizontal")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(PremiumColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumColor.border, lineWidth: 1))
                .tint(.white)

            }
            .padding(20)
        }
        .background(PremiumColor.bgDark)
        .navigationTitle("運動紀錄詳情")
        .iosDetailNavigationBarStyling()
    }
}

struct WorkoutDetailHeaderView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WorkoutDetailInformationArchitecture.header)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.62))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workout.workoutType.iconName)
                    .font(.title3)
                    .foregroundStyle(PremiumColor.skyBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.workoutType.localizedName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - Phase D: Hero Decision Card (主決策卡)

struct HeroDecisionCardView: View {
    let workout: WorkoutInput
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WorkoutDetailInformationArchitecture.primaryResult)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 8) {
                Image(systemName: "figure.run.square.stack")
                    .font(.subheadline.bold())
                Text(evaluation.trainingTendency)
                    .font(.headline.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PremiumColor.skyBlue.opacity(0.15))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                summaryPill(
                    title: WorkoutDetailInformationArchitecture.classificationConfidence,
                    value: reliabilitySummary,
                    color: reliabilityColor
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .foregroundStyle(PremiumColor.emerald)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("後續觀察點")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Text(evaluation.nextAction)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PremiumColor.emerald.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(PremiumColor.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    private var reliabilitySummary: String {
        switch evaluation.evaluationConfidence {
        case 80...:
            return "資料足夠"
        case 60..<80:
            return "可作參考"
        default:
            return "資料有限"
        }
    }

    private var reliabilityColor: Color {
        switch evaluation.evaluationConfidence {
        case 80...: return PremiumColor.emerald
        case 60..<80: return PremiumColor.gold
        default: return PremiumColor.redOrange
        }
    }

    @ViewBuilder
    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AnalysisZoneContextCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(WorkoutDetailInformationArchitecture.heartRateContext, systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.white)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Text("這裡只說明這次分析實際用到的範圍與來源，避免把結果誤解成固定標準。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - Evidence Summary Section (主要依據，永遠可見)

struct EvidenceSummarySectionView: View {
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(WorkoutDetailInformationArchitecture.evidenceSummary, systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                EvidenceSignalRow(title: "節奏", value: rhythmSummary, color: PremiumColor.emerald)
                EvidenceSignalRow(title: "心率", value: heartRateSummary, color: PremiumColor.skyBlue)
                EvidenceSignalRow(title: "資料品質", value: dataCoverageSummary, color: dataCoverageColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private var rhythmSummary: String {
        evaluation.keyFindings.first ?? evaluation.trainingTendency
    }

    private var heartRateSummary: String {
        if let driftRatio = result.driftRatio {
            let percentage = driftRatio * 100
            if abs(percentage) < 5 {
                return "前後段心率大致穩定"
            }
            return "前後段心率約 \(String(format: "%+.1f%%", percentage)) 變化"
        }
        if let stability = result.stabilityStandardDeviation {
            return "心率標準差約 \(String(format: "%.1f bpm", stability))"
        }
        return "心率樣本已納入判讀"
    }

    private var dataCoverageSummary: String {
        switch evaluation.evaluationConfidence {
        case 80...:
            return "資料足夠"
        case 60..<80:
            return "可參考"
        default:
            return "資料有限"
        }
    }

    private var dataCoverageColor: Color {
        switch evaluation.evaluationConfidence {
        case 80...: return PremiumColor.emerald
        case 60..<80: return PremiumColor.gold
        default: return PremiumColor.redOrange
        }
    }
}

struct EvidenceSignalRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.68))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TrainingClassificationFeedbackControl: View {
    @Binding var rating: TrainingClassificationFeedbackRating?
    @Binding var suggestedMode: TrainingMode?
    let recordingResult: WorkoutClassificationFeedbackRecordingResult?
    let onFeedbackChanged: (TrainingClassificationFeedbackRating?, TrainingMode?) -> WorkoutClassificationFeedbackRecordingResult

    init(
        rating: Binding<TrainingClassificationFeedbackRating?>,
        suggestedMode: Binding<TrainingMode?>,
        recordingResult: WorkoutClassificationFeedbackRecordingResult? = nil,
        onFeedbackChanged: @escaping (TrainingClassificationFeedbackRating?, TrainingMode?) -> WorkoutClassificationFeedbackRecordingResult = { _, _ in .incomplete }
    ) {
        self._rating = rating
        self._suggestedMode = suggestedMode
        self.recordingResult = recordingResult
        self.onFeedbackChanged = onFeedbackChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(WorkoutDetailInformationArchitecture.classificationFeedback, systemImage: "hand.thumbsup")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                ForEach(TrainingModeFeedbackPresenter.ratingOptions, id: \.self) { option in
                    Button {
                        rating = option
                        if option == .accurate {
                            suggestedMode = nil
                        }
                        _ = onFeedbackChanged(rating, suggestedMode)
                    } label: {
                        Text(TrainingModeFeedbackPresenter.label(for: option))
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(feedbackRatingColor(option).opacity(rating == option ? 0.22 : 0.08))
                            .foregroundStyle(rating == option ? .white : .white.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(feedbackRatingColor(option).opacity(rating == option ? 0.65 : 0.20), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if rating == .somewhatSimilar || rating == .inaccurate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(WorkoutDetailInformationArchitecture.feedbackSuggestedMode)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.68))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                        ForEach(TrainingModeFeedbackPresenter.suggestedModeOptions, id: \.self) { mode in
                            Button {
                                suggestedMode = mode
                                _ = onFeedbackChanged(rating, suggestedMode)
                            } label: {
                                Text(TrainingModeFeedbackPresenter.label(for: mode))
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)
                                    .background(PremiumColor.skyBlue.opacity(suggestedMode == mode ? 0.22 : 0.07))
                                    .foregroundStyle(suggestedMode == mode ? .white : .white.opacity(0.78))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(PremiumColor.skyBlue.opacity(suggestedMode == mode ? 0.62 : 0.18), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(recordingStatusText)
                .font(.caption2)
                .foregroundStyle(recordingStatusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func feedbackRatingColor(_ option: TrainingClassificationFeedbackRating) -> Color {
        switch option {
        case .accurate:
            return PremiumColor.emerald
        case .somewhatSimilar:
            return PremiumColor.gold
        case .inaccurate:
            return PremiumColor.redOrange
        }
    }

    private var recordingStatusText: String {
        switch recordingResult {
        case .saved:
            return "已保存這次回饋。"
        case .duplicate:
            return "這次回饋已保存，沒有新增重複紀錄。"
        case .incomplete:
            return "請先選擇比較像的訓練型態，才會保存回饋。"
        case nil:
            return "選擇後會保存為回饋紀錄，不會改變原始活動資料。"
        }
    }

    private var recordingStatusColor: Color {
        switch recordingResult {
        case .saved, .duplicate:
            return PremiumColor.emerald.opacity(0.9)
        case .incomplete:
            return PremiumColor.gold.opacity(0.9)
        case nil:
            return .secondary
        }
    }
}

// MARK: - Metrics Grid Section (移入詳細數據區塊)

struct MetricsGridSectionView: View {
    let workout: WorkoutInput
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricGridCell(icon: "clock.fill", color: PremiumColor.skyBlue, title: "持續時間",
                           value: "\(Int(workout.durationSeconds / 60)) 分鐘")
            MetricGridCell(icon: "waveform.path.ecg", color: .red, title: "心率樣本",
                           value: "\(workout.heartRateSamples.count) 筆")
            if let stability = result.stabilityStandardDeviation {
                MetricGridCell(icon: "waveform.path.ecg.rectangle", color: PremiumColor.gold,
                               title: "心率穩定度 (標差)", value: String(format: "%.1f bpm", stability))
            }
            if let drift = result.driftRatio {
                MetricGridCell(icon: "chart.xyaxis.line", color: PremiumColor.neonPurple,
                               title: "心率飄移", value: String(format: "%.1f%%", drift * 100))
            }
            if WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: workout.workoutType),
               let vo2MaxEstimate = workout.vo2MaxEstimate {
                MetricGridCell(icon: "speedometer", color: PremiumColor.emerald,
                               title: "VO2 max 估算",
                               value: String(format: "%.1f ml/kg/min", vo2MaxEstimate.value))
            }
            if let recovery = workout.heartRateRecoveryOneMinute {
                MetricGridCell(icon: "heart.circle.fill", color: PremiumColor.skyBlue,
                               title: "1 分鐘心率恢復",
                               value: String(format: "%.0f bpm", recovery.value))
            }
            if let runningPower = workout.runningPower {
                MetricGridCell(icon: "bolt.fill", color: PremiumColor.gold,
                               title: "跑步功率",
                               value: String(format: "%.0f W", runningPower.averageWatts))
            }
            if let cyclingPower = workout.cyclingPower {
                MetricGridCell(icon: "bolt.badge.a.fill", color: PremiumColor.emerald,
                               title: "自行車功率",
                               value: String(format: "%.0f W", cyclingPower.averageWatts))
            }
            if let route = workout.workoutRoute {
                MetricGridCell(icon: "map.fill", color: PremiumColor.neonPurple,
                               title: "路線脈絡",
                               value: routeValue(route))
            }
            if let decoupling = workout.externalLoadDecoupling {
                MetricGridCell(icon: "link", color: PremiumColor.skyBlue,
                               title: "負荷一致性",
                               value: decouplingValue(decoupling))
            }
            if let strengthMetric = workout.strengthMetrics.first {
                MetricGridCell(icon: "dumbbell.fill", color: PremiumColor.gold,
                               title: strengthMetricTitle(strengthMetric),
                               value: strengthMetricValue(strengthMetric))
            }
        }
    }

    private func strengthMetricTitle(_ metric: StrengthMetric) -> String {
        switch metric.source {
        case .direct1RM:
            return "\(metric.exerciseName) 1RM"
        case .e1RM:
            return "\(metric.exerciseName) e1RM"
        default:
            return "\(metric.exerciseName) 肌力"
        }
    }

    private func strengthMetricValue(_ metric: StrengthMetric) -> String {
        String(format: "%.1f %@", metric.value, metric.unit)
    }

    private func routeValue(_ route: WorkoutRouteObservation) -> String {
        if let elevationGain = route.elevationGainMeters {
            return "\(route.pointCount) 點 / +\(Int(elevationGain.rounded())) m"
        }
        return "\(route.pointCount) 點"
    }

    private func decouplingValue(_ observation: ExternalLoadDecouplingObservation) -> String {
        let ratio = observation.decouplingRatio * 100
        let prefix = abs(ratio) < 5 ? "穩定" : abs(ratio) <= 8 ? "輕微變化" : "變化明顯"
        return "\(prefix) \(String(format: "%+.1f%%", ratio))"
    }
}

// MARK: - Confidence radial gauge view

struct ConfidenceRingView: View {
    let confidence: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0.0, to: CGFloat(confidence))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(Angle(degrees: -90))
                .animation(.easeOut, value: confidence)
            VStack(spacing: 2) {
                Text("\(Int((confidence * 100).rounded()))%")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                Text("信心")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
    }
}

struct SummaryCardView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Title and Confidence
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: workout.workoutType.iconName)
                            .font(.headline)
                            .foregroundStyle(PremiumColor.skyBlue)
                        
                        Text(workout.workoutType.localizedName)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    
                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                ConfidenceRingView(
                    confidence: Double(evaluation.evaluationConfidence) / 100.0,
                    color: colorForVerdict(result.verdict)
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            // Coach summary banner
            HStack(spacing: 8) {
                Image(systemName: "figure.run.square.stack")
                    .font(.subheadline.bold())
                Text(evaluation.trainingTendency)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(PremiumColor.skyBlue.opacity(0.15))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("建議：\(evaluation.nextAction)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
            
            // Grid of Metrics
            LazyVGrid(columns: columns, spacing: 12) {
                MetricGridCell(
                    icon: "clock.fill",
                    color: PremiumColor.skyBlue,
                    title: "持續時間",
                    value: "\(Int(workout.durationSeconds / 60)) 分鐘"
                )
                
                MetricGridCell(
                    icon: "waveform.path.ecg",
                    color: .red,
                    title: "心率樣本",
                    value: "\(workout.heartRateSamples.count) 筆"
                )
                
                if let stability = result.stabilityStandardDeviation {
                    MetricGridCell(
                        icon: "waveform.path.ecg.rectangle",
                        color: PremiumColor.gold,
                        title: "心率穩定度 (標差)",
                        value: String(format: "%.1f bpm", stability)
                    )
                }
                
                if let drift = result.driftRatio {
                    MetricGridCell(
                        icon: "chart.xyaxis.line",
                        color: PremiumColor.neonPurple,
                        title: "心率飄移",
                        value: String(format: "%.1f%%", drift * 100)
                    )
                }

                if WorkoutDetailInformationArchitecture.shouldShowVO2MaxMetric(on: workout.workoutType),
                   let vo2MaxEstimate = workout.vo2MaxEstimate {
                    MetricGridCell(
                        icon: "speedometer",
                        color: PremiumColor.emerald,
                        title: "VO2 max 估算",
                        value: String(format: "%.1f ml/kg/min", vo2MaxEstimate.value)
                    )
                }

                if let recovery = workout.heartRateRecoveryOneMinute {
                    MetricGridCell(
                        icon: "heart.circle.fill",
                        color: PremiumColor.skyBlue,
                        title: "1 分鐘心率恢復",
                        value: String(format: "%.0f bpm", recovery.value)
                    )
                }

                if let runningPower = workout.runningPower {
                    MetricGridCell(
                        icon: "bolt.fill",
                        color: PremiumColor.gold,
                        title: "跑步功率",
                        value: String(format: "%.0f W", runningPower.averageWatts)
                    )
                }

                if let cyclingPower = workout.cyclingPower {
                    MetricGridCell(
                        icon: "bolt.badge.a.fill",
                        color: PremiumColor.emerald,
                        title: "自行車功率",
                        value: String(format: "%.0f W", cyclingPower.averageWatts)
                    )
                }

                if let route = workout.workoutRoute {
                    MetricGridCell(
                        icon: "map.fill",
                        color: PremiumColor.neonPurple,
                        title: "路線脈絡",
                        value: routeValue(route)
                    )
                }

                if let decoupling = workout.externalLoadDecoupling {
                    MetricGridCell(
                        icon: "link",
                        color: PremiumColor.skyBlue,
                        title: "負荷一致性",
                        value: decouplingValue(decoupling)
                    )
                }

                if let strengthMetric = workout.strengthMetrics.first {
                    MetricGridCell(
                        icon: "dumbbell.fill",
                        color: PremiumColor.gold,
                        title: strengthMetricTitle(strengthMetric),
                        value: strengthMetricValue(strengthMetric)
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(PremiumColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
    }

    private func colorForVerdict(_ verdict: AnalysisVerdict) -> Color {
        switch verdict {
        case .pass: return PremiumColor.emerald
        case .warning: return PremiumColor.gold
        case .fail: return PremiumColor.redOrange
        }
    }

    private func strengthMetricTitle(_ metric: StrengthMetric) -> String {
        switch metric.source {
        case .direct1RM:
            return "\(metric.exerciseName) 1RM"
        case .e1RM:
            return "\(metric.exerciseName) e1RM"
        default:
            return "\(metric.exerciseName) 肌力"
        }
    }

    private func strengthMetricValue(_ metric: StrengthMetric) -> String {
        String(format: "%.1f %@", metric.value, metric.unit)
    }

    private func routeValue(_ route: WorkoutRouteObservation) -> String {
        if let elevationGain = route.elevationGainMeters {
            return "\(route.pointCount) 點 / +\(Int(elevationGain.rounded())) m"
        }
        return "\(route.pointCount) 點"
    }

    private func decouplingValue(_ observation: ExternalLoadDecouplingObservation) -> String {
        let ratio = observation.decouplingRatio * 100
        let prefix = abs(ratio) < 5 ? "穩定" : abs(ratio) <= 8 ? "輕微變化" : "變化明顯"
        return "\(prefix) \(String(format: "%+.1f%%", ratio))"
    }
}

struct MetricGridCell: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

struct IntentPickerView: View {
    let selectedIntent: TrainingIntent
    let selectedIntentSource: IntentSource
    let onIntentChanged: (TrainingIntent) -> Void
    let onApplyToSameWorkoutType: (IntentApplyScope) -> Void
    let impactedCountForScope: (IntentApplyScope) -> Int
    @State private var showApplyScopeDialog = false
    @State private var pendingScope: IntentApplyScope?
    @State private var showApplyConfirmDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("設定訓練目標")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text(selectedIntentSource == .auto ? "自動判定" : "手動設定")
                    .font(.caption.bold())
                    .foregroundStyle(selectedIntentSource == .auto ? PremiumColor.skyBlue : PremiumColor.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((selectedIntentSource == .auto ? PremiumColor.skyBlue : PremiumColor.gold).opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Picker(
                "目標",
                selection: Binding(
                    get: {
                        TrainingIntent.uiVisibleCases.contains(selectedIntent) ? selectedIntent : .zone2
                    },
                    set: { onIntentChanged($0) }
                )
            ) {
                ForEach(TrainingIntent.uiVisibleCases, id: \.self) { intent in
                    Text(intent.localizedName).tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(PremiumColor.skyBlue)

            Button {
                showApplyScopeDialog = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("套用到同類型運動")
                }
                .font(.caption.bold())
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(PremiumColor.skyBlue.opacity(0.15))
                .foregroundStyle(PremiumColor.skyBlue)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(PremiumColor.skyBlue.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .confirmationDialog("選擇套用範圍", isPresented: $showApplyScopeDialog, titleVisibility: .visible) {
                ForEach(IntentApplyScope.allCases) { scope in
                    let count = impactedCountForScope(scope)
                    Button(scopeLabel(scope, count: count)) {
                        pendingScope = scope
                        showApplyConfirmDialog = true
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("確認套用目標", isPresented: $showApplyConfirmDialog, titleVisibility: .visible) {
                if let scope = pendingScope {
                    let count = impactedCountForScope(scope)
                    Button("套用（\(count) 筆）") {
                        onApplyToSameWorkoutType(scope)
                        pendingScope = nil
                    }
                }
                Button("取消", role: .cancel) {
                    pendingScope = nil
                }
            } message: {
                if let scope = pendingScope {
                    Text("將目前目標套用到\(scopeReadable(scope))，預計影響 \(impactedCountForScope(scope)) 筆。")
                }
            }
        }
        .padding(12)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
    }

    private func scopeLabel(_ scope: IntentApplyScope, count: Int) -> String {
        "\(scopeReadable(scope))（\(count) 筆）"
    }

    private func scopeReadable(_ scope: IntentApplyScope) -> String {
        switch scope {
        case .allLoaded: return "同類型（目前已載入）"
        case .last4Weeks: return "同類型（最近 4 週）"
        case .sameSource: return "同類型（同資料來源）"
        }
    }
}

// MARK: - Native Swift Chart for Training Zones

struct ZoneDistributionChartView: View {
    let distribution: ZoneDistribution

    private func color(for zone: TrainingZone) -> Color {
        switch zone {
        case .zone1: return .gray.opacity(0.6)
        case .zone2: return PremiumColor.emerald
        case .zone3: return PremiumColor.gold
        case .zone4: return PremiumColor.redOrange
        case .zone5: return PremiumColor.neonPurple
        }
    }

    var body: some View {
        Chart {
            ForEach(TrainingZone.allCases.reversed(), id: \.self) { zone in
                let ratio = distribution.ratio(for: zone)
                BarMark(
                    x: .value("比例", ratio),
                    y: .value("區間", "Zone \(zone.rawValue)")
                )
                .foregroundStyle(color(for: zone).gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(.system(size: 10, design: .rounded).bold())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .extended, position: .leading) { value in
                AxisValueLabel()
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(height: 140)
        .padding(.vertical, 8)
    }
}

struct AnalysisResultView: View {
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("核心分析報告")
                .font(.title3.bold())
                .foregroundStyle(.white)

            MetricDisclosureCardView(metadata: result.metricMetadata)

            VStack(alignment: .leading, spacing: 8) {
                Label("主要發現", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(PremiumColor.gold)
                ForEach(evaluation.keyFindings, id: \.self) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(PremiumColor.gold)
                        Text(finding)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(14)
            .background(PremiumColor.gold.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(PremiumColor.gold.opacity(0.2), lineWidth: 1)
            )

            // Zone distribution chart
            VStack(alignment: .leading, spacing: 10) {
                Label("心率區間分佈", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                ZoneDistributionChartView(distribution: result.zoneDistribution)
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )

            // Reasons Callout Box
            if !result.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("判定理由說明", systemImage: "info.circle.fill")
                        .font(.headline)
                        .foregroundStyle(PremiumColor.skyBlue)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(PremiumColor.skyBlue)
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PremiumColor.skyBlue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PremiumColor.skyBlue.opacity(0.15), lineWidth: 1)
                )
            }

            // Recommendations Callout Box
            if !result.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("教練建議回饋", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(PremiumColor.emerald)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.recommendations, id: \.self) { recommendation in
                            HStack(alignment: .top, spacing: 8) {
                                Text("💡")
                                Text(recommendation)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PremiumColor.emerald.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PremiumColor.emerald.opacity(0.15), lineWidth: 1)
                )
            }

            DisclosureGroup("進階分析（技術細節）") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(WorkoutDetailInformationArchitecture.technicalClassificationConfidence)：\(evaluation.classificationConfidence)%")
                    Text("\(WorkoutDetailInformationArchitecture.technicalEvaluationConfidence)：\(evaluation.evaluationConfidence)%")
                    ForEach(evaluation.secondarySignals, id: \.self) { signal in
                        Text("• \(signal)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
    }
}

struct CalibrationSuggestionView: View {
    let suggestion: CalibrationSuggestion
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("個人化 Zone 2 校正", systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(suggestion.confidence * 100))% 信心水準")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)

            HStack(spacing: 8) {
                Text(suggestion.source.displayLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.82))
                Text(suggestion.source.verificationLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(PremiumColor.gold)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.16))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading) {
                        Text("目前 Zone 2")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(Int(suggestion.currentBounds.zone2LowerBound))-\(Int(suggestion.currentBounds.zone2UpperBound)) bpm")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    VStack(alignment: .leading) {
                        Text("建議 Zone 2")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(Int(suggestion.suggestedBounds.zone2LowerBound))-\(Int(suggestion.suggestedBounds.zone2UpperBound)) bpm")
                            .font(.caption.bold())
                            .foregroundStyle(PremiumColor.gold)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                Button("套用建議", action: onApply)
                    .font(.caption.bold())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.white)
                    .foregroundColor(PremiumColor.neonPurple)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [PremiumColor.neonPurple.opacity(0.85), PremiumColor.neonPurple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: PremiumColor.neonPurple.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    private let configurableWorkoutTypes: [WorkoutType] = [
        .running, .cycling, .swimming, .walking, .strengthTraining
    ]
    private let restingHeartRateStore: any HealthKitWorkoutStore
    @State private var isImportingRestingHeartRate = false
    @State private var restingHeartRateImportMessage: String?

    init(
        settingsManager: SettingsManager,
        restingHeartRateStore: any HealthKitWorkoutStore = SystemHealthKitWorkoutStore()
    ) {
        self.settingsManager = settingsManager
        self.restingHeartRateStore = restingHeartRateStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("分析策略設定")
                .font(.title3.bold())
                .foregroundStyle(.white)

            if let suggestion = settingsManager.pendingSuggestion {
                CalibrationSuggestionView(suggestion: suggestion) {
                    withAnimation {
                        settingsManager.applySuggestion()
                    }
                }
            }

            zone2ProfileStatusSection
            restingHeartRateSection
            zone2BoundsSection

            VStack(alignment: .leading, spacing: 12) {
                Label("運動類型預設目標", systemImage: "scope")
                    .font(.headline)
                    .foregroundStyle(.white)

                ForEach(configurableWorkoutTypes, id: \.self) { type in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(type.localizedName)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker(
                            type.localizedName,
                            selection: Binding(
                                get: {
                                    let intent = settingsManager.defaultIntent(for: type)
                                    return TrainingIntent.uiVisibleCases.contains(intent) ? intent : .zone2
                                },
                                set: { settingsManager.setDefaultIntent($0, for: type) }
                            )
                        ) {
                            ForEach(TrainingIntent.uiVisibleCases, id: \.self) { intent in
                                Text(intent.localizedName).tag(intent)
                            }
                        }
                        .pickerStyle(.segmented)
                        .colorMultiply(PremiumColor.skyBlue)
                    }
                }
            }
            .padding(12)
            .background(PremiumColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(PremiumColor.border, lineWidth: 1)
            )
            .padding(14)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Divider()
                .background(Color.white.opacity(0.1))

            // Training goal selection
            VStack(alignment: .leading, spacing: 12) {
                Label("訓練目標方向", systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("設定後，本週概況將顯示訓練型態與目標方向的一致性（僅描述型態符合程度，不代表目標達成。）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(
                    "訓練目標",
                    selection: Binding(
                        get: { settingsManager.trainingGoal },
                        set: { settingsManager.updateTrainingGoal($0) }
                    )
                ) {
                    Text("未設定").tag(UserTrainingGoal?.none)
                    ForEach(UserTrainingGoal.allCases, id: \.self) { goal in
                        Text(goal.localizedLabel).tag(UserTrainingGoal?.some(goal))
                    }
                }
                .pickerStyle(.menu)
                .tint(PremiumColor.skyBlue)
            }
            .padding(14)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                Label("固定核心策略 (不可變更)", systemImage: "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 排除暖身時間：\(Int(settingsManager.policy.warmupExclusionSeconds / 60)) 分鐘")
                    Text("• 排除緩和時間：\(Int(settingsManager.policy.cooldownExclusionSeconds / 60)) 分鐘")
                    Text("• 最短持續時間：\(Int(settingsManager.policy.minimumDurationSeconds / 60)) 分鐘")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            }
        }
        .padding(18)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
    }

    private var zone2ProfileStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("目前 Zone 2 設定狀態", systemImage: "checklist.checked")
                .font(.headline)
                .foregroundStyle(.white)

            Text(settingsManager.zone2ProfileStatusSummary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var restingHeartRateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("個人化心率基線", systemImage: "heart.circle")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Resting HR 會用下方偏移量產生 Zone 2 起始建議；只有按下套用建議後，分析器才會改用新的 bpm 邊界。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Resting HR")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 12) {
                    TextField("例如 55", value: restingHeartRateBinding, format: .number)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .font(.system(.body, design: .rounded).bold())
                        .frame(width: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Button {
                        Task { await importRestingHeartRateFromAppleHealth() }
                    } label: {
                        HStack(spacing: 6) {
                            if isImportingRestingHeartRate {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "heart.text.square")
                            }
                            Text(isImportingRestingHeartRate ? "匯入中..." : "從 Apple Health 匯入")
                        }
                        .font(.caption.bold())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportingRestingHeartRate || !restingHeartRateStore.isAvailable)
                }
            }

            if let restingHeartRateImportMessage {
                Text(restingHeartRateImportMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("建議公式偏移量")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    restingHeartRateOffsetField(title: "下限 +", value: restingLowerOffsetBinding)
                    restingHeartRateOffsetField(title: "上限 +", value: restingUpperOffsetBinding)
                }
                Text("目前公式：Resting HR + \(Int(settingsManager.restingHeartRateSuggestionOffsets.lowerOffset.rounded())) 到 + \(Int(settingsManager.restingHeartRateSuggestionOffsets.upperOffset.rounded())) bpm。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("依 Resting HR 產生建議") {
                    withAnimation {
                        settingsManager.generateRestingHeartRateSuggestion()
                    }
                }
                .font(.caption.bold())
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(PremiumColor.skyBlue.gradient)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .disabled(settingsManager.restingHeartRate == nil)

                if settingsManager.restingHeartRate == nil {
                    Text("先輸入 Resting HR")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var zone2BoundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Zone 2 邊界設定 (bpm)", systemImage: "slider.horizontal.2.square.on.square")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 20) {
                zone2BoundField(title: "下限", value: zone2LowerBinding)
                zone2BoundField(title: "上限", value: zone2UpperBinding)
            }

            HStack(spacing: 10) {
                Button("重設為預設") {
                    withAnimation {
                        settingsManager.resetZone2BoundsToDefault()
                    }
                }
                .font(.caption.bold())
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .disabled(!settingsManager.isUsingCustomZoneBounds)

                if !settingsManager.isUsingCustomZoneBounds {
                    Text("目前已是預設界線")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var restingHeartRateBinding: Binding<Double> {
        Binding(
            get: { settingsManager.restingHeartRate ?? 0 },
            set: { settingsManager.updateRestingHeartRate($0 == 0 ? nil : $0) }
        )
    }

    private var restingLowerOffsetBinding: Binding<Double> {
        Binding(
            get: { settingsManager.restingHeartRateSuggestionOffsets.lowerOffset },
            set: {
                settingsManager.updateRestingHeartRateSuggestionOffsets(
                    lowerOffset: $0,
                    upperOffset: settingsManager.restingHeartRateSuggestionOffsets.upperOffset
                )
            }
        )
    }

    private var restingUpperOffsetBinding: Binding<Double> {
        Binding(
            get: { settingsManager.restingHeartRateSuggestionOffsets.upperOffset },
            set: {
                settingsManager.updateRestingHeartRateSuggestionOffsets(
                    lowerOffset: settingsManager.restingHeartRateSuggestionOffsets.lowerOffset,
                    upperOffset: $0
                )
            }
        )
    }

    private var zone2LowerBinding: Binding<Double> {
        Binding(
            get: { settingsManager.policy.zoneBounds.zone2LowerBound },
            set: { settingsManager.updateZone2Bounds(lower: $0, upper: settingsManager.policy.zoneBounds.zone2UpperBound) }
        )
    }

    private var zone2UpperBinding: Binding<Double> {
        Binding(
            get: { settingsManager.policy.zoneBounds.zone2UpperBound },
            set: { settingsManager.updateZone2Bounds(lower: settingsManager.policy.zoneBounds.zone2LowerBound, upper: $0) }
        )
    }

    @ViewBuilder
    private func zone2BoundField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .foregroundColor(.white)
                .font(.system(.body, design: .rounded).bold())
                .frame(width: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func restingHeartRateOffsetField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .foregroundColor(.white)
                .font(.system(.body, design: .rounded).bold())
                .frame(width: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private func importRestingHeartRateFromAppleHealth() async {
        guard restingHeartRateStore.isAvailable else {
            restingHeartRateImportMessage = "此裝置目前無法使用 Apple Health Resting HR。"
            return
        }

        isImportingRestingHeartRate = true
        defer { isImportingRestingHeartRate = false }

        let status = await restingHeartRateStore.requestAuthorization()
        guard status == .sharingAuthorized else {
            restingHeartRateImportMessage = "尚未取得 Apple Health 讀取權限。"
            return
        }

        do {
            guard let imported = try await restingHeartRateStore.fetchRestingHeartRateBaseline() else {
                restingHeartRateImportMessage = "Apple Health 最近 7 天沒有可用的 Resting HR 資料。"
                return
            }

            settingsManager.updateRestingHeartRate(imported)
            settingsManager.generateRestingHeartRateSuggestion()
            restingHeartRateImportMessage = "已匯入 Apple Health 最近 7 天平均 Resting HR \(Int(imported.rounded())) bpm，並產生 Zone 2 建議。"
        } catch {
            restingHeartRateImportMessage = "Apple Health Resting HR 匯入失敗，請稍後再試。"
        }
    }
}
