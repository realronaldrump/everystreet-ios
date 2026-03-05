import Foundation
import Observation

@MainActor
@Observable
final class PlacesViewModel {
    private let repository: PlacesRepository

    var places: [PlaceSummary] = []
    var selectedPlace: PlaceSummary?
    var selectedPlaceTrips: PlaceTripsSnapshot?

    var isLoading = false
    var errorMessage: String?

    init(repository: PlacesRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            places = try await repository.loadPlaces()
            if let first = places.first {
                await select(place: first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func select(place: PlaceSummary) async {
        selectedPlace = place

        do {
            selectedPlaceTrips = try await repository.loadPlaceTrips(placeID: place.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
