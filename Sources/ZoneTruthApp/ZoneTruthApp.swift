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
            intentOverrideStore: environment.intentOverrideStore,
            settingsManager: settings,
            stravaAuthorizationURL: environment.stravaAuthorizationURL,
            callbackHandler: handler,
            bodyCompositionLedger: environment.bodyCompositionLedger
        ))
        callbackHandler = handler
    }

    public var body: some View {
        TabView {
            WorkoutListView(viewModel: viewModel, settingsManager: settingsManager)
                .tabItem {
                    Label("訓練紀錄", systemImage: "figure.run")
                }

            NavigationStack {
                WeeklyDashboardView(viewModel: viewModel, settingsManager: settingsManager)
            }
            .tabItem {
                Label("本週", systemImage: "calendar")
            }
        }
        .tint(PremiumColor.skyBlue)
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
