import Foundation

@MainActor
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private enum Keys {
        static let selectedPreset = "selected_date_preset"
        static let customStart = "custom_start_date"
        static let customEnd = "custom_end_date"
        static let selectedCoverageAreaID = "selected_coverage_area_id"
    }

    private static let fixedAPIBaseURL = URL(string: "https://www.everystreet.me")!
    private let defaults = UserDefaults.standard

    var apiBaseURL: URL {
        Self.fixedAPIBaseURL
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

    var selectedCoverageAreaID: String? {
        get {
            guard let value = defaults.string(forKey: Keys.selectedCoverageAreaID) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed?.isEmpty == false ? trimmed : nil, forKey: Keys.selectedCoverageAreaID)
        }
    }
}
