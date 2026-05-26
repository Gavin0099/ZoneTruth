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
}
