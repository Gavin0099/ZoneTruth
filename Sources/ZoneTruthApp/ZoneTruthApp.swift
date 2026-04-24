import SwiftUI

@main
struct ZoneTruthApp: App {
    @StateObject private var viewModel: WorkoutListViewModel
    private let callbackHandler: StravaCallbackHandler?

    init() {
        let environment = AppEnvironment.live()
        _viewModel = StateObject(wrappedValue: WorkoutListViewModel(
            repository: environment.repository,
            stravaAuthorizationURL: environment.stravaAuthorizationURL
        ))
        callbackHandler = environment.stravaCallbackHandler
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(viewModel: viewModel)
                .onOpenURL { url in
                    Task {
                        let handled = await callbackHandler?.handle(url) ?? false
                        if handled {
                            await viewModel.refreshWorkouts()
                        }
                    }
                }
        }
    }
}
