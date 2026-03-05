import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MapTabViewModel {
    private let repository: TripsRepository
    private let coordinateCache: LRUCoordinateCache

    var allTrips: [TripSummary] = []
    var visibleTrips: [TripSummary] = []
    var selectedTrip: TripSummary?

    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    )

    var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
    )

    var zoomBucket: ZoomBucket = .mid
    var densityPoints: [(coordinate: CLLocationCoordinate2D, weight: Int)] = []

    var isLoading = false
    var errorMessage: String?

    init(repository: TripsRepository, coordinateCache: LRUCoordinateCache) {
        self.repository = repository
        self.coordinateCache = coordinateCache
    }

    func load(query: TripQuery, appModel: AppModel) async {
        isLoading = true
        errorMessage = nil
        appModel.markSyncStarted()

        do {
            let trips = try await repository.loadTrips(query: query)
            allTrips = trips
            updateVisibleTrips()
            let lastSync = await repository.lastSyncDate(for: query)
            appModel.lastUpdated = lastSync
            appModel.markSyncFinished(at: lastSync ?? .now)
        } catch {
            if !allTrips.isEmpty {
                appModel.markSyncStale()
            } else {
                appModel.markSyncFailure(error.localizedDescription)
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh(query: TripQuery, appModel: AppModel) async {
        appModel.markSyncStarted()

        do {
            let trips = try await repository.refresh(query: query)
            allTrips = trips
            updateVisibleTrips()
            appModel.markSyncFinished()
        } catch {
            appModel.markSyncFailure(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func update(region: MKCoordinateRegion) {
        currentRegion = region
        zoomBucket = MapGeometry.zoomBucket(for: region)
        updateVisibleTrips()
    }

    func coordinates(for trip: TripSummary, level: GeometryDetailLevel) -> [CLLocationCoordinate2D] {
        let key = "\(trip.transactionId)-\(level.rawValue)"
        if let cached = coordinateCache.value(for: key) {
            return cached
        }

        let coords = trip.geometry(for: level)
        coordinateCache.set(coords, for: key)
        return coords
    }

    private func updateVisibleTrips() {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.20)

        let visible = allTrips.filter { trip in
            guard let bbox = trip.boundingBox else { return false }
            return bbox.intersects(visibleBox)
        }

        let limit: Int
        switch zoomBucket {
        case .low: limit = 400
        case .mid: limit = 1_200
        case .high: limit = 2_000
        }

        visibleTrips = Array(visible.prefix(limit))

        if zoomBucket == .low {
            densityPoints = MapGeometry.densityPoints(
                from: visible,
                in: visibleBox,
                cellSizeDegrees: 0.05
            )
            .prefix(240)
            .map { $0 }
        } else {
            densityPoints = []
        }
    }
}
