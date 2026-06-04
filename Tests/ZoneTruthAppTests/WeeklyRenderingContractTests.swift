import XCTest
@testable import ZoneTruthApp
@testable import ZoneTruthCore

// P3a — Rendering Contract Lock
//
// Three invariants that must hold across all future changes to the weekly
// dashboard rendering layer. These tests guard the gap between semantic
// classifiers (which fire correctly) and the final rendered text
// (which is where overclaiming historically appears).

final class WeeklyRenderingContractTests: XCTestCase {

    // Contract 1: .noSignal must never render as a positive direction label.
    // "維持期" is a positive training observation; .noSignal is an evidence gap,
    // not a direction. If it renders as "維持期", the system fabricates a
    // training signal from absence of evidence.
    func testNoSignalNeverRendersMaintenance() {
        let allAuthorities: [WeeklyDecisionAuthority] = [.observational, .boundedInference, .weakInference]
        for authority in allAuthorities {
            let label = WeeklyAdaptationDirection.noSignal.admissibleLabel(for: authority)
            XCTAssertFalse(
                label.contains("維持期"),
                "noSignal + \(authority) must not contain '維持期', got: \(label)"
            )
        }
    }

    // Contract 2: .functionalFatigue must never render the clinical term.
    // The classifier fires on consecutiveTrainingDays alone — that evidence
    // level cannot support a physiological fatigue diagnosis.
    // Covers both the admissibleLabel gate and the progressionBarLabel path
    // used by StateProgressionBar (which bypasses admissibleLabel).
    func testFunctionalFatigueNeverRendersClinicalTerm() {
        let allAuthorities: [WeeklyDecisionAuthority] = [.observational, .boundedInference, .weakInference]
        for authority in allAuthorities {
            let label = TrainingState.functionalFatigue.admissibleLabel(for: authority)
            XCTAssertFalse(
                label.contains("功能性疲勞"),
                "functionalFatigue.admissibleLabel(for: \(authority)) must not render clinical term, got: \(label)"
            )
        }
        XCTAssertFalse(
            TrainingState.functionalFatigue.progressionBarLabel.contains("功能性疲勞"),
            "progressionBarLabel must not render clinical term, got: \(TrainingState.functionalFatigue.progressionBarLabel)"
        )
    }

    // Contract 3: CTA wording must be bounded by authority tier.
    // .boundedInference must append a "觀察體感" qualifier (softer directive).
    // .weakInference must prepend the "訊號有限" disclaimer (weakest authority).
    func testCTAWordingBoundedByAuthorityTier() {
        let base = "本週訓練節奏尚可，下週視體感微調強度。"

        let bounded = WeeklyCTAPresenter.render(base: base, for: .boundedInference, goal: nil, goalSignal: nil)
        XCTAssertTrue(
            bounded.contains("觀察體感"),
            "boundedInference CTA must contain '觀察體感', got: \(bounded)"
        )

        let weak = WeeklyCTAPresenter.render(base: base, for: .weakInference, goal: nil, goalSignal: nil)
        XCTAssertTrue(
            weak.hasPrefix("訊號有限，僅供方向參考"),
            "weakInference CTA must start with '訊號有限，僅供方向參考', got: \(weak)"
        )
    }

    // Supplementary: all StateProgressionBar state labels must be clinical-term free.
    // StateProgressionBar renders state.progressionBarLabel for every state in
    // TrainingState.progression — this test locks the full progression set.
    func testProgressionBarLabelSetContainsNoClinicalTerms() {
        for state in TrainingState.progression {
            XCTAssertFalse(
                state.progressionBarLabel.contains("功能性疲勞"),
                "StateProgressionBar label for '\(state.rawValue)' must not contain clinical term, got: \(state.progressionBarLabel)"
            )
        }
    }

    // Contract 4: weekly rendering must not absorb single-workout metric disclosure
    // into stronger measured/precise claims. Weekly summaries aggregate observation
    // signals; they do not measure VO2 max, exact Zone 2 thresholds, or strength.
    func testWeeklyRenderingContainsNoMetricMeasurementClaims() throws {
        let sourceText = try weeklyDashboardSourceText()
        let presenterText = weeklyPresenterSurfaceText()
        let combinedText = sourceText + "\n" + presenterText
        let forbiddenTerms = [
            "VO2 max 實測",
            "true VO2 max",
            "lab-equivalent",
            "精準 Zone 2",
            "exact Zone 2",
            "optimal Zone 2",
            "1RM",
            "肌力測量",
            "force output"
        ]

        for term in forbiddenTerms {
            XCTAssertFalse(
                combinedText.localizedCaseInsensitiveContains(term),
                "Weekly rendering must not contain metric measurement overclaim term '\(term)'."
            )
        }
    }

    private func weeklyPresenterSurfaceText() -> String {
        var labels: [String] = []
        for authority in [WeeklyDecisionAuthority.observational, .boundedInference, .weakInference] {
            labels.append(WeeklyCTAPresenter.render(
                base: "本週訓練節奏尚可，下週視體感微調強度。",
                for: authority,
                goal: nil,
                goalSignal: nil
            ))
            labels.append(WeeklyAdaptationDirection.noSignal.admissibleLabel(for: authority))
            labels.append(TrainingState.functionalFatigue.admissibleLabel(for: authority))
        }
        labels.append(contentsOf: TrainingState.progression.map(\.progressionBarLabel))
        return labels.joined(separator: "\n")
    }

    private func weeklyDashboardSourceText() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent("Sources/ZoneTruthApp/WeeklyDashboardView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
