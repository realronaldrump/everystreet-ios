import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let authRepository: AuthRepository
    let tripsRepository: TripsRepository
    let settingsRepository: SettingsRepository
    let coverageRepository: CoverageRepository
    let coordinateCache = LRUCoordinateCache()

    init(inMemory: Bool = false) throws {
        self.modelContainer = try PersistenceController.makeContainer(inMemory: inMemory)
        self.authRepository = AuthRepositoryLive()
        self.tripsRepository = TripsRepositoryLive(container: modelContainer)
        self.settingsRepository = SettingsRepositoryLive()
        self.coverageRepository = CoverageRepositoryLive()
    }
}
