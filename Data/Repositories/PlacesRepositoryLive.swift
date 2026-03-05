import Foundation

@MainActor
final class PlacesRepositoryLive: PlacesRepository {
    func loadPlaces() async throws -> [PlaceSummary] {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/places/statistics")
        }
        return try PlacesAPIParser.parsePlaceStatsList(data: data)
            .sorted { ($0.totalVisits ?? 0) > ($1.totalVisits ?? 0) }
    }

    func loadPlaceTrips(placeID: String) async throws -> PlaceTripsSnapshot {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/places/\(placeID)/trips")
        }
        return try PlacesAPIParser.parsePlaceTrips(data: data)
    }

    func loadPlaceStats(placeID: String) async throws -> PlaceSummary {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/places/\(placeID)/statistics")
        }
        return try PlacesAPIParser.parsePlaceStats(data: data)
    }

    private func makeClient() -> APIClient {
        let baseURL = AppSettingsStore.shared.apiBaseURL
        return APIClient(baseURL: baseURL)
    }
}
