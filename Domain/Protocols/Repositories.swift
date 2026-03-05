import Foundation

@MainActor
protocol TripsRepository {
    func loadTrips(query: TripQuery) async throws -> [TripSummary]
    func loadTripDetail(id: String) async throws -> TripDetail
    func prefetch(range: DateInterval) async
    func refresh(query: TripQuery) async throws -> [TripSummary]
    func loadVehicles(forceRefresh: Bool) async throws -> [Vehicle]
    func firstTripDate() async throws -> Date?
    func lastSyncDate(for query: TripQuery) async -> Date?
    func cacheStats() async -> TripCacheStats
    func clearCache() async throws
}

@MainActor
protocol DashboardRepository {
    func loadMetrics(range: DateInterval) async throws -> MetricsSnapshot
    func loadTripAnalytics(range: DateInterval) async throws -> TripAnalyticsSnapshot
    func loadDriverBehavior(range: DateInterval) async throws -> DriverBehaviorSnapshot
}

@MainActor
protocol PlacesRepository {
    func loadPlaces() async throws -> [PlaceSummary]
    func loadPlaceTrips(placeID: String) async throws -> PlaceTripsSnapshot
    func loadPlaceStats(placeID: String) async throws -> PlaceSummary
}

@MainActor
protocol SettingsRepository {
    func loadHealth() async throws -> ServiceHealthSnapshot
}

@MainActor
protocol CoverageRepository {
    func loadCoverageAreas() async throws -> [CoverageArea]
    func loadCoverageAreaDetail(id: String) async throws -> CoverageAreaDetail
    func loadStreets(areaID: String, boundingBox: TripBoundingBox) async throws -> CoverageStreetsSnapshot
}

struct TripCacheStats: Equatable {
    let tripCount: Int
    let windowCount: Int
    let vehicleCount: Int
    let estimatedBytes: Int64
}
