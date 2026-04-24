import Foundation

public enum SampleWorkoutCases {
    public static func zone2ReferenceCases() -> [WorkoutInput] {
        let start = Date(timeIntervalSince1970: 0)

        return [
            WorkoutInput(
                workoutType: .running,
                startDate: start,
                endDate: start.addingTimeInterval(24 * 60),
                heartRateSamples: makeSamples(start: start, values: Array(repeating: 118, count: 24)),
                intent: .zone2
            ),
            WorkoutInput(
                workoutType: .running,
                startDate: start.addingTimeInterval(86_400),
                endDate: start.addingTimeInterval(86_400 + 24 * 60),
                heartRateSamples: makeSamples(
                    start: start.addingTimeInterval(86_400),
                    values: [116, 117, 118, 120, 121, 122, 123, 124, 126, 128, 129, 130, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]
                ),
                intent: .zone2
            ),
            WorkoutInput(
                workoutType: .swimming,
                startDate: start.addingTimeInterval(172_800),
                endDate: start.addingTimeInterval(172_800 + 24 * 60),
                heartRateSamples: makeSamples(
                    start: start.addingTimeInterval(172_800),
                    values: [118, 119, 120, 121, 123, 124, 126, 128, 129, 131, 132, 134, 135, 137, 138, 139, 140, 142, 143, 144, 145, 146, 147, 148]
                ),
                intent: .zone2
            ),
        ]
    }

    private static func makeSamples(start: Date, values: [Double]) -> [HeartRateSample] {
        values.enumerated().map { index, bpm in
            HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(index * 60)), bpm: bpm)
        }
    }
}
