import Foundation

struct ServiceHealthSnapshot: Equatable {
    let isHealthy: Bool
    let overallStatus: String
    let message: String
    let lastUpdated: Date?
}
