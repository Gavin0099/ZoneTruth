import Foundation

func bodyCompositionSpanDays(from earliestDate: Date, to latestDate: Date) -> Int {
    let interval = latestDate.timeIntervalSince(earliestDate)
    guard interval > 0 else { return 0 }
    return max(1, Int(ceil(interval / 86_400)))
}

// MARK: - Raw measurement

public struct BodyCompositionMeasurement: Codable, Equatable, Sendable {
    public let date: Date
    public let weightKg: Double
    public let skeletalMuscleKg: Double
    public let bodyFatKg: Double
    public let bmi: Double
    public let bodyFatPercent: Double
    public let waistHipRatio: Double
    public let visceralFatCm2: Double
    public let subcutaneousFatCm2: Double
    public let basalMetabolicRateKcal: Int
    public let healthScore: Double?
    public let source: String

    public init(
        date: Date,
        weightKg: Double,
        skeletalMuscleKg: Double,
        bodyFatKg: Double,
        bmi: Double,
        bodyFatPercent: Double,
        waistHipRatio: Double,
        visceralFatCm2: Double,
        subcutaneousFatCm2: Double,
        basalMetabolicRateKcal: Int,
        healthScore: Double? = nil,
        source: String = "InBody"
    ) {
        self.date = date
        self.weightKg = weightKg
        self.skeletalMuscleKg = skeletalMuscleKg
        self.bodyFatKg = bodyFatKg
        self.bmi = bmi
        self.bodyFatPercent = bodyFatPercent
        self.waistHipRatio = waistHipRatio
        self.visceralFatCm2 = visceralFatCm2
        self.subcutaneousFatCm2 = subcutaneousFatCm2
        self.basalMetabolicRateKcal = basalMetabolicRateKcal
        self.healthScore = healthScore
        self.source = source
    }
}

// MARK: - Trend primitives

public enum TrendDirection: String, Codable, Equatable, Sendable {
    case declining
    case stable
    case increasing
}

// Confidence reflects both measurement consistency and magnitude relative to
// the instrument's noise band. A single large measurement delta can still
// be .uncertain if the intermediate points are erratic.
public enum TrendConfidence: String, Codable, Equatable, Sendable {
    case strong       // Sustained directional change, magnitude >> noise band
    case directional  // Consistent direction but moderate magnitude
    case uncertain    // Change within noise band
    case insufficient // Fewer than 2 usable data points
}

public struct MetricTrend: Equatable, Sendable {
    public let direction: TrendDirection
    public let absoluteChange: Double      // latest - earliest
    public let percentChange: Double       // (latest - earliest) / |earliest| * 100
    public let confidence: TrendConfidence
    public let spanDays: Int
    public let noiseBand: Double           // ±value; instrument accuracy reference

    public init(
        direction: TrendDirection,
        absoluteChange: Double,
        percentChange: Double,
        confidence: TrendConfidence,
        spanDays: Int,
        noiseBand: Double
    ) {
        self.direction = direction
        self.absoluteChange = absoluteChange
        self.percentChange = percentChange
        self.confidence = confidence
        self.spanDays = spanDays
        self.noiseBand = noiseBand
    }
}

// MARK: - Ledger

// A BodyCompositionLedger aggregates multiple measurements into
// evidence-qualified trend claims. Claims are only admitted when
// the underlying trend magnitude exceeds the instrument noise band.
public struct BodyCompositionLedger: Equatable, Sendable {
    public let measurements: [BodyCompositionMeasurement]
    public let measurementCount: Int
    public let earliestDate: Date
    public let latestDate: Date
    public let latest: BodyCompositionMeasurement
    public let fatTrend: MetricTrend
    public let muscleTrend: MetricTrend
    public let visceralFatTrend: MetricTrend
    public let weightTrend: MetricTrend

    // Body recomposition: fat declining beyond noise AND muscle not declining
    // beyond noise. Cannot be claimed from a single measurement delta alone.
    public let isBodyRecomposition: Bool

    public init(
        measurements: [BodyCompositionMeasurement] = [],
        measurementCount: Int,
        earliestDate: Date,
        latestDate: Date,
        latest: BodyCompositionMeasurement,
        fatTrend: MetricTrend,
        muscleTrend: MetricTrend,
        visceralFatTrend: MetricTrend,
        weightTrend: MetricTrend,
        isBodyRecomposition: Bool
    ) {
        self.measurements = measurements
        self.measurementCount = measurementCount
        self.earliestDate = earliestDate
        self.latestDate = latestDate
        self.latest = latest
        self.fatTrend = fatTrend
        self.muscleTrend = muscleTrend
        self.visceralFatTrend = visceralFatTrend
        self.weightTrend = weightTrend
        self.isBodyRecomposition = isBodyRecomposition
    }

    // Admissible label for the long-term adaptation summary.
    // causal attribution ("Zone2 caused fat loss") is never admissible here;
    // only correlated longitudinal change is described.
    public var compositionNarrative: String {
        if isBodyRecomposition && fatTrend.confidence == .strong && visceralFatTrend.confidence == .strong {
            return "長期脂肪持續下降，肌肉量大致維持，內臟脂肪顯著改善。"
        }
        if fatTrend.direction == .declining && fatTrend.confidence != .insufficient {
            return "體脂方向持續下降，肌肉量大致穩定。"
        }
        if fatTrend.confidence == .insufficient {
            return "量測資料不足，尚無可靠長期趨勢。"
        }
        return "長期身體組成方向中性。"
    }

    public var spanDays: Int {
        bodyCompositionSpanDays(from: earliestDate, to: latestDate)
    }
}
