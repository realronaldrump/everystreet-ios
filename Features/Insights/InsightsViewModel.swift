import Foundation
import Observation

@MainActor
@Observable
final class InsightsViewModel {
    private let repository: DashboardRepository

    var metrics: MetricsSnapshot?
    var analytics: TripAnalyticsSnapshot?
    var behavior: DriverBehaviorSnapshot?

    var isLoading = false
    var errorMessage: String?

    init(repository: DashboardRepository) {
        self.repository = repository
    }

    func load(range: DateInterval) async {
        isLoading = true
        errorMessage = nil

        do {
            metrics = try await repository.loadMetrics(range: range)
            analytics = try await repository.loadTripAnalytics(range: range)
            behavior = try await repository.loadDriverBehavior(range: range)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
