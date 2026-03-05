import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            CachedTripRecord.self,
            CachedVehicleRecord.self,
            CachedWindowRecord.self,
            CachedDashboardSnapshot.self
        ])

        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
