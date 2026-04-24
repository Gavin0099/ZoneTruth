import SwiftUI

@main
struct ZoneTruthApp: App {
    @StateObject private var viewModel = WorkoutListViewModel(
        repository: AppEnvironment.live().repository
    )

    var body: some Scene {
        WindowGroup {
            WorkoutListView(viewModel: viewModel)
        }
    }
}
