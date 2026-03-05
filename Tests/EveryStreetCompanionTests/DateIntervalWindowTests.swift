import Foundation
import XCTest
@testable import EveryStreetCompanion

final class DateIntervalWindowTests: XCTestCase {
    func testMonthlyWindowsSplitsAcrossMonths() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let interval = DateInterval(start: start, end: end)

        let windows = interval.monthlyWindows(calendar: calendar)
        XCTAssertGreaterThanOrEqual(windows.count, 2)
        XCTAssertEqual(windows.first?.start, calendar.startOfDay(for: start))
        XCTAssertEqual(windows.last?.end, end)
    }

    func testCachePolicyFreshness() {
        let range = DateInterval(start: Date().addingTimeInterval(-2_000), end: .now)
        let lastSync = Date().addingTimeInterval(-60)
        XCTAssertTrue(CachePolicy.isFresh(lastSyncDate: lastSync, interval: range))
    }
}
