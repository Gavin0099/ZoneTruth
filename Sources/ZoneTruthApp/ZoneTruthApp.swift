import SwiftUI

@main
struct ZoneTruthApp: App {
    @StateObject private var viewModel = WorkoutListViewModel(
        repository: MockWorkoutRepository()
    )

    var body: some Scene {
        WindowGroup {
            WorkoutListView(viewModel: viewModel)
        }
    }
}
