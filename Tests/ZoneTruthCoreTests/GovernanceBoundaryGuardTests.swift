import Foundation
import XCTest

final class GovernanceBoundaryGuardTests: XCTestCase {
    private struct BoundaryConfig: Decodable {
        let appTestBoundaryRules: [AppBoundaryRule]
        let appSourceBoundaryRules: [AppSourceBoundaryRule]
        let commentFilterRegex: String
    }

    private struct AppBoundaryRule: Decodable {
        let id: String
        let regex: String
        let rationale: String
    }

    private typealias AppSourceBoundaryRule = AppBoundaryRule

    private struct BoundarySchema: Decodable {
        let type: String
        let required: [String]
        let properties: [String: BoundaryProperty]
        let additionalProperties: Bool?
    }

    private struct BoundaryProperty: Decodable {
        let type: String?
        let minLength: Int?
    }

    func testBoundaryPatternConfigSatisfiesSchemaContract() throws {
        let configURL = try boundaryConfigURL()
        let schemaURL = try boundarySchemaURL()
        let cfgData = try Data(contentsOf: configURL)
        let schemaData = try Data(contentsOf: schemaURL)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(BoundaryConfig.self, from: cfgData)
        let schema = try decoder.decode(BoundarySchema.self, from: schemaData)

        XCTAssertEqual(schema.type, "object")
        XCTAssertFalse(schema.required.isEmpty)
        XCTAssertEqual(schema.additionalProperties, false)

        for key in schema.required {
            XCTAssertNotNil(schema.properties[key], "Schema required key missing property descriptor: \(key)")
        }

        XCTAssertFalse(config.commentFilterRegex.isEmpty)
        XCTAssertFalse(config.appTestBoundaryRules.isEmpty)
        XCTAssertTrue(config.appTestBoundaryRules.allSatisfy { !$0.id.isEmpty && !$0.regex.isEmpty && !$0.rationale.isEmpty })
        XCTAssertFalse(config.appSourceBoundaryRules.isEmpty)
        XCTAssertTrue(config.appSourceBoundaryRules.allSatisfy { !$0.id.isEmpty && !$0.regex.isEmpty && !$0.rationale.isEmpty })
    }

    func testCloseoutBoundaryTelemetryContractPresent() throws {
        let scriptURL = boundaryRoot()
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("closeout_workout_evaluation.sh", isDirectory: false)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("artifacts/runtime/boundary-telemetry"))
        XCTAssertTrue(script.contains("write_boundary_telemetry()"))
        XCTAssertTrue(script.contains("boundary_telemetry_file:"))
    }

    func testAppTestBoundaryScanReturnsFileLineHitFormat() throws {
        let config = try loadBoundaryConfig()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("zt-boundary-\(UUID().uuidString)", isDirectory: true)
        let appTestsDir = tempRoot
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("ZoneTruthAppTests", isDirectory: true)
        try FileManager.default.createDirectory(at: appTestsDir, withIntermediateDirectories: true)

        let sampleFile = appTestsDir.appendingPathComponent("BoundaryHitSample.swift")
        let sampleContent = """
        import XCTest
        final class BoundaryHitSample: XCTestCase {
            func testHit() {
                _ = WeeklyInferenceClassifier.classify(
                    confidence: 0.9, freshness: .fresh, workoutCount: 1, elapsedDays: 7
                )
            }
        }
        """
        try sampleContent.write(to: sampleFile, atomically: true, encoding: .utf8)

        let escapedRoot = tempRoot.path.replacingOccurrences(of: "\"", with: "\\\"")
        guard let testRule = config.appTestBoundaryRules.first(where: { $0.regex.contains("WeeklyInferenceClassifier\\.classify") }) else {
            XCTFail("Missing app test boundary rule for core inference classifier.")
            return
        }

        let cmd = """
        grep -RIn --include="*.swift" -E '\(testRule.regex)' "\(escapedRoot)/Tests/ZoneTruthAppTests" | grep -Ev '\(config.commentFilterRegex)' || true
        """
        let output = try runBash(cmd)

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(output.contains("BoundaryHitSample.swift:"))
        XCTAssertTrue(output.contains("WeeklyInferenceClassifier.classify"))
    }

    func testEveryAppTestBoundaryRuleHasDedicatedNegativeFixtureHit() throws {
        let config = try loadBoundaryConfig()
        try assertBoundaryRulesHaveFixtureCoverage(
            rules: config.appTestBoundaryRules,
            fixtureByRuleID: fixtureByRuleID(for: .appTests),
            rootRelativeDir: "Tests/ZoneTruthAppTests",
            commentFilterRegex: config.commentFilterRegex
        )
    }

    func testAppSourceBoundaryScanReturnsFileLineHitFormat() throws {
        let config = try loadBoundaryConfig()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("zt-boundary-\(UUID().uuidString)", isDirectory: true)
        let appSourceDir = tempRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("ZoneTruthApp", isDirectory: true)
        try FileManager.default.createDirectory(at: appSourceDir, withIntermediateDirectories: true)

        let sampleFile = appSourceDir.appendingPathComponent("BoundaryHitSourceSample.swift")
        let sampleContent = """
        import Foundation
        struct BoundaryHitSourceSample {
            func hit(authority: WeeklyDecisionAuthority) {
                _ = WeeklyAuthorityRendering.authority(for: 0.85, freshness: .fresh)
                _ = authority
            }
        }
        """
        try sampleContent.write(to: sampleFile, atomically: true, encoding: .utf8)

        let escapedRoot = tempRoot.path.replacingOccurrences(of: "\"", with: "\\\"")
        guard let sourceRule = config.appSourceBoundaryRules.first(where: { $0.regex.contains("WeeklyAuthorityRendering\\.authority") }) else {
            XCTFail("Missing app source boundary rule for authority rendering classification.")
            return
        }

        let cmd = """
        grep -RIn --include="*.swift" -E '\(sourceRule.regex)' "\(escapedRoot)/Sources/ZoneTruthApp" | grep -Ev '\(config.commentFilterRegex)' || true
        """
        let output = try runBash(cmd)

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(output.contains("BoundaryHitSourceSample.swift:"))
        XCTAssertTrue(output.contains("WeeklyAuthorityRendering.authority"))
    }

    func testEveryAppSourceBoundaryRuleHasDedicatedNegativeFixtureHit() throws {
        let config = try loadBoundaryConfig()
        try assertBoundaryRulesHaveFixtureCoverage(
            rules: config.appSourceBoundaryRules,
            fixtureByRuleID: fixtureByRuleID(for: .appSource),
            rootRelativeDir: "Sources/ZoneTruthApp",
            commentFilterRegex: config.commentFilterRegex
        )
    }

    private enum BoundaryDomain {
        case appTests
        case appSource
    }

    private func fixtureByRuleID(for domain: BoundaryDomain) -> [String: String] {
        switch domain {
        case .appTests:
            return [
                "core_inference_classifier_in_app_tests": """
                import XCTest
                final class RuleFixtureCoreInferenceClassifier: XCTestCase {
                    func testHit() {
                        _ = WeeklyInferenceClassifier.classify(
                            confidence: 0.85, freshness: .fresh, workoutCount: 3, elapsedDays: 7
                        )
                    }
                }
                """,
                "core_confidence_semantics_in_app_tests": """
                import XCTest
                final class RuleFixtureCoreConfidenceSemantics: XCTestCase {
                    func testHit() {
                        _ = WeeklyConfidenceSemantics.calibrated(
                            confidence: 0.75, freshness: .fresh, elapsedDays: 7
                        )
                    }
                }
                """,
                "core_freshness_classifier_in_app_tests": """
                import XCTest
                final class RuleFixtureCoreFreshnessClassifier: XCTestCase {
                    func testHit() {
                        _ = WeeklyFreshnessSignal.classify(workoutCount: 2, elapsedDays: 7)
                    }
                }
                """
            ]
        case .appSource:
            return [
                "core_classifier_in_app_source": """
                import Foundation
                struct RuleFixtureCoreClassifier {
                    func hit() {
                        _ = WeeklyInferenceClassifier.classify(
                            confidence: 0.8, freshness: .fresh, workoutCount: 2, elapsedDays: 7
                        )
                    }
                }
                """,
                "authority_rendering_classification_in_app_source": """
                import Foundation
                struct RuleFixtureAuthorityRendering {
                    func hit() {
                        _ = WeeklyAuthorityRendering.authority(for: 0.7, freshness: .fresh)
                    }
                }
                """,
                "provenance_factory_in_app_source": """
                import Foundation
                struct RuleFixtureProvenanceFactory {
                    func hit(workouts: [WorkoutObservation]) {
                        _ = InferenceProvenanceFactory.weekly(from: workouts)
                    }
                }
                """,
                "authority_ceiling_type_usage_in_app_source": """
                import Foundation
                struct RuleFixtureAuthorityCeilingType {
                    let ceiling: InferenceAuthorityCeiling = .nonInterventional
                }
                """,
                "missing_evidence_inference_in_app_source": """
                import Foundation
                struct RuleFixtureMissingEvidence {
                    let evidence = MissingEvidence.sleep
                }
                """
            ]
        }
    }

    private func assertBoundaryRulesHaveFixtureCoverage(
        rules: [AppBoundaryRule],
        fixtureByRuleID: [String: String],
        rootRelativeDir: String,
        commentFilterRegex: String
    ) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("zt-boundary-\(UUID().uuidString)", isDirectory: true)
        let targetDir = tempRoot.appendingPathComponent(rootRelativeDir, isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        for rule in rules {
            guard let fixture = fixtureByRuleID[rule.id] else {
                XCTFail("Missing fixture mapping for boundary rule id: \(rule.id)")
                continue
            }
            let fileName = "RuleFixture_\(rule.id).swift".replacingOccurrences(of: "-", with: "_")
            let fixtureFile = targetDir.appendingPathComponent(fileName)
            try fixture.write(to: fixtureFile, atomically: true, encoding: .utf8)

            let escapedRoot = tempRoot.path.replacingOccurrences(of: "\"", with: "\\\"")
            let cmd = """
            grep -RIn --include="*.swift" -E '\(rule.regex)' "\(escapedRoot)/\(rootRelativeDir)" | grep -Ev '\(commentFilterRegex)' || true
            """
            let output = try runBash(cmd)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

            XCTAssertFalse(trimmed.isEmpty, "Expected rule to hit fixture: \(rule.id)")
            XCTAssertTrue(output.contains("RuleFixture_"), "Expected file reference for rule: \(rule.id)")
        }
    }

    private func runBash(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stdout

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func boundaryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func boundaryConfigURL() throws -> URL {
        boundaryRoot()
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("closeout_boundary_patterns.json", isDirectory: false)
    }

    private func boundarySchemaURL() throws -> URL {
        boundaryRoot()
            .appendingPathComponent("schemas", isDirectory: true)
            .appendingPathComponent("closeout_boundary_patterns.schema.json", isDirectory: false)
    }

    private func loadBoundaryConfig() throws -> BoundaryConfig {
        let configURL = try boundaryConfigURL()
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BoundaryConfig.self, from: data)
    }

}
