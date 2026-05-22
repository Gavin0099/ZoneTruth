import Foundation

public enum BodyCompositionTrendAnalyzer {

    // Instrument noise bands (InBody reference accuracy ranges).
    // Changes within these bands are .uncertain regardless of direction.
    private static let weightNoiseBand: Double     = 0.5   // kg
    private static let muscleNoiseBand: Double     = 0.5   // kg
    private static let fatPercentNoiseBand: Double = 1.0   // %
    private static let fatKgNoiseBand: Double      = 0.8   // kg
    private static let visceralNoiseBand: Double   = 5.0   // cm²

    public static func analyze(
        measurements: [BodyCompositionMeasurement]
    ) -> BodyCompositionLedger? {
        let sorted = measurements.sorted { $0.date < $1.date }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else {
            return nil
        }

        let fatTrend = trend(
            values: sorted.map { ($0.date, $0.bodyFatKg) },
            noiseBand: fatKgNoiseBand
        )
        let muscleTrend = trend(
            values: sorted.map { ($0.date, $0.skeletalMuscleKg) },
            noiseBand: muscleNoiseBand
        )
        let visceralTrend = trend(
            values: sorted.map { ($0.date, $0.visceralFatCm2) },
            noiseBand: visceralNoiseBand
        )
        let weightTrend = trend(
            values: sorted.map { ($0.date, $0.weightKg) },
            noiseBand: weightNoiseBand
        )

        // Body recomposition: fat must be declining beyond noise AND
        // muscle must not be declining beyond noise (stable or increasing).
        let fatDeclining = fatTrend.direction == .declining && fatTrend.confidence != .uncertain && fatTrend.confidence != .insufficient
        let musclePreserved = muscleTrend.direction != .declining || muscleTrend.confidence == .uncertain
        let isBodyRecomposition = fatDeclining && musclePreserved && sorted.count >= 3

        return BodyCompositionLedger(
            measurements: sorted,
            measurementCount: sorted.count,
            earliestDate: first.date,
            latestDate: last.date,
            latest: last,
            fatTrend: fatTrend,
            muscleTrend: muscleTrend,
            visceralFatTrend: visceralTrend,
            weightTrend: weightTrend,
            isBodyRecomposition: isBodyRecomposition
        )
    }

    // MARK: - Internal

    private static func trend(
        values: [(Date, Double)],
        noiseBand: Double
    ) -> MetricTrend {
        guard values.count >= 2,
              let first = values.first,
              let last = values.last else {
            return MetricTrend(
                direction: .stable,
                absoluteChange: 0,
                percentChange: 0,
                confidence: .insufficient,
                spanDays: 0,
                noiseBand: noiseBand
            )
        }

        let delta = last.1 - first.1
        let pct = first.1 == 0 ? 0 : (delta / abs(first.1)) * 100
        let spanDays = Int(last.0.timeIntervalSince(first.0) / 86400)

        let direction: TrendDirection
        if abs(delta) <= noiseBand {
            direction = .stable
        } else {
            direction = delta < 0 ? .declining : .increasing
        }

        // Confidence: count intermediate points moving same direction as overall delta.
        // A trend with ≥ 70% intermediate consistency and |delta| ≥ 2× noise is .strong.
        let confidence = computeConfidence(
            values: values.map(\.1),
            delta: delta,
            noiseBand: noiseBand,
            direction: direction
        )

        return MetricTrend(
            direction: direction,
            absoluteChange: delta,
            percentChange: pct,
            confidence: confidence,
            spanDays: spanDays,
            noiseBand: noiseBand
        )
    }

    private static func computeConfidence(
        values: [Double],
        delta: Double,
        noiseBand: Double,
        direction: TrendDirection
    ) -> TrendConfidence {
        guard values.count >= 2 else { return .insufficient }

        if direction == .stable { return .uncertain }

        // Magnitude test: must exceed noise band meaningfully
        let magnitude = abs(delta)
        if magnitude < noiseBand { return .uncertain }

        // Consistency test: what fraction of consecutive pairs move same direction?
        var sameDirection = 0
        var total = 0
        for i in 1 ..< values.count {
            let step = values[i] - values[i - 1]
            if abs(step) < noiseBand * 0.3 { continue } // skip near-flat steps
            total += 1
            if (direction == .declining && step < 0) || (direction == .increasing && step > 0) {
                sameDirection += 1
            }
        }

        let consistency = total > 0 ? Double(sameDirection) / Double(total) : 0

        if magnitude >= noiseBand * 3 && consistency >= 0.7 {
            return .strong
        }
        if magnitude >= noiseBand && consistency >= 0.5 {
            return .directional
        }
        return .uncertain
    }
}
