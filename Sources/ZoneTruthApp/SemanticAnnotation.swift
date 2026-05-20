import Foundation

enum AnnotationAdmissibility: String, Codable, Equatable, Sendable {
    case intentionalSemanticChange = "intentional_semantic_change"
    case observationRefinement = "observation_refinement"
    case bugFix = "bug_fix"
}

struct SemanticChangeAnnotation: Codable, Equatable, Sendable {
    let changeID: String
    let reason: String
    let affectedFixtures: [String]
    let expectedBehaviorChange: [String]
    let reviewedBy: String
    let admissibility: AnnotationAdmissibility
}

// Annotation gate: any evaluation snapshot update must carry a SemanticChangeAnnotation.
// blocking_drift additionally requires admissibility == .intentionalSemanticChange.
enum AnnotationGate {
    enum ValidationResult: Equatable {
        case admissible
        case requiresAnnotation
        case blockedByAdmissibility
    }

    static func validate(
        annotation: SemanticChangeAnnotation?,
        driftStatus: DualRunReviewStatus,
        snapshotChanged: Bool
    ) -> ValidationResult {
        guard snapshotChanged else { return .admissible }
        guard let annotation else { return .requiresAnnotation }

        if driftStatus == .blockingDrift,
           annotation.admissibility != .intentionalSemanticChange {
            return .blockedByAdmissibility
        }
        return .admissible
    }

    static func load(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> SemanticChangeAnnotation? {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let latest = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("SEM-") }
            .sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }
            .first

        guard let url = latest,
              let data = fileManager.contents(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(SemanticChangeAnnotation.self, from: data)
    }
}
