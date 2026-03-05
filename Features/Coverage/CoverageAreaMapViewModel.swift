import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CoverageAreaMapViewModel {
    private let areaID: String
    private let repository: CoverageRepository

    private var fetchTask: Task<Void, Never>?
    private var requestToken = UUID()
    private var hasLoaded = false

    var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
    )

    var filter: CoverageStreetFilter = .all
    var segments: [CoverageStreetSegment] = []
    var totalInViewport = 0
    var truncated = false
    var isLoading = false
    var errorMessage: String?

    var visibleSegments: [CoverageStreetSegment] {
        segments.filter { filter.matches($0.status) }
    }

    var counts: (driven: Int, undriven: Int, undriveable: Int) {
        segments.reduce(into: (driven: 0, undriven: 0, undriveable: 0)) { result, segment in
            switch segment.status {
            case .driven:
                result.driven += 1
            case .undriven:
                result.undriven += 1
            case .undriveable:
                result.undriveable += 1
            case .unknown:
                break
            }
        }
    }

    init(areaID: String, repository: CoverageRepository) {
        self.areaID = areaID
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            let detail = try await repository.loadCoverageAreaDetail(id: areaID)
            if let box = detail.boundingBox {
                let region = region(for: box)
                currentRegion = region
                cameraPosition = .region(region)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        scheduleStreetLoad(force: true)
    }

    func refresh() {
        scheduleStreetLoad(force: true)
    }

    func update(region: MKCoordinateRegion) {
        currentRegion = region
        scheduleStreetLoad()
    }

    func setFilter(_ filter: CoverageStreetFilter) {
        self.filter = filter
    }

    private func scheduleStreetLoad(force: Bool = false) {
        let region = currentRegion
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            if !force {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            await self.loadStreets(region: region)
        }
    }

    private func loadStreets(region: MKCoordinateRegion) async {
        let token = UUID()
        requestToken = token
        isLoading = true

        do {
            let box = MapGeometry.boundingBox(for: region).expanded(by: 0.06)
            let snapshot = try await repository.loadStreets(areaID: areaID, boundingBox: box)
            guard !Task.isCancelled, token == requestToken else { return }

            segments = snapshot.segments
            totalInViewport = snapshot.totalInViewport
            truncated = snapshot.truncated
            errorMessage = nil
            isLoading = false
        } catch {
            guard !Task.isCancelled, token == requestToken else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func region(for box: TripBoundingBox) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (box.minLat + box.maxLat) / 2,
                longitude: (box.minLon + box.maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((box.maxLat - box.minLat) * 1.35, 0.02),
                longitudeDelta: max((box.maxLon - box.minLon) * 1.35, 0.02)
            )
        )
    }
}
