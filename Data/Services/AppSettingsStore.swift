import Foundation

@MainActor
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private enum Keys {
        static let apiBaseURL = "api_base_url"
        static let selectedPreset = "selected_date_preset"
        static let customStart = "custom_start_date"
        static let customEnd = "custom_end_date"
        static let selectedIMEI = "selected_imei"
    }

    private let defaults = UserDefaults.standard

    var apiBaseURL: URL {
        get {
            if let raw = defaults.string(forKey: Keys.apiBaseURL), let url = URL(string: raw) {
                return url
            }
            return URL(string: "https://www.everystreet.me")!
        }
        set {
            defaults.set(newValue.absoluteString, forKey: Keys.apiBaseURL)
        }
    }

    var selectedPreset: DateRangePreset {
        get {
            if let raw = defaults.string(forKey: Keys.selectedPreset), let preset = DateRangePreset(rawValue: raw) {
                return preset
            }
            return .thirtyDays
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedPreset)
        }
    }

    var customStartDate: Date? {
        get { defaults.object(forKey: Keys.customStart) as? Date }
        set { defaults.set(newValue, forKey: Keys.customStart) }
    }

    var customEndDate: Date? {
        get { defaults.object(forKey: Keys.customEnd) as? Date }
        set { defaults.set(newValue, forKey: Keys.customEnd) }
    }

    var selectedIMEI: String? {
        get { defaults.string(forKey: Keys.selectedIMEI) }
        set { defaults.set(newValue, forKey: Keys.selectedIMEI) }
    }
}
