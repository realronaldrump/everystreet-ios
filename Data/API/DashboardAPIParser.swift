import Foundation

enum DashboardAPIParser {
    static func parseMetrics(data: Data) throws -> MetricsSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "metrics")
        }

        return MetricsSnapshot(
            totalTrips: object.int("total_trips") ?? 0,
            totalDistance: object.double("total_distance") ?? 0,
            totalDurationSeconds: object.double("total_duration_seconds") ?? 0,
            avgDistance: object.double("avg_distance") ?? 0,
            avgDrivingTime: object.double("avg_driving_time") ?? 0,
            avgSpeed: object.double("avg_speed") ?? 0,
            maxSpeed: object.double("max_speed") ?? 0,
            avgStartTime: object.string("avg_start_time")
        )
    }

    static func parseTripAnalytics(data: Data) throws -> TripAnalyticsSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "trip-analytics")
        }

        let daily = (object["daily_distances"] as? [[String: Any]] ?? []).map { item in
            TripAnalyticsPoint(
                label: item.string("date") ?? "",
                value: item.double("distance") ?? 0,
                count: item.int("count") ?? 0,
                date: JSONHelpers.date(from: item["date"])
            )
        }

        let weekday = (object["weekday_distribution"] as? [[String: Any]] ?? []).map { item in
            let day = item.int("day") ?? 0
            return TripAnalyticsPoint(
                label: weekdayLabel(day),
                value: Double(item.int("count") ?? 0),
                count: item.int("count") ?? 0,
                date: nil
            )
        }

        let time = (object["time_distribution"] as? [[String: Any]] ?? []).map { item in
            let hour = item.int("hour") ?? 0
            return TripAnalyticsPoint(
                label: String(format: "%02d:00", hour),
                value: Double(item.int("count") ?? 0),
                count: item.int("count") ?? 0,
                date: nil
            )
        }

        return TripAnalyticsSnapshot(dailyDistances: daily, weekdayDistribution: weekday, timeDistribution: time)
    }

    static func parseDriverBehavior(data: Data) throws -> DriverBehaviorSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "driver-behavior")
        }

        let monthly = (object["monthly"] as? [[String: Any]] ?? []).map { item in
            TripAnalyticsPoint(
                label: item.string("month") ?? item.string("label") ?? "",
                value: item.double("distance") ?? item.double("value") ?? 0,
                count: item.int("count") ?? 0,
                date: nil
            )
        }

        let weekly = (object["weekly"] as? [[String: Any]] ?? []).map { item in
            TripAnalyticsPoint(
                label: item.string("week") ?? item.string("label") ?? "",
                value: item.double("distance") ?? item.double("value") ?? 0,
                count: item.int("count") ?? 0,
                date: nil
            )
        }

        return DriverBehaviorSnapshot(
            totalTrips: object.int("totalTrips"),
            totalDistance: object.double("totalDistance"),
            maxSpeed: object.double("maxSpeed"),
            avgSpeed: object.double("avgSpeed"),
            hardBrakingCount: object.int("hardBrakingCounts"),
            hardAccelerationCount: object.int("hardAccelerationCounts"),
            fuelConsumed: object.double("fuelConsumed"),
            totalIdleDuration: object.double("totalIdleDuration"),
            monthlySeries: monthly,
            weeklySeries: weekly
        )
    }

    private static func weekdayLabel(_ day: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        if day >= 0, day < symbols.count {
            return symbols[day]
        }
        return "Day \(day)"
    }
}
