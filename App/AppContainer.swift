import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let tripsRepository: TripsRepository
    let dashboardRepository: DashboardRepository
    let placesRepository: PlacesRepository
    let settingsRepository: SettingsRepository
    let coverageRepository: CoverageRepository
    let coordinateCache = LRUCoordinateCache()

    init(inMemory: Bool = false) throws {
        self.modelContainer = try PersistenceController.makeContainer(inMemory: inMemory)
        self.tripsRepository = TripsRepositoryLive(container: modelContainer)
        self.dashboardRepository = DashboardRepositoryLive(container: modelContainer)
        self.placesRepository = PlacesRepositoryLive()
        self.settingsRepository = SettingsRepositoryLive()
        self.coverageRepository = CoverageRepositoryLive()
    }
}
