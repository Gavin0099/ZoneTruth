import SwiftUI

@main
struct ZoneTruthApp: App {
    @StateObject private var viewModel: WorkoutListViewModel
    @StateObject private var settingsManager = SettingsManager()
    private let callbackHandler: StravaCallbackHandler?

    init() {
        let environment = AppEnvironment.live()
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: WorkoutListViewModel(
            repository: environment.repository,
            settingsManager: settings,
            stravaAuthorizationURL: environment.stravaAuthorizationURL
        ))
        callbackHandler = environment.stravaCallbackHandler
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(viewModel: viewModel, settingsManager: settingsManager)
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
