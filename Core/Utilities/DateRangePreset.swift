import Foundation

enum DateRangePreset: String, CaseIterable, Identifiable, Codable {
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
    case ytd = "YTD"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }

    func dateInterval(now: Date = .now, firstTripDate: Date?) -> DateInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .sevenDays:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday, end: now)
        case .thirtyDays:
            return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday, end: now)
        case .ninetyDays:
            return DateInterval(start: calendar.date(byAdding: .day, value: -90, to: startOfToday) ?? startOfToday, end: now)
        case .ytd:
            let year = calendar.component(.year, from: now)
            let comps = DateComponents(year: year, month: 1, day: 1)
            let ytdStart = calendar.date(from: comps) ?? startOfToday
            return DateInterval(start: ytdStart, end: now)
        case .all:
            return DateInterval(start: firstTripDate ?? (calendar.date(byAdding: .year, value: -5, to: now) ?? now), end: now)
        case .custom:
            return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday, end: now)
        }
    }
}
