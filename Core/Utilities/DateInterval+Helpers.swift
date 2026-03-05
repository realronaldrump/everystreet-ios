import Foundation

extension DateInterval {
    var isLargeWindow: Bool {
        duration > 60 * 60 * 24 * 30
    }

    var shortLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    func monthlyWindows(calendar: Calendar = .current) -> [DateInterval] {
        guard start <= end else { return [] }
        var windows: [DateInterval] = []
        var cursor = calendar.startOfDay(for: start)

        while cursor < end {
            let monthComponents = calendar.dateComponents([.year, .month], from: cursor)
            guard let monthStart = calendar.date(from: monthComponents),
                  let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else {
                break
            }

            let windowStart = max(cursor, start)
            let windowEnd = min(nextMonthStart, end)
            windows.append(DateInterval(start: windowStart, end: windowEnd))
            cursor = windowEnd
        }

        return windows.isEmpty ? [self] : windows
    }
}
