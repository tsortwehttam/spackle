import Foundation

final class SettingsStore {
    private let key = "app.aisatsu.spackle.settings"

    func getSettings() -> AppSettings {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) else {
            return .default
        }
        let decoder = JSONDecoder()
        guard let s = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return s
    }

    func setSettings(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
