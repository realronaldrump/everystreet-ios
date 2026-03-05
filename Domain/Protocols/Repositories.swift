import Foundation
import CoreLocation

@MainActor
protocol TripsRepository {
    func loadTrips(query: TripQuery) async throws -> [TripSummary]
    func loadTripDetail(id: String) async throws -> TripDetail
    func loadTripMapBundle(query: TripQuery) async throws -> TripMapBundle
    func prefetch(range: DateInterval) async
    func refresh(query: TripQuery) async throws -> [TripSummary]
    func loadVehicles(forceRefresh: Bool) async throws -> [Vehicle]
    func firstTripDate() async throws -> Date?
    func lastSyncDate(for query: TripQuery) async -> Date?
    func cacheStats() async -> TripCacheStats
    func clearCache() async throws
}

@MainActor
protocol SettingsRepository {
    func loadHealth() async throws -> ServiceHealthSnapshot
}

@MainActor
protocol CoverageRepository {
    func loadCoverageAreas() async throws -> [CoverageArea]
    func loadCoverageAreaDetail(id: String) async throws -> CoverageAreaDetail
    func loadCoverageMapBundle(
        areaID: String,
        status: CoverageMapStatusFilter
    ) async throws -> CoverageMapBundle
    func loadNavigationSuggestions(
        areaID: String,
        origin: CLLocationCoordinate2D,
        limit: Int
    ) async throws -> CoverageNavigationSuggestionSet
}

struct TripCacheStats: Equatable {
    let tripCount: Int
    let windowCount: Int
    let vehicleCount: Int
    let estimatedBytes: Int64
}
