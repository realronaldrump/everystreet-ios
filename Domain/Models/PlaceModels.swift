import Foundation

struct PlaceSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let totalVisits: Int?
    let averageTimeSpent: String?
    let firstVisit: Date?
    let lastVisit: Date?
    let averageTimeSinceLastVisit: String?
}

struct PlaceTripSummary: Identifiable, Hashable {
    let id: String
    let transactionId: String
    let endTime: Date?
    let departureTime: Date?
    let timeSpent: String?
    let timeSinceLastVisit: String?
    let source: String?
    let distance: Double?
}

struct PlaceTripsSnapshot: Equatable {
    let placeName: String
    let trips: [PlaceTripSummary]
}

struct ServiceHealthSnapshot: Equatable {
    let isHealthy: Bool
    let overallStatus: String
    let message: String
    let lastUpdated: Date?
}
