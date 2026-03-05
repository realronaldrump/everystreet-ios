import MapKit
import Observation
import SwiftUI

enum MapLayerMode: String, CaseIterable, Identifiable {
    case trips
    case coverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: "Trips"
        case .coverage: "Coverage Streets"
        }
    }

    var shortTitle: String {
        switch self {
        case .trips: "Trips"
        case .coverage: "Coverage"
        }
    }
}

@MainActor
@Observable
final class MapTabViewModel {
    private struct RenderBudget {
        let maxItems: Int
        let maxPoints: Int
    }

    private let repository: TripsRepository
    private let coverageRepository: CoverageRepository
    private let coordinateCache: LRUCoordinateCache

    private var coverageFetchTask: Task<Void, Never>?
    private var coverageRequestToken = UUID()
    private var areaBoundingBoxes: [String: TripBoundingBox] = [:]

    var allTrips: [TripSummary] = []
    var visibleTrips: [TripSummary] = []
    var renderedTrips: [TripSummary] = []
    var selectedTrip: TripSummary?

    var selectedLayer: MapLayerMode = .trips
    var coverageAreas: [CoverageArea] = []
    var selectedCoverageAreaID: String?
    var coverageFilter: CoverageStreetFilter = .all
    var coverageSegments: [CoverageStreetSegment] = []
    var renderedCoverageSegments: [CoverageStreetSegment] = []
    var coverageTotalInViewport = 0
    var coverageTruncated = false

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

    var isCoverageLoading = false
    var coverageErrorMessage: String?

    var selectedCoverageArea: CoverageArea? {
        guard let selectedCoverageAreaID else { return nil }
        return coverageAreas.first(where: { $0.id == selectedCoverageAreaID })
    }

    var visibleCoverageSegments: [CoverageStreetSegment] {
        coverageSegments.filter { coverageFilter.matches($0.status) }
    }

    var isTripRenderingCapped: Bool {
        zoomBucket != .low && renderedTrips.count < visibleTrips.count
    }

    var isCoverageRenderingCapped: Bool {
        renderedCoverageSegments.count < visibleCoverageSegments.count
    }

    var coverageCounts: (driven: Int, undriven: Int, undriveable: Int) {
        coverageSegments.reduce(into: (driven: 0, undriven: 0, undriveable: 0)) { result, segment in
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

    var isCurrentLayerLoading: Bool {
        selectedLayer == .trips ? isLoading : isCoverageLoading
    }

    var currentLayerErrorMessage: String? {
        selectedLayer == .trips ? errorMessage : coverageErrorMessage
    }

    init(repository: TripsRepository, coverageRepository: CoverageRepository, coordinateCache: LRUCoordinateCache) {
        self.repository = repository
        self.coverageRepository = coverageRepository
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
        await loadCoverageAreasIfNeeded()

        if selectedLayer == .coverage {
            scheduleCoverageStreetFetch(force: true)
        }
    }

    func refresh(query: TripQuery, appModel: AppModel) async {
        await refreshCurrentLayer(query: query, appModel: appModel)
    }

    func refreshCurrentLayer(query: TripQuery, appModel: AppModel) async {
        switch selectedLayer {
        case .trips:
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
        case .coverage:
            await refreshCoverageLayer()
        }
    }

    func setLayer(_ layer: MapLayerMode) async {
        guard selectedLayer != layer else { return }
        selectedLayer = layer

        switch layer {
        case .trips:
            coverageFetchTask?.cancel()
            isCoverageLoading = false
            updateRenderedTrips()
        case .coverage:
            await loadCoverageAreasIfNeeded()
            if let areaID = selectedCoverageAreaID {
                await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
            }
            updateRenderedCoverageSegments()
            scheduleCoverageStreetFetch(force: true)
        }
    }

    func selectCoverageArea(_ areaID: String) async {
        guard selectedCoverageAreaID != areaID else { return }
        selectedCoverageAreaID = areaID
        coverageSegments = []
        renderedCoverageSegments = []
        coverageTotalInViewport = 0
        coverageTruncated = false

        await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
        scheduleCoverageStreetFetch(force: true)
    }

    func setCoverageFilter(_ filter: CoverageStreetFilter) {
        coverageFilter = filter
        updateRenderedCoverageSegments()
    }

    func update(region: MKCoordinateRegion) {
        currentRegion = region
        zoomBucket = MapGeometry.zoomBucket(for: region)
        updateVisibleTrips()
        updateRenderedCoverageSegments()

        if selectedLayer == .coverage {
            scheduleCoverageStreetFetch()
        }
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

    private func loadCoverageAreasIfNeeded() async {
        await loadCoverageAreas(force: false)
    }

    private func refreshCoverageLayer() async {
        await loadCoverageAreas(force: true)
        scheduleCoverageStreetFetch(force: true)
    }

    private func loadCoverageAreas(force: Bool) async {
        guard force || coverageAreas.isEmpty else { return }

        isCoverageLoading = true
        defer { isCoverageLoading = false }

        do {
            let areas = try await coverageRepository.loadCoverageAreas()
            coverageAreas = areas
            coverageErrorMessage = nil

            if let selectedCoverageAreaID,
               areas.contains(where: { $0.id == selectedCoverageAreaID })
            {
                // Keep selected area.
            } else {
                selectedCoverageAreaID = areas.first?.id
            }

            if let selectedCoverageAreaID {
                await loadCoverageAreaDetailIfNeeded(areaID: selectedCoverageAreaID, focusCamera: false)
            }
        } catch {
            coverageErrorMessage = error.localizedDescription
        }
    }

    private func loadCoverageAreaDetailIfNeeded(areaID: String, focusCamera: Bool) async {
        if let cached = areaBoundingBoxes[areaID] {
            if focusCamera {
                applyCamera(for: cached)
            }
            return
        }

        do {
            let detail = try await coverageRepository.loadCoverageAreaDetail(id: areaID)
            if let boundingBox = detail.boundingBox {
                areaBoundingBoxes[areaID] = boundingBox
                if focusCamera {
                    applyCamera(for: boundingBox)
                }
            }

            if let index = coverageAreas.firstIndex(where: { $0.id == areaID }) {
                coverageAreas[index] = detail.area
            }
        } catch {
            coverageErrorMessage = error.localizedDescription
        }
    }

    private func scheduleCoverageStreetFetch(force: Bool = false) {
        guard selectedLayer == .coverage,
              let areaID = selectedCoverageAreaID
        else {
            return
        }

        let region = currentRegion
        coverageFetchTask?.cancel()
        coverageFetchTask = Task { [weak self] in
            guard let self else { return }
            if !force {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            await self.fetchCoverageStreets(areaID: areaID, region: region)
        }
    }

    private func fetchCoverageStreets(areaID: String, region: MKCoordinateRegion) async {
        let requestToken = UUID()
        coverageRequestToken = requestToken
        isCoverageLoading = true

        let viewport = MapGeometry.boundingBox(for: region).expanded(by: 0.08)

        do {
            let snapshot = try await coverageRepository.loadStreets(areaID: areaID, boundingBox: viewport)
            guard !Task.isCancelled, requestToken == coverageRequestToken else { return }

            coverageSegments = snapshot.segments
            coverageTotalInViewport = snapshot.totalInViewport
            coverageTruncated = snapshot.truncated
            updateRenderedCoverageSegments()
            coverageErrorMessage = nil
            isCoverageLoading = false
        } catch {
            guard !Task.isCancelled, requestToken == coverageRequestToken else { return }
            coverageErrorMessage = error.localizedDescription
            isCoverageLoading = false
        }
    }

    private func applyCamera(for boundingBox: TripBoundingBox) {
        let center = CLLocationCoordinate2D(
            latitude: (boundingBox.minLat + boundingBox.maxLat) / 2,
            longitude: (boundingBox.minLon + boundingBox.maxLon) / 2
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((boundingBox.maxLat - boundingBox.minLat) * 1.35, 0.02),
                longitudeDelta: max((boundingBox.maxLon - boundingBox.minLon) * 1.35, 0.02)
            )
        )

        currentRegion = region
        cameraPosition = .region(region)
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

        updateRenderedTrips()
    }

    private func updateRenderedTrips() {
        guard zoomBucket != .low else {
            renderedTrips = []
            return
        }

        let level = geometryLevel(for: zoomBucket)
        let budget = tripRenderBudget(for: zoomBucket)
        var rendered: [TripSummary] = []
        rendered.reserveCapacity(min(visibleTrips.count, budget.maxItems))
        var consumedPoints = 0

        for trip in visibleTrips {
            guard rendered.count < budget.maxItems else { break }

            let pointCount = coordinateCount(for: trip, level: level)
            guard pointCount > 1 else { continue }

            if consumedPoints + pointCount > budget.maxPoints {
                if rendered.isEmpty {
                    rendered.append(trip)
                }
                break
            }

            rendered.append(trip)
            consumedPoints += pointCount
        }

        renderedTrips = rendered
    }

    private func updateRenderedCoverageSegments() {
        let candidates = visibleCoverageSegments
        let budget = coverageRenderBudget(for: zoomBucket)
        var rendered: [CoverageStreetSegment] = []
        rendered.reserveCapacity(min(candidates.count, budget.maxItems))
        var consumedPoints = 0

        for segment in candidates {
            guard rendered.count < budget.maxItems else { break }
            let pointCount = segment.coordinates.count
            guard pointCount > 1 else { continue }

            if consumedPoints + pointCount > budget.maxPoints {
                if rendered.isEmpty {
                    rendered.append(segment)
                }
                break
            }

            rendered.append(segment)
            consumedPoints += pointCount
        }

        renderedCoverageSegments = rendered
    }

    private func geometryLevel(for zoomBucket: ZoomBucket) -> GeometryDetailLevel {
        switch zoomBucket {
        case .low: .low
        case .mid: .medium
        case .high: .full
        }
    }

    private func coordinateCount(for trip: TripSummary, level: GeometryDetailLevel) -> Int {
        switch level {
        case .full:
            return trip.fullGeometry.count
        case .medium:
            return trip.mediumGeometry.isEmpty ? trip.fullGeometry.count : trip.mediumGeometry.count
        case .low:
            if !trip.lowGeometry.isEmpty { return trip.lowGeometry.count }
            if !trip.mediumGeometry.isEmpty { return trip.mediumGeometry.count }
            return trip.fullGeometry.count
        }
    }

    private func tripRenderBudget(for zoomBucket: ZoomBucket) -> RenderBudget {
        switch zoomBucket {
        case .low:
            return RenderBudget(maxItems: 0, maxPoints: 0)
        case .mid:
            return RenderBudget(maxItems: 260, maxPoints: 28_000)
        case .high:
            return RenderBudget(maxItems: 180, maxPoints: 24_000)
        }
    }

    private func coverageRenderBudget(for zoomBucket: ZoomBucket) -> RenderBudget {
        switch zoomBucket {
        case .low:
            return RenderBudget(maxItems: 900, maxPoints: 18_000)
        case .mid:
            return RenderBudget(maxItems: 1_200, maxPoints: 24_000)
        case .high:
            return RenderBudget(maxItems: 1_500, maxPoints: 30_000)
        }
    }
}
