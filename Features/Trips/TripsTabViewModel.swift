import Foundation
import Observation

@MainActor
@Observable
final class TripsTabViewModel {
    private let repository: TripsRepository

    var trips: [TripSummary] = []
    var searchText = ""
    var isLoading = false
    var errorMessage: String?

    init(repository: TripsRepository) {
        self.repository = repository
    }

    func load(query: TripQuery, appModel: AppModel) async {
        isLoading = true
        errorMessage = nil

        do {
            trips = try await repository.loadTrips(query: query)
            if let lastSync = await repository.lastSyncDate(for: query) {
                appModel.lastUpdated = lastSync
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh(query: TripQuery) async {
        do {
            trips = try await repository.refresh(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredTrips: [TripSummary] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trips
        }

        let needle = searchText.lowercased()
        return trips.filter { trip in
            let haystack = [
                trip.startLocation,
                trip.destination,
                trip.transactionId,
                trip.vehicleLabel
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            return haystack.contains(needle)
        }
    }

    var groupedTrips: [(day: Date, trips: [TripSummary])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTrips) { calendar.startOfDay(for: $0.startTime) }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.startTime > $1.startTime }) }
            .sorted { $0.day > $1.day }
    }
}
