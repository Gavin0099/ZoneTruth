import Foundation
import XCTest

final class GovernanceBoundaryGuardTests: XCTestCase {
    private struct BoundaryConfig: Decodable {
        let appSourceBoundaryRules: [AppSourceBoundaryRule]
        let commentFilterRegex: String
        let appTestBoundaryRegex: String
    }

    private struct AppSourceBoundaryRule: Decodable {
        let id: String
        let regex: String
        let rationale: String
    }

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
        XCTAssertFalse(config.appTestBoundaryRegex.isEmpty)
        XCTAssertFalse(config.appSourceBoundaryRules.isEmpty)
        XCTAssertTrue(config.appSourceBoundaryRules.allSatisfy { !$0.id.isEmpty && !$0.regex.isEmpty && !$0.rationale.isEmpty })
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
        let cmd = """
        grep -RIn --include="*.swift" -E '\(config.appTestBoundaryRegex)' "\(escapedRoot)/Tests/ZoneTruthAppTests" | grep -Ev '\(config.commentFilterRegex)' || true
        """
        let output = try runBash(cmd)

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(output.contains("BoundaryHitSample.swift:"))
        XCTAssertTrue(output.contains("WeeklyInferenceClassifier.classify"))
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
