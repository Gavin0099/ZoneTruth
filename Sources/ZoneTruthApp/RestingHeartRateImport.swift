import Foundation

@MainActor
struct RestingHeartRateImporter {
    static func importFromAppleHealth(
        store: any HealthKitWorkoutStore,
        settingsManager: SettingsManager
    ) async -> String {
        guard store.isAvailable else {
            return "此裝置目前無法使用 Apple Health Resting HR。"
        }

        _ = await store.requestAuthorization()

        do {
            guard let imported = try await store.fetchRestingHeartRateBaseline() else {
                return "Apple Health 最近 7 天沒有可用的 Resting HR 資料。"
            }

            settingsManager.updateRestingHeartRate(imported)
            settingsManager.generateRestingHeartRateSuggestion()
            return "已匯入 Apple Health 最近 7 天平均 Resting HR \(Int(imported.rounded())) bpm，並產生 Zone 2 建議。"
        } catch HealthKitStoreError.unauthorized {
            return "尚未取得 Apple Health 讀取權限。"
        } catch {
            return "Apple Health Resting HR 匯入失敗，請稍後再試。"
        }
    }
}
