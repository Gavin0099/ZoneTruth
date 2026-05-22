import Foundation
import ZoneTruthCore

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
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BodyCompositionMeasurement].self, from: data)) ?? []
    }

    func save(measurements: [BodyCompositionMeasurement]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(measurements)
        try data.write(to: fileURL, options: .atomic)
    }
}

extension AppEnvironment {
    static func bodyCompositionFileURL(fileManager: FileManager = .default) -> URL {
        fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("body_composition.json")
    }
}
