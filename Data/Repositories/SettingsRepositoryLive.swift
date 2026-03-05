import Foundation

@MainActor
final class SettingsRepositoryLive: SettingsRepository {
    func loadHealth() async throws -> ServiceHealthSnapshot {
        let baseURL = AppSettingsStore.shared.apiBaseURL
        let client = APIClient(baseURL: baseURL)
        let data = try await client.get(path: "api/status/health")
        return try PlacesAPIParser.parseHealth(data: data)
    }
}
