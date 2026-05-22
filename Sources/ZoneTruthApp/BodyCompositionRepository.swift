import Foundation
import ZoneTruthCore

private final class BodyCompositionBundleToken {}

struct BodyCompositionRepository {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadLedger() -> BodyCompositionLedger? {
        let measurements = loadMeasurements()
        guard !measurements.isEmpty else { return nil }
        return BodyCompositionTrendAnalyzer.analyze(measurements: measurements)
    }

    func loadMeasurements() -> [BodyCompositionMeasurement] {
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([BodyCompositionMeasurement].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
        }

        // First-run or invalid-empty file bootstrap: seed Documents so Weekly
        // body composition context is visible without manual import.
        let seeded = loadBundledSeedMeasurements()
        if !seeded.isEmpty {
            try? save(measurements: seeded)
        }
        return seeded
    }

    func save(measurements: [BodyCompositionMeasurement]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(measurements)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadBundledSeedMeasurements() -> [BodyCompositionMeasurement] {
        let candidateBundles: [Bundle] = [
            Bundle(for: BodyCompositionBundleToken.self),
            .main,
        ]
        let candidateNames = ["body_composition.seed", "body_composition"]
        let resourceURL = candidateBundles.lazy.compactMap { bundle in
            candidateNames.lazy.compactMap { name in
                bundle.url(forResource: name, withExtension: "json")
            }.first
        }.first
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url) else {
            return fallbackSeedMeasurements()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BodyCompositionMeasurement].self, from: data)) ?? fallbackSeedMeasurements()
    }

    private func fallbackSeedMeasurements() -> [BodyCompositionMeasurement] {
        let rows: [(String, Double, Double, Double, Double, Double, Double, Double, Double, Int, Double)] = [
            ("2020-11-06T00:00:00Z", 77.5, 34.5, 15.5, 25.0, 20.0, 0.87, 68.0, 127.4, 1708, 83.2),
            ("2024-11-08T00:00:00Z", 85.8, 36.1, 21.2, 28.0, 24.7, 0.92, 99.1, 187.1, 1765, 76.8),
            ("2025-04-08T00:00:00Z", 85.0, 36.1, 20.4, 27.8, 24.0, 0.92, 94.8, 178.2, 1766, 77.9),
            ("2025-05-06T00:00:00Z", 85.8, 36.4, 20.6, 28.0, 24.0, 0.91, 96.2, 181.0, 1777, 77.9),
            ("2025-06-06T00:00:00Z", 84.1, 36.2, 19.3, 27.5, 22.9, 0.90, 89.2, 166.8, 1770, 79.5),
            ("2025-07-29T00:00:00Z", 83.0, 36.0, 18.5, 27.1, 22.2, 0.90, 85.0, 158.2, 1764, 80.5),
            ("2025-08-20T00:00:00Z", 81.9, 35.8, 17.8, 26.7, 21.7, 0.90, 81.7, 151.4, 1754, 81.1),
            ("2025-09-10T00:00:00Z", 81.4, 35.9, 16.9, 26.6, 20.8, 0.89, 77.2, 142.3, 1762, 82.6),
            ("2025-09-18T00:00:00Z", 81.4, 36.3, 16.4, 26.6, 20.1, 0.89, 74.5, 136.6, 1774, 83.7),
            ("2025-09-23T00:00:00Z", 81.2, 36.2, 16.2, 26.5, 20.0, 0.90, 73.5, 134.7, 1773, 83.9),
            ("2025-10-31T00:00:00Z", 79.6, 35.8, 15.5, 26.0, 19.5, 0.89, 69.9, 127.3, 1754, 84.5),
            ("2026-05-22T00:00:00Z", 79.9, 36.4, 14.8, 26.1, 18.5, 0.88, 66.3, 120.0, 1775, 86.1),
        ]
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let date = iso.date(from: row.0) else { return nil }
            return BodyCompositionMeasurement(
                date: date,
                weightKg: row.1,
                skeletalMuscleKg: row.2,
                bodyFatKg: row.3,
                bmi: row.4,
                bodyFatPercent: row.5,
                waistHipRatio: row.6,
                visceralFatCm2: row.7,
                subcutaneousFatCm2: row.8,
                basalMetabolicRateKcal: row.9,
                healthScore: row.10,
                source: "InBody"
            )
        }
    }
}

extension AppEnvironment {
    static func bodyCompositionFileURL(fileManager: FileManager = .default) -> URL {
        fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("body_composition.json")
    }
}

extension BodyCompositionRepository {
    static func defaultSeedLedger() -> BodyCompositionLedger? {
        BodyCompositionTrendAnalyzer.analyze(measurements: seedMeasurements())
    }

    static func seedMeasurements() -> [BodyCompositionMeasurement] {
        let rows: [(String, Double, Double, Double, Double, Double, Double, Double, Double, Int, Double)] = [
            ("2020-11-06T00:00:00Z", 77.5, 34.5, 15.5, 25.0, 20.0, 0.87, 68.0, 127.4, 1708, 83.2),
            ("2024-11-08T00:00:00Z", 85.8, 36.1, 21.2, 28.0, 24.7, 0.92, 99.1, 187.1, 1765, 76.8),
            ("2025-04-08T00:00:00Z", 85.0, 36.1, 20.4, 27.8, 24.0, 0.92, 94.8, 178.2, 1766, 77.9),
            ("2025-05-06T00:00:00Z", 85.8, 36.4, 20.6, 28.0, 24.0, 0.91, 96.2, 181.0, 1777, 77.9),
            ("2025-06-06T00:00:00Z", 84.1, 36.2, 19.3, 27.5, 22.9, 0.90, 89.2, 166.8, 1770, 79.5),
            ("2025-07-29T00:00:00Z", 83.0, 36.0, 18.5, 27.1, 22.2, 0.90, 85.0, 158.2, 1764, 80.5),
            ("2025-08-20T00:00:00Z", 81.9, 35.8, 17.8, 26.7, 21.7, 0.90, 81.7, 151.4, 1754, 81.1),
            ("2025-09-10T00:00:00Z", 81.4, 35.9, 16.9, 26.6, 20.8, 0.89, 77.2, 142.3, 1762, 82.6),
            ("2025-09-18T00:00:00Z", 81.4, 36.3, 16.4, 26.6, 20.1, 0.89, 74.5, 136.6, 1774, 83.7),
            ("2025-09-23T00:00:00Z", 81.2, 36.2, 16.2, 26.5, 20.0, 0.90, 73.5, 134.7, 1773, 83.9),
            ("2025-10-31T00:00:00Z", 79.6, 35.8, 15.5, 26.0, 19.5, 0.89, 69.9, 127.3, 1754, 84.5),
            ("2026-05-22T00:00:00Z", 79.9, 36.4, 14.8, 26.1, 18.5, 0.88, 66.3, 120.0, 1775, 86.1),
        ]
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let date = iso.date(from: row.0) else { return nil }
            return BodyCompositionMeasurement(
                date: date,
                weightKg: row.1,
                skeletalMuscleKg: row.2,
                bodyFatKg: row.3,
                bmi: row.4,
                bodyFatPercent: row.5,
                waistHipRatio: row.6,
                visceralFatCm2: row.7,
                subcutaneousFatCm2: row.8,
                basalMetabolicRateKcal: row.9,
                healthScore: row.10,
                source: "InBody"
            )
        }
    }
}
