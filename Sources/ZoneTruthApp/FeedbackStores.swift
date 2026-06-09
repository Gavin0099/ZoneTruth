import Foundation
import ZoneTruthCore

struct FileTrainingClassificationFeedbackStore: TrainingClassificationFeedbackStoring {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func save(_ record: TrainingClassificationFeedbackRecord) {
        var records = loadRecords()
        records.append(record)
        save(records)
    }

    func records(for workoutID: UUID) -> [TrainingClassificationFeedbackRecord] {
        loadRecords().filter { $0.feedback.workoutID == workoutID }
    }

    func allRecords() -> [TrainingClassificationFeedbackRecord] {
        loadRecords()
    }

    private func loadRecords() -> [TrainingClassificationFeedbackRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let file = try? JSONDecoder.zoneTruth.decode(TrainingClassificationFeedbackRecordFile.self, from: data) else {
            return []
        }
        return file.records
    }

    private func save(_ records: [TrainingClassificationFeedbackRecord]) {
        let file = TrainingClassificationFeedbackRecordFile(records: records)
        guard let data = try? JSONEncoder.zoneTruth.encode(file) else { return }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

private struct TrainingClassificationFeedbackRecordFile: Codable, Equatable {
    let schemaVersion: Int
    let records: [TrainingClassificationFeedbackRecord]

    init(
        schemaVersion: Int = 1,
        records: [TrainingClassificationFeedbackRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}
