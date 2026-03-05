import Foundation

@MainActor
final class CoverageRepositoryLive: CoverageRepository {
    func loadCoverageAreas() async throws -> [CoverageArea] {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/coverage/areas")
        }

        return try CoverageAPIParser.parseAreas(data: data)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func loadCoverageAreaDetail(id: String) async throws -> CoverageAreaDetail {
        let client = makeClient()
        let data = try await TaskRetry.run {
            try await client.get(path: "api/coverage/areas/\(id)")
        }
        return try CoverageAPIParser.parseAreaDetail(data: data)
    }

    func loadStreets(areaID: String, boundingBox: TripBoundingBox) async throws -> CoverageStreetsSnapshot {
        let client = makeClient()
        let query = [
            URLQueryItem(name: "min_lon", value: boundingBox.minLon.coverageQueryValue),
            URLQueryItem(name: "min_lat", value: boundingBox.minLat.coverageQueryValue),
            URLQueryItem(name: "max_lon", value: boundingBox.maxLon.coverageQueryValue),
            URLQueryItem(name: "max_lat", value: boundingBox.maxLat.coverageQueryValue),
        ]

        let data = try await TaskRetry.run {
            try await client.get(path: "api/coverage/areas/\(areaID)/streets", query: query)
        }

        return try CoverageAPIParser.parseStreets(data: data)
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: AppSettingsStore.shared.apiBaseURL)
    }
}

private extension Double {
    var coverageQueryValue: String {
        String(format: "%.7f", self)
    }
}
