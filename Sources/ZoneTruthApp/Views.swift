import SwiftUI
import ZoneTruthCore

struct WorkoutListView: View {
    @ObservedObject var viewModel: WorkoutListViewModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                WorkoutSourceBannerView(
                    source: viewModel.currentSource,
                    statusMessage: viewModel.statusMessage,
                    isRefreshing: viewModel.isRefreshing,
                    isRequestingAuthorization: viewModel.isRequestingAuthorization,
                    canRequestHealthAccess: viewModel.canRequestHealthAccess,
                    onRequestHealthAccess: {
                        Task {
                            await viewModel.requestHealthAccess()
                        }
                    },
                    stravaAuthorizationURL: viewModel.canConnectStrava ? viewModel.stravaAuthorizationURL : nil
                )

                List(selection: $viewModel.selectedWorkout) {
                    ForEach(viewModel.workouts, id: \.id) { workout in
                        Button {
                            viewModel.selectWorkout(workout)
                        } label: {
                            WorkoutRowView(
                                workout: workout,
                                result: viewModel.analysisResult(for: workout)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("ZoneTruth")
        } detail: {
            if let workout = viewModel.selectedWorkout {
                WorkoutDetailView(
                    workout: workout,
                    selectedIntent: viewModel.selectedIntent,
                    result: viewModel.analysisResult(for: workout),
                    onIntentChanged: viewModel.updateIntent
                )
            } else {
                ContentUnavailableView("No Workout", systemImage: "heart.text.square")
            }
        }
        .task {
            await viewModel.refreshWorkouts()
        }
    }
}

struct WorkoutSourceBannerView: View {
    let source: WorkoutDataSource
    let statusMessage: String?
    let isRefreshing: Bool
    let isRequestingAuthorization: Bool
    let canRequestHealthAccess: Bool
    let onRequestHealthAccess: () -> Void
    var stravaAuthorizationURL: URL? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(source.rawValue)
                    .font(.headline)
                Spacer()
                if isRefreshing || isRequestingAuthorization {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canRequestHealthAccess {
                Button(action: onRequestHealthAccess) {
                    Text(isRequestingAuthorization ? "Requesting Apple Health Access..." : "Request Apple Health Access")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRequestingAuthorization || isRefreshing)
            }

            if let url = stravaAuthorizationURL {
                Button {
                    openURL(url)
                } label: {
                    Text("Connect Strava")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.04))
    }
}

struct WorkoutRowView: View {
    let workout: WorkoutInput
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workout.workoutType.rawValue.capitalized)
                .font(.headline)
            Text(workout.intent.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(result.verdict.rawValue.capitalized, systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 4)
    }

    private var statusSymbol: String {
        switch result.verdict {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch result.verdict {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        }
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent
    let result: AnalysisResult
    let onIntentChanged: (TrainingIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SummaryCardView(workout: workout, selectedIntent: selectedIntent, result: result)
                IntentPickerView(selectedIntent: selectedIntent, onIntentChanged: onIntentChanged)
                AnalysisResultView(result: result)
                SettingsView(policy: .default)
            }
            .padding(24)
        }
        .navigationTitle("Workout Detail")
    }
}

struct SummaryCardView: View {
    let workout: WorkoutInput
    let selectedIntent: TrainingIntent
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.title2.weight(.semibold))
            Text("\(workout.workoutType.rawValue.capitalized) | \(selectedIntent.rawValue)")
                .font(.headline)
            Text("Verdict: \(result.verdict.rawValue.capitalized)")
                .foregroundStyle(colorForVerdict(result.verdict))
            Text("Confidence: \(Int((result.confidence * 100).rounded()))%")
            Text("Duration: \(Int(workout.durationSeconds / 60)) min")
            if let stability = result.stabilityStandardDeviation {
                Text(String(format: "HR stability (std dev): %.1f bpm", stability))
            }
            if let drift = result.driftRatio {
                Text(String(format: "HR drift: %.1f%%", drift * 100))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func colorForVerdict(_ verdict: AnalysisVerdict) -> Color {
        switch verdict {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        }
    }
}

struct IntentPickerView: View {
    let selectedIntent: TrainingIntent
    let onIntentChanged: (TrainingIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Declared Intent")
                .font(.headline)
            Picker(
                "Intent",
                selection: Binding(
                    get: { selectedIntent },
                    set: { onIntentChanged($0) }
                )
            ) {
                Text(TrainingIntent.zone2.rawValue).tag(TrainingIntent.zone2)
                Text(TrainingIntent.activityReview.rawValue).tag(TrainingIntent.activityReview)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct AnalysisResultView: View {
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analysis Result")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Reasons")
                    .font(.headline)
                ForEach(result.reasons, id: \.self) { reason in
                    Text("- \(reason)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recommendations")
                    .font(.headline)
                ForEach(result.recommendations, id: \.self) { recommendation in
                    Text("- \(recommendation)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Zone Distribution")
                    .font(.headline)
                ForEach(TrainingZone.allCases, id: \.self) { zone in
                    let ratio = result.zoneDistribution.ratio(for: zone)
                    HStack {
                        Text("Zone \(zone.rawValue)")
                        Spacer()
                        Text("\(Int((ratio * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SettingsView: View {
    let policy: AnalysisPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Policy")
                .font(.headline)
            Text("Zone 2: \(Int(policy.zoneBounds.zone2LowerBound))-\(Int(policy.zoneBounds.zone2UpperBound)) bpm")
            Text("Warm-up exclusion: \(Int(policy.warmupExclusionSeconds / 60)) min")
            Text("Cool-down exclusion: \(Int(policy.cooldownExclusionSeconds / 60)) min")
            Text("Minimum duration: \(Int(policy.minimumDurationSeconds / 60)) min")
            Text("Minimum samples: \(policy.minimumSampleCount)")
            Text("This screen is still driven by defaults. HealthKit and personalization are the next phase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
