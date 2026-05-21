import SwiftUI

public struct ZoneTruthMainView: View {
    @StateObject private var viewModel: WorkoutListViewModel
    @StateObject private var settingsManager = SettingsManager()
    private let callbackHandler: StravaCallbackHandler?

    public init() {
        let environment = AppEnvironment.live()
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        let handler = environment.stravaCallbackHandler
        _viewModel = StateObject(wrappedValue: WorkoutListViewModel(
            repository: environment.repository,
            settingsManager: settings,
            stravaAuthorizationURL: environment.stravaAuthorizationURL,
            callbackHandler: handler
        ))
        callbackHandler = handler
    }

    public var body: some View {
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
