import SwiftUI
import ZoneTruthCore

private let bodyCompositionMeasurementDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yy.MM.dd"
    return formatter
}()

func bodyCompositionMeasurementDateLabel(_ date: Date) -> String {
    bodyCompositionMeasurementDateFormatter.string(from: date)
}

// MARK: - Standalone body composition history tab / sheet

struct BodyCompositionView: View {
    let ledger: BodyCompositionLedger

    var body: some View {
        ZStack {
            PremiumColor.bgDark.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    narrativeCard
                    keyMetricsCard
                    measurementConfidenceCard
                }
                .padding(16)
            }
        }
        .navigationTitle("身體組成趨勢")
        .iosNavigationBarStyling()
    }

    // MARK: Narrative

    private var narrativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .foregroundStyle(PremiumColor.emerald)
                Text("長期身體組成觀察")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Spacer()
                EvidencePill(label: "直接量測", color: PremiumColor.emerald)
            }

            Text(ledger.compositionNarrative)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                metaTag(icon: "calendar", text: spanLabel)
                metaTag(icon: "number", text: "\(ledger.measurementCount) 次量測")
                metaTag(icon: "ruler", text: ledger.latest.source)
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    // MARK: Key metrics

    private var keyMetricsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("趨勢指標")
                .font(.headline.bold())
                .foregroundStyle(.white)

            TrendRow(
                label: "體脂肪",
                trend: ledger.fatTrend,
                unit: "kg",
                goodDirection: .declining,
                noiseCaveat: "±0.8 kg（InBody 估算誤差）"
            )
            Divider().background(PremiumColor.border)
            TrendRow(
                label: "骨骼肌",
                trend: ledger.muscleTrend,
                unit: "kg",
                goodDirection: .increasing,
                noiseCaveat: "±0.5 kg（InBody 估算誤差）"
            )
            Divider().background(PremiumColor.border)
            TrendRow(
                label: "內臟脂肪",
                trend: ledger.visceralFatTrend,
                unit: "cm²",
                goodDirection: .declining,
                noiseCaveat: "±5 cm²（估算誤差）"
            )
            Divider().background(PremiumColor.border)
            TrendRow(
                label: "體重",
                trend: ledger.weightTrend,
                unit: "kg",
                goodDirection: nil,
                noiseCaveat: "±0.5 kg（水分 / 時間點）"
            )

            if ledger.isBodyRecomposition {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.and.arrow.down.backward")
                        .foregroundStyle(PremiumColor.emerald)
                        .font(.subheadline)
                    Text("脂肪下降同時肌肉量維持，符合身體組成重塑方向。")
                        .font(.caption)
                        .foregroundStyle(PremiumColor.emerald.opacity(0.9))
                }
                .padding(10)
                .background(PremiumColor.emerald.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(PremiumColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PremiumColor.border, lineWidth: 1))
    }

    // MARK: Measurement confidence caveat

    private var measurementConfidenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(PremiumColor.gold)
                Text("量測誤差說明")
                    .font(.caption.bold())
                    .foregroundStyle(PremiumColor.gold)
            }
            Text(
                "InBody 生物電阻抗量測受水分、進食時間、排汗狀態影響。" +
                "單次數值的細微差異（±0.5 kg 骨骼肌、±1% 體脂率）不應視為確定性增減，" +
                "僅長期方向性趨勢（多個月、多次量測一致）具有觀察價值。" +
                "此系統不提供醫療或代謝診斷，所有觀察僅描述相關性變化，不推論因果。"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(PremiumColor.gold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PremiumColor.gold.opacity(0.15), lineWidth: 1))
    }

    // MARK: Helpers

    private var spanLabel: String {
        let days = ledger.spanDays
        if days >= 365 {
            let months = days / 30
            return "跨度約 \(months) 個月"
        }
        return "跨度 \(days) 天"
    }

    private func metaTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct EvidencePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
    }
}

private struct TrendRow: View {
    let label: String
    let trend: MetricTrend
    let unit: String
    let goodDirection: TrendDirection?
    let noiseCaveat: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: directionIcon)
                        .font(.caption.bold())
                        .foregroundStyle(trendColor)
                    Text(changeLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(trendColor)
                    Text(confidenceBadgeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            Text(noiseCaveat)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var directionIcon: String {
        switch trend.direction {
        case .declining:  return "arrow.down"
        case .stable:     return "minus"
        case .increasing: return "arrow.up"
        }
    }

    private var trendColor: Color {
        guard let good = goodDirection else { return .white }
        if trend.direction == good { return PremiumColor.emerald }
        if trend.direction == .stable { return .white }
        return PremiumColor.redOrange
    }

    private var changeLabel: String {
        let sign = trend.absoluteChange >= 0 ? "+" : ""
        return String(format: "%@%.1f %@", sign, trend.absoluteChange, unit)
    }

    private var confidenceBadgeLabel: String {
        switch trend.confidence {
        case .strong:       return "強趨勢"
        case .directional:  return "方向性"
        case .uncertain:    return "誤差內"
        case .insufficient: return "資料不足"
        }
    }
}

// MARK: - WeeklyDashboard inline section

struct BodyCompositionContextSection: View {
    let ledger: BodyCompositionLedger
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("長期背景")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                NavigationLink {
                    BodyCompositionView(ledger: ledger)
                } label: {
                    HStack(spacing: 4) {
                        Text("完整趨勢")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(PremiumColor.skyBlue)
                }
            }

            Text(ledger.compositionNarrative)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                compositionChip(
                    icon: "flame.fill",
                    color: PremiumColor.redOrange,
                    label: "體脂",
                    trend: ledger.fatTrend,
                    unit: "kg"
                )
                compositionChip(
                    icon: "figure.strengthtraining.functional",
                    color: PremiumColor.emerald,
                    label: "骨骼肌",
                    trend: ledger.muscleTrend,
                    unit: "kg"
                )
                compositionChip(
                    icon: "heart.fill",
                    color: PremiumColor.skyBlue,
                    label: "內臟脂肪",
                    trend: ledger.visceralFatTrend,
                    unit: "cm²"
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(ledger.measurementCount) 次量測・\(spanLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("InBody")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !ledger.measurements.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(spacing: 8) {
                        ForEach(Array(ledger.measurements.enumerated().reversed()), id: \.offset) { idx, item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("測量 \(idx)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(
                                    "\(dateLabel(item.date))  體重 \(fmt1(item.weightKg))kg  骨骼肌 \(fmt1(item.skeletalMuscleKg))kg  體脂 \(fmt1(item.bodyFatKg))kg"
                                )
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                                Text(
                                    "體脂率 \(fmt1(item.bodyFatPercent))%  BMI \(fmt1(item.bmi))  內臟脂肪 \(fmt1(item.visceralFatCm2))cm²  健康分數 \(item.healthScore.map(fmt1) ?? "-")"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.caption)
                        Text("查看每筆量測明細")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(PremiumColor.skyBlue)
                }
            }
        }
    }

    private var spanLabel: String {
        let days = ledger.spanDays
        if days >= 365 { return "跨度約 \(days / 30) 個月" }
        return "跨度 \(days) 天"
    }

    private func dateLabel(_ date: Date) -> String {
        bodyCompositionMeasurementDateLabel(date)
    }

    private func fmt1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func compositionChip(
        icon: String,
        color: Color,
        label: String,
        trend: MetricTrend,
        unit: String
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            let sign = trend.absoluteChange >= 0 ? "+" : ""
            Text(String(format: "%@%.1f", sign, trend.absoluteChange))
                .font(.caption.bold())
                .foregroundStyle(trend.direction == .declining && color == PremiumColor.redOrange ? PremiumColor.emerald : color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1))
    }
}
