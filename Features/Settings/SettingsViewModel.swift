import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let tripsRepository: TripsRepository
    private let settingsRepository: SettingsRepository

    var cacheStats: TripCacheStats?
    var health: ServiceHealthSnapshot?
    var isLoading = false
    var statusMessage: String?

    init(tripsRepository: TripsRepository, settingsRepository: SettingsRepository) {
        self.tripsRepository = tripsRepository
        self.settingsRepository = settingsRepository
    }

    func load() async {
        isLoading = true

        cacheStats = await tripsRepository.cacheStats()
        health = await loadHealthIfPossible()

        isLoading = false
    }

    func clearCache() async {
        do {
            try await tripsRepository.clearCache()
            cacheStats = await tripsRepository.cacheStats()
            statusMessage = "Cache cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshHealth() async {
        health = await loadHealthIfPossible()
    }

    private func loadHealthIfPossible() async -> ServiceHealthSnapshot? {
        do {
            return try await settingsRepository.loadHealth()
        } catch {
            statusMessage = "Health endpoint unavailable"
            return nil
        }
    }
}
