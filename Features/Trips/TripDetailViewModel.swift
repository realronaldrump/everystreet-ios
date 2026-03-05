import Foundation
import Observation

@MainActor
@Observable
final class TripDetailViewModel {
    private let repository: TripsRepository

    var detail: TripDetail?
    var relatedTrips: [TripSummary] = []
    var isLoading = false
    var errorMessage: String?

    init(repository: TripsRepository) {
        self.repository = repository
    }

    func load(tripID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await repository.loadTripDetail(id: tripID)
            detail = loaded

            if let date = loaded.startTime {
                let dayStart = Calendar.current.startOfDay(for: date)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let query = TripQuery(dateRange: DateInterval(start: dayStart, end: dayEnd), imei: nil, source: .rawTripsOnly)
                relatedTrips = try await repository.loadTrips(query: query)
                    .filter { $0.transactionId != tripID }
                    .prefix(12)
                    .map { $0 }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
