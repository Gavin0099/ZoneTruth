import Foundation

public enum SampleWorkoutCases {
    public static func zone2ValidationCases() -> [LabeledWorkoutCase] {
        let start = Date(timeIntervalSince1970: 0)

        return [
            LabeledWorkoutCase(
                name: "steady_zone2_run",
                summary: "Steady aerobic run with low drift and no meaningful Zone 3 leakage.",
                workout: WorkoutInput(
                    workoutType: .running,
                    startDate: start,
                    endDate: start.addingTimeInterval(32 * 60),
                    heartRateSamples: makeSamples(
                        start: start,
                        values: [96, 102, 108, 112, 116, 118, 118, 119, 118, 118, 119, 118, 118, 119, 118, 119, 118, 119, 120, 119, 119, 120, 119, 120, 119, 120, 119, 118, 116, 112, 108, 102]
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .pass,
                expectedReasonSnippets: ["10% 以下", "5% 以下"]
            ),
            LabeledWorkoutCase(
                name: "leaky_zone2_run",
                summary: "Mostly aerobic run that spends a little too much time in Zone 3 and drifts mildly late.",
                workout: WorkoutInput(
                    workoutType: .running,
                    startDate: start.addingTimeInterval(86_400),
                    endDate: start.addingTimeInterval(86_400 + 32 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(86_400),
                        values: [97, 102, 107, 111, 114, 115, 116, 116, 117, 117, 118, 118, 118, 119, 119, 119, 120, 121, 122, 123, 123, 124, 124, 125, 125, 126, 126, 126, 127, 121, 112, 104]
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .warning,
                expectedReasonSnippets: ["10% 到 20%", "5% 到 8%"]
            ),
            LabeledWorkoutCase(
                name: "drifting_swim",
                summary: "Session ramps into Zone 3 and Zone 4 enough that it should fail as a Zone 2 workout.",
                workout: WorkoutInput(
                    workoutType: .swimming,
                    startDate: start.addingTimeInterval(172_800),
                    endDate: start.addingTimeInterval(172_800 + 32 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(172_800),
                        values: [98, 104, 109, 113, 116, 118, 120, 122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 142, 144, 145, 146, 147, 148, 149, 148, 147, 146, 144, 138, 128, 116, 108]
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .fail,
                expectedReasonSnippets: ["超過 20%", "超過 8%"]
            ),
            LabeledWorkoutCase(
                name: "badminton_activity_review",
                summary: "Mixed-intensity activity that should be treated as descriptive review rather than strict aerobic judgment.",
                workout: WorkoutInput(
                    workoutType: .mixed,
                    startDate: start.addingTimeInterval(259_200),
                    endDate: start.addingTimeInterval(259_200 + 28 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(259_200),
                        values: [92, 96, 101, 107, 114, 118, 122, 109, 116, 121, 110, 124, 118, 106, 113, 120, 111, 125, 117, 108, 114, 119, 110, 104, 99, 96, 94, 92]
                    ),
                    intent: .activityReview
                ),
                expectedVerdict: .pass,
                expectedReasonSnippets: ["一般活動"]
            ),
            LabeledWorkoutCase(
                name: "sparse_hr_cycling",
                summary: "Adequate session duration but too few HR samples after sanitization due to recording gaps.",
                workout: WorkoutInput(
                    workoutType: .cycling,
                    startDate: start.addingTimeInterval(5 * 86_400),
                    endDate: start.addingTimeInterval(5 * 86_400 + 30 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(5 * 86_400),
                        values: [95, 112, 118, 119, 120, 121, 116],
                        intervalSeconds: 5 * 60
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .fail,
                expectedReasonSnippets: ["過低"]
            ),
            LabeledWorkoutCase(
                name: "high_drift_zone2_ride",
                summary: "Zone 3 leakage is minimal but HR rises steadily across the session, causing a drift failure.",
                workout: WorkoutInput(
                    workoutType: .cycling,
                    startDate: start.addingTimeInterval(6 * 86_400),
                    endDate: start.addingTimeInterval(6 * 86_400 + 35 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(6 * 86_400),
                        values: [96, 100, 104, 108, 110,
                                 110, 110, 110, 110, 111, 110, 111, 110, 110, 111, 110, 111, 110,
                                 120, 121, 122, 122, 123, 123, 123, 123, 124, 124, 124, 124, 124, 124,
                                 118, 110, 102]
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .fail,
                expectedReasonSnippets: ["超過 8%"]
            ),
            LabeledWorkoutCase(
                name: "unstable_zone2_run",
                summary: "Average HR stays in Zone 2 and drift is low, but high beat-to-beat variability causes a warning.",
                workout: WorkoutInput(
                    workoutType: .running,
                    startDate: start.addingTimeInterval(7 * 86_400),
                    endDate: start.addingTimeInterval(7 * 86_400 + 30 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(7 * 86_400),
                        values: [95, 100, 104, 108, 110,
                                 111, 124, 111, 124, 111, 124, 111, 124, 111, 124, 111, 124, 111, 124,
                                 111, 124, 111, 124, 111, 124, 111, 124,
                                 116, 108, 100]
                    ),
                    intent: .zone2
                ),
                expectedVerdict: .warning,
                expectedReasonSnippets: ["變異度為中等"]
            ),
        ]
    }

    public static func vo2IntervalValidationCases() -> [LabeledWorkoutCase] {
        let start = Date(timeIntervalSince1970: 10 * 86_400) // Day 10

        return [
            LabeledWorkoutCase(
                name: "solid_vo2_max_intervals",
                summary: "High intensity intervals reaching Zone 4 and Zone 5 consistently.",
                workout: WorkoutInput(
                    workoutType: .running,
                    startDate: start,
                    endDate: start.addingTimeInterval(40 * 60),
                    heartRateSamples: makeSamples(
                        start: start,
                        values: [90, 100, 110, 120, // Warmup
                                 145, 150, 155, 120, // Interval 1 + Rest
                                 146, 152, 158, 121, // Interval 2 + Rest
                                 147, 153, 159, 122, // Interval 3 + Rest
                                 148, 154, 160, 123, // Interval 4 + Rest
                                 110, 100, 90]        // Cooldown
                    ),
                    intent: .vo2Interval
                ),
                expectedVerdict: .pass,
                expectedReasonSnippets: ["停留的時間充足"]
            ),
            LabeledWorkoutCase(
                name: "low_intensity_intervals",
                summary: "Intervals that only reach Zone 3, failing to hit VO2 max intensities.",
                workout: WorkoutInput(
                    workoutType: .cycling,
                    startDate: start.addingTimeInterval(86_400),
                    endDate: start.addingTimeInterval(86_400 + 30 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(86_400),
                        values: [95, 105, 115, 125, // Warmup
                                 130, 132, 130, 120, // Interval 1
                                 131, 133, 131, 121, // Interval 2
                                 132, 134, 132, 122, // Interval 3
                                 110, 100, 95]        // Cooldown
                    ),
                    intent: .vo2Interval
                ),
                expectedVerdict: .fail,
                expectedReasonSnippets: ["時間過少"]
            )
        ]
    }

    public static func strengthValidationCases() -> [LabeledWorkoutCase] {
        let start = Date(timeIntervalSince1970: 15 * 86_400) // Day 15

        return [
            LabeledWorkoutCase(
                name: "traditional_strength_training",
                summary: "Strength session with adequate rest, keeping average HR low.",
                workout: WorkoutInput(
                    workoutType: .strengthTraining,
                    startDate: start,
                    endDate: start.addingTimeInterval(45 * 60),
                    heartRateSamples: makeSamples(
                        start: start,
                        values: [85, 95, 110, 90, 115, 92, 112, 88, 118, 95, 110, 85]
                    ),
                    intent: .strength
                ),
                expectedVerdict: .pass,
                expectedReasonSnippets: ["典型範圍"]
            ),
            LabeledWorkoutCase(
                name: "metabolic_strength_circuit",
                summary: "High-intensity circuit training with high average HR.",
                workout: WorkoutInput(
                    workoutType: .strengthTraining,
                    startDate: start.addingTimeInterval(86_400),
                    endDate: start.addingTimeInterval(86_400 + 30 * 60),
                    heartRateSamples: makeSamples(
                        start: start.addingTimeInterval(86_400),
                        values: [100, 120, 135, 140, 138, 135, 142, 145, 140, 138, 135, 120]
                    ),
                    intent: .strength
                ),
                expectedVerdict: .fail,
                expectedReasonSnippets: ["非常高", "體能代謝"]
            )
        ]
    }

    public static func previewWorkouts() -> [WorkoutInput] {
        zone2ValidationCases().map(\.workout) +
        vo2IntervalValidationCases().map(\.workout) +
        strengthValidationCases().map(\.workout)
    }

    private static func makeSamples(start: Date, values: [Double], intervalSeconds: TimeInterval = 60) -> [HeartRateSample] {
        values.enumerated().map { index, bpm in
            HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(index) * intervalSeconds), bpm: bpm)
        }
    }
}
