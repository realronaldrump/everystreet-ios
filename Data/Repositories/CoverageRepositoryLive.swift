import Foundation

@MainActor
final class CoverageRepositoryLive: CoverageRepository {
    private let mapBundleCache = MapBundleCacheStore()

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

    func loadCoverageMapBundle(
        areaID: String,
        status: CoverageMapStatusFilter
    ) async throws -> CoverageMapBundle {
        let client = makeClient()
        let query = [URLQueryItem(name: "status", value: status.apiValue)]
        let cacheKey = "coverage-map-bundle|\(areaID)|\(status.apiValue)"
        let cached = mapBundleCache.load(key: cacheKey)
        var headers: [String: String] = [:]
        if let cached {
            headers["If-None-Match"] = cached.etag
        }

        let payload = try await TaskRetry.run {
            try await client.get(
                path: "api/map/coverage/areas/\(areaID)/bundle",
                query: query,
                headers: headers,
                allowNotModified: true
            )
        }

        if payload.statusCode == 304, let cached {
            return try CoverageAPIParser.parseCoverageMapBundle(data: cached.payload)
        }

        let data = payload.data
        if let etag = payload.headerValue("ETag"), !etag.isEmpty {
            mapBundleCache.store(key: cacheKey, payload: data, etag: etag)
        }
        return try CoverageAPIParser.parseCoverageMapBundle(data: data)
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: AppSettingsStore.shared.apiBaseURL)
    }
}
