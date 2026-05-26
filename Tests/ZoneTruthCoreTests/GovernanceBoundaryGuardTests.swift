import Foundation
import XCTest

final class GovernanceBoundaryGuardTests: XCTestCase {
    func testAppTestBoundaryScanReturnsFileLineHitFormat() throws {
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
        grep -RIn --include="*.swift" -E 'WeeklyInferenceClassifier\\.classify|WeeklyConfidenceSemantics\\.calibrated|WeeklyFreshnessSignal\\.classify' "\(escapedRoot)/Tests/ZoneTruthAppTests" | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true
        """
        let output = try runBash(cmd)

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(output.contains("BoundaryHitSample.swift:"))
        XCTAssertTrue(output.contains("WeeklyInferenceClassifier.classify"))
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
}
