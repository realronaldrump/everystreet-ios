import Foundation

enum CachePolicy {
    static let recentFreshness: TimeInterval = 60 * 60 * 6
    static let historicalFreshness: TimeInterval = 60 * 60 * 24 * 7

    static func maxAge(for interval: DateInterval, now: Date = .now) -> TimeInterval {
        let thirtyDaysAgo = now.addingTimeInterval(-60 * 60 * 24 * 30)
        if interval.end >= thirtyDaysAgo {
            return recentFreshness
        }
        return historicalFreshness
    }

    static func isFresh(lastSyncDate: Date?, interval: DateInterval, now: Date = .now) -> Bool {
        guard let lastSyncDate else { return false }
        let maxAge = maxAge(for: interval, now: now)
        return now.timeIntervalSince(lastSyncDate) <= maxAge
    }
}
