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
        case .mixed: return "混合訓練"
        case .other: return "其他 (如羽球等)"
        }
    }
    
    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .strengthTraining: return "figure.strengthtraining.functional"
        case .mixed: return "figure.mixed.cardio"
        case .other: return "sportscourt"
        }
    }
}

extension TrainingIntent {
    var localizedName: String {
        switch self {
        case .zone2: return "Zone 2"
        case .activityReview: return "活動 / 技巧"
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
                        onRequestHealthAccess: {
                            Task { await viewModel.requestHealthAccess() }
                        },
                        onConnectStrava: viewModel.canConnectStrava ? {
                            Task { await viewModel.connectStrava() }
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
                        result: viewModel.analysisResult(for: workout),
                        evaluation: viewModel.evaluationResult(for: workout),
                        onIntentChanged: viewModel.updateIntent,
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
    }
}

struct WorkoutSourceBannerView: View {
    let source: WorkoutDataSource
    let statusMessage: String?
    let isRefreshing: Bool
    let isRequestingAuthorization: Bool
    let canRequestHealthAccess: Bool
    let onRequestHealthAccess: () -> Void
    var onConnectStrava: (() -> Void)? = nil

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
                Text(workout.workoutType.localizedName)
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(.white)
                
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
}

struct WorkoutDetailView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent
    let result: AnalysisResult
    let evaluation: WorkoutEvaluation
    let onIntentChanged: (TrainingIntent) -> Void
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SummaryCardView(workout: workout, selectedIntent: selectedIntent, result: result, evaluation: evaluation)
                
                IntentPickerView(selectedIntent: selectedIntent, onIntentChanged: onIntentChanged)
                
                AnalysisResultView(result: result, evaluation: evaluation)
                
                SettingsView(settingsManager: settingsManager)
            }
            .padding(20)
        }
        .background(PremiumColor.bgDark)
        .navigationTitle("運動紀錄詳情")
        .iosDetailNavigationBarStyling()
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

            Text(evaluation.goalFitLabel)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(.white)

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
    let onIntentChanged: (TrainingIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("設定訓練目標")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            
            Picker(
                "目標",
                selection: Binding(
                    get: { selectedIntent },
                    set: { onIntentChanged($0) }
                )
            ) {
                ForEach(TrainingIntent.allCases, id: \.self) { intent in
                    Text(intent.localizedName).tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(PremiumColor.skyBlue)
        }
        .padding(12)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PremiumColor.border, lineWidth: 1)
        )
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
                    Text("分類信心：\(evaluation.classificationConfidence)%")
                    Text("評估信心：\(evaluation.evaluationConfidence)%")
                    ForEach(evaluation.secondarySignals, id: \.self) { signal in
                        Text("• \(signal)")
                    }
                    Text("舊版判定：\(result.verdict.localizedName)")
                        .foregroundStyle(.secondary)
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

            HStack(spacing: 12) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading) {
                        Text("目前上限")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(Int(suggestion.currentBounds.zone2UpperBound)) bpm")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    VStack(alignment: .leading) {
                        Text("建議上限")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(Int(suggestion.suggestedBounds.zone2UpperBound)) bpm")
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

            VStack(alignment: .leading, spacing: 12) {
                Label("Zone 2 邊界設定 (bpm)", systemImage: "slider.horizontal.2.square.on.square")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("下限")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("下限", value: Binding(
                            get: { settingsManager.policy.zoneBounds.zone2LowerBound },
                            set: { settingsManager.updateZone2Bounds(lower: $0, upper: settingsManager.policy.zoneBounds.zone2UpperBound) }
                        ), format: .number)
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("上限")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("上限", value: Binding(
                            get: { settingsManager.policy.zoneBounds.zone2UpperBound },
                            set: { settingsManager.updateZone2Bounds(lower: settingsManager.policy.zoneBounds.zone2LowerBound, upper: $0) }
                        ), format: .number)
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
}
