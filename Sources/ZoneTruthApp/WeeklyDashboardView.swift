import SwiftUI
import ZoneTruthCore

// MARK: - Extensions

extension RecoveryConcernLevel {
    var localizedLabel: String {
        switch self {
        case .low:      return "低"
        case .moderate: return "中等"
        case .elevated: return "偏高"
        case .high:     return "高"
        }
    }

    var accentColor: Color {
        switch self {
        case .low:      return PremiumColor.emerald
        case .moderate: return PremiumColor.gold
        case .elevated: return .orange
        case .high:     return PremiumColor.redOrange
        }
    }
}

extension LoadTendency {
    var localizedLabel: String {
        switch self {
        case .balanced:           return "均衡"
        case .highIntensityFocused: return "高強度為主"
        case .aerobicFocused:     return "有氧為主"
        case .mixed:              return "混合"
        case .underloaded:        return "訓練量偏少"
        }
    }

    var iconName: String {
        switch self {
        case .balanced:           return "checkmark.circle"
        case .highIntensityFocused: return "bolt.fill"
        case .aerobicFocused:     return "heart.fill"
        case .mixed:              return "shuffle"
        case .underloaded:        return "tortoise.fill"
        }
    }
}

// MARK: - Root view

struct WeeklyDashboardView: View {
    @ObservedObject var viewModel: WorkoutListViewModel

    var body: some View {
        ZStack {
            PremiumColor.bgDark.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    weekRangeHeader
                    WeeklyOverviewCard(
                        summary: viewModel.weeklySummary,
                        policy: viewModel.weeklyPolicy
                    )
                    WeeklyDistributionCard(summary: viewModel.weeklySummary)
                    WeeklyAdvancedCard(
                        summary: viewModel.weeklySummary,
                        policy: viewModel.weeklyPolicy
                    )
                }
                .padding(16)
            }
        }
        .navigationTitle("本週概況")
        .iosNavigationBarStyling()
    }

    private var weekRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        let s = viewModel.weeklySummary.weekStart
        let e = viewModel.weeklySummary.weekEnd
        return "\(fmt.string(from: s)) – \(fmt.string(from: e))"
    }

    private var weekRangeHeader: some View {
        HStack {
            Text(weekRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Section 1: Overview

struct WeeklyOverviewCard: View {
    let summary: WeeklyWorkoutSummary
    let policy: WeeklyLoadPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if summary.workoutCount == 0 {
                Label("本週尚無訓練紀錄", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 20) {
                    concernBlock
                    Divider()
                        .frame(height: 44)
                        .background(PremiumColor.border)
                    tendencyBlock
                    Spacer()
                }

                Divider().background(PremiumColor.border)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(policy.keyFindings, id: \.self) { finding in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 7)
                            Text(finding)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(PremiumColor.gold)
                        .font(.subheadline)
                    Text(policy.nextAction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PremiumColor.gold.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(PremiumColor.gold.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    private var concernBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("恢復觀察")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(policy.recoveryConcernLevel.accentColor)
                    .frame(width: 8, height: 8)
                Text(policy.recoveryConcernLevel.localizedLabel)
                    .font(.headline.bold())
                    .foregroundStyle(policy.recoveryConcernLevel.accentColor)
            }
        }
    }

    private var tendencyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("訓練傾向")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: policy.loadTendency.iconName)
                    .font(.caption.bold())
                    .foregroundStyle(PremiumColor.skyBlue)
                Text(policy.loadTendency.localizedLabel)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Section 2: Distribution

struct WeeklyDistributionCard: View {
    let summary: WeeklyWorkoutSummary

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本週分布")
                .font(.headline.bold())
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 12) {
                MetricGridCell(
                    icon: "figure.run",
                    color: PremiumColor.skyBlue,
                    title: "訓練次數",
                    value: "\(summary.workoutCount) 次"
                )
                MetricGridCell(
                    icon: "clock.fill",
                    color: PremiumColor.neonPurple,
                    title: "總時間",
                    value: String(format: "%.0f 分鐘", summary.totalDurationMinutes)
                )
                MetricGridCell(
                    icon: "moon.zzz",
                    color: .gray,
                    title: "休息日",
                    value: "\(summary.restDays) 天"
                )
                MetricGridCell(
                    icon: "bolt.fill",
                    color: PremiumColor.redOrange,
                    title: "高強度日",
                    value: "\(summary.highIntensityDays) 天"
                )
                MetricGridCell(
                    icon: "flame.fill",
                    color: .orange,
                    title: "連續訓練",
                    value: "\(summary.consecutiveTrainingDays) 天"
                )
                MetricGridCell(
                    icon: "figure.strengthtraining.functional",
                    color: PremiumColor.emerald,
                    title: "肌力日",
                    value: "\(summary.strengthDays) 天"
                )
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }
}

// MARK: - Section 3: Advanced

struct WeeklyAdvancedCard: View {
    let summary: WeeklyWorkoutSummary
    let policy: WeeklyLoadPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("進階")
                .font(.headline.bold())
                .foregroundStyle(.white)

            // Intent distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("訓練目標分布")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))

                let intentsWithData = TrainingIntent.allCases.filter {
                    summary.intentDistribution[$0, default: 0] > 0
                }
                if intentsWithData.isEmpty {
                    Text("本週無訓練紀錄")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(intentsWithData, id: \.self) { intent in
                        HStack {
                            Text(intent.localizedName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(summary.intentDistribution[intent, default: 0]) 次")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            Divider().background(PremiumColor.border)

            // Zone distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("心率區間分布")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))

                if summary.zoneDistribution.counts.values.reduce(0, +) > 0 {
                    ZoneDistributionChartView(distribution: summary.zoneDistribution)
                } else {
                    Text("心率樣本不足，無法計算區間分布")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().background(PremiumColor.border)

            // Confidence
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("資料信心指數")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    if policy.confidence < 0.6 {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(PremiumColor.gold)
                            Text("部分訓練心率樣本不足，數據僅供參考")
                                .font(.caption)
                                .foregroundStyle(PremiumColor.gold.opacity(0.9))
                        }
                    }
                }
                Spacer()
                ConfidenceRingView(
                    confidence: policy.confidence,
                    color: policy.confidence < 0.6 ? PremiumColor.gold : PremiumColor.emerald
                )
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }
}
