import Foundation

struct MetricsSnapshot: Equatable, Codable {
    let totalTrips: Int
    let totalDistance: Double
    let totalDurationSeconds: Double
    let avgDistance: Double
    let avgDrivingTime: Double
    let avgSpeed: Double
    let maxSpeed: Double
    let avgStartTime: String?
}

struct TripAnalyticsPoint: Identifiable, Equatable, Codable {
    var id: String { label }
    let label: String
    let value: Double
    let count: Int
    let date: Date?
}

struct TripAnalyticsSnapshot: Equatable, Codable {
    let dailyDistances: [TripAnalyticsPoint]
    let weekdayDistribution: [TripAnalyticsPoint]
    let timeDistribution: [TripAnalyticsPoint]
}

struct DriverBehaviorSnapshot: Equatable, Codable {
    let totalTrips: Int?
    let totalDistance: Double?
    let maxSpeed: Double?
    let avgSpeed: Double?
    let hardBrakingCount: Int?
    let hardAccelerationCount: Int?
    let fuelConsumed: Double?
    let totalIdleDuration: Double?
    let monthlySeries: [TripAnalyticsPoint]
    let weeklySeries: [TripAnalyticsPoint]
}
