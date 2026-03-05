import MapKit
import Observation
import SwiftUI
import UIKit

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

struct OverlayLineStyle: Hashable {
    let color: UIColor
    let lineWidth: CGFloat
    let alpha: CGFloat
    let dashPattern: [NSNumber]?

    init(color: UIColor, lineWidth: CGFloat, alpha: CGFloat, dashPattern: [NSNumber]? = nil) {
        self.color = color
        self.lineWidth = lineWidth
        self.alpha = alpha
        self.dashPattern = dashPattern
    }
}

enum OverlaySemantic: Hashable {
    case trip(bucket: Int)
    case coverage(status: CoverageStreetStatus)
}

struct OverlayRenderGroup: Identifiable {
    let id: String
    let overlay: MKMultiPolyline
    let style: OverlayLineStyle
    let semantic: OverlaySemantic
}

@MainActor
@Observable
final class MapTabViewModel {
    private let repository: TripsRepository
    private let coverageRepository: CoverageRepository
    private let coordinateCache: LRUCoordinateCache

    private var areaBoundingBoxes: [String: TripBoundingBox] = [:]
    private var tripOverlayGroupsByLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]
    private var coverageOverlayGroupsByLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]

    var allTrips: [TripMapFeature] = []
    var visibleTrips: [TripMapFeature] = []

    var selectedLayer: MapLayerMode = .trips
    var coverageAreas: [CoverageArea] = []
    var selectedCoverageAreaID: String?
    var coverageFilter: CoverageStreetFilter = .all
    var coverageFeatures: [CoverageMapFeature] = []
    var coverageTotalInViewport = 0

    var cameraRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
    )

    var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
    )

    var cameraRevision = 0
    var zoomBucket: ZoomBucket = .mid

    var isLoading = false
    var errorMessage: String?

    var isCoverageLoading = false
    var coverageErrorMessage: String?

    var selectedCoverageArea: CoverageArea? {
        guard let selectedCoverageAreaID else { return nil }
        return coverageAreas.first(where: { $0.id == selectedCoverageAreaID })
    }

    var visibleCoverageSegments: [CoverageMapFeature] {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.10)
        return coverageFeatures.filter { feature in
            coverageFilter.matches(feature.status)
                && feature.bbox.asTripBoundingBox.intersects(visibleBox)
        }
    }

    var coverageCounts: (driven: Int, undriven: Int, undriveable: Int) {
        coverageFeatures.reduce(into: (driven: 0, undriven: 0, undriveable: 0)) { result, feature in
            switch feature.status {
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

    var activeOverlayGroups: [OverlayRenderGroup] {
        let level = Self.geometryLevel(for: zoomBucket)
        switch selectedLayer {
        case .trips:
            return tripOverlayGroupsByLevel[level] ?? []
        case .coverage:
            let groups = coverageOverlayGroupsByLevel[level] ?? []
            switch coverageFilter {
            case .all:
                return groups
            case .driven:
                return groups.filter { $0.semantic == OverlaySemantic.coverage(status: .driven) }
            case .undriven:
                return groups.filter { $0.semantic == OverlaySemantic.coverage(status: .undriven) }
            case .undriveable:
                return groups.filter { $0.semantic == OverlaySemantic.coverage(status: .undriveable) }
            }
        }
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
            let bundle = try await repository.loadTripMapBundle(query: query)
            allTrips = bundle.trips.sorted { $0.startTime > $1.startTime }
            updateVisibleTrips()
            await rebuildTripOverlays(query: query)

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

        if selectedLayer == .coverage, let areaID = selectedCoverageAreaID {
            await loadCoverageBundle(areaID: areaID)
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
                let bundle = try await repository.loadTripMapBundle(query: query)
                allTrips = bundle.trips.sorted { $0.startTime > $1.startTime }
                updateVisibleTrips()
                await rebuildTripOverlays(query: query)
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
            break
        case .coverage:
            await loadCoverageAreasIfNeeded()
            if let areaID = selectedCoverageAreaID {
                await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
                await loadCoverageBundle(areaID: areaID)
            }
        }
    }

    func selectCoverageArea(_ areaID: String) async {
        guard selectedCoverageAreaID != areaID else { return }
        selectedCoverageAreaID = areaID
        coverageFeatures = []
        coverageOverlayGroupsByLevel = [:]
        coverageTotalInViewport = 0

        await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
        await loadCoverageBundle(areaID: areaID)
    }

    func setCoverageFilter(_ filter: CoverageStreetFilter) {
        coverageFilter = filter
        updateCoverageViewportCount()
    }

    func update(region: MKCoordinateRegion) {
        currentRegion = region
        cameraRegion = region
        zoomBucket = MapGeometry.zoomBucket(for: region)
        updateVisibleTrips()
        updateCoverageViewportCount()
    }

    private func loadCoverageAreasIfNeeded() async {
        await loadCoverageAreas(force: false)
    }

    private func refreshCoverageLayer() async {
        await loadCoverageAreas(force: true)
        if let areaID = selectedCoverageAreaID {
            await loadCoverageBundle(areaID: areaID)
        }
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

    private func loadCoverageBundle(areaID: String) async {
        isCoverageLoading = true
        defer { isCoverageLoading = false }

        do {
            let bundle = try await coverageRepository.loadCoverageMapBundle(areaID: areaID, status: .all)
            coverageFeatures = bundle.segments
            await rebuildCoverageOverlays()
            updateCoverageViewportCount()
            coverageErrorMessage = nil
        } catch {
            coverageErrorMessage = error.localizedDescription
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
        cameraRegion = region
        cameraRevision += 1
    }

    private func updateVisibleTrips() {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.20)
        visibleTrips = allTrips.filter { trip in
            trip.bbox.asTripBoundingBox.intersects(visibleBox)
        }
    }

    private func updateCoverageViewportCount() {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.10)
        coverageTotalInViewport = coverageFeatures.reduce(into: 0) { total, feature in
            guard feature.bbox.asTripBoundingBox.intersects(visibleBox) else { return }
            total += 1
        }
    }

    private func rebuildTripOverlays(query: TripQuery) async {
        tripOverlayGroupsByLevel = Self.buildTripOverlayGroups(
            features: allTrips,
            queryRange: query.dateRange,
            coordinateCache: coordinateCache
        )
    }

    private func rebuildCoverageOverlays() async {
        coverageOverlayGroupsByLevel = Self.buildCoverageOverlayGroups(
            features: coverageFeatures,
            coordinateCache: coordinateCache
        )
    }

    private static func buildTripOverlayGroups(
        features: [TripMapFeature],
        queryRange: DateInterval,
        coordinateCache: LRUCoordinateCache
    ) -> [GeometryDetailLevel: [OverlayRenderGroup]] {
        var byLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]

        for level in GeometryDetailLevel.allCases {
            var buckets: [Int: [MKPolyline]] = [:]
            for feature in features {
                let cacheKey = "trip-\(feature.id)-\(level.rawValue)"
                let coordinates: [CLLocationCoordinate2D]
                if let cached = coordinateCache.value(for: cacheKey) {
                    coordinates = cached
                } else {
                    let decoded = Polyline6.decode(feature.geom.encodedPath(for: level))
                    coordinateCache.set(decoded, for: cacheKey)
                    coordinates = decoded
                }

                guard coordinates.count > 1 else { continue }
                let bucket = timeBucket(for: feature.startTime, in: queryRange)
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                buckets[bucket, default: []].append(polyline)
            }

            var groups: [OverlayRenderGroup] = []
            for bucket in 0 ..< 8 {
                guard let polylines = buckets[bucket], !polylines.isEmpty else { continue }
                let overlay = MKMultiPolyline(polylines)
                let uiColor = tripBucketColor(bucket: bucket)
                let width = CGFloat(1.4 + Double(bucket) * 0.34)
                let alpha = CGFloat(min(0.98, 0.50 + (Double(bucket) * 0.07)))
                let style = OverlayLineStyle(color: uiColor, lineWidth: width, alpha: alpha)
                groups.append(
                    OverlayRenderGroup(
                        id: "trip-\(level.rawValue)-\(bucket)",
                        overlay: overlay,
                        style: style,
                        semantic: .trip(bucket: bucket)
                    )
                )
            }

            byLevel[level] = groups
        }

        return byLevel
    }

    private static func buildCoverageOverlayGroups(
        features: [CoverageMapFeature],
        coordinateCache: LRUCoordinateCache
    ) -> [GeometryDetailLevel: [OverlayRenderGroup]] {
        var byLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]
        let statuses: [CoverageStreetStatus] = [.driven, .undriven, .undriveable, .unknown]

        for level in GeometryDetailLevel.allCases {
            var bucketed: [CoverageStreetStatus: [MKPolyline]] = [:]

            for feature in features {
                let cacheKey = "coverage-\(feature.id)-\(level.rawValue)"
                let coordinates: [CLLocationCoordinate2D]
                if let cached = coordinateCache.value(for: cacheKey) {
                    coordinates = cached
                } else {
                    let decoded = Polyline6.decode(feature.geom.encodedPath(for: level))
                    coordinateCache.set(decoded, for: cacheKey)
                    coordinates = decoded
                }

                guard coordinates.count > 1 else { continue }
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                bucketed[feature.status, default: []].append(polyline)
            }

            var groups: [OverlayRenderGroup] = []
            for status in statuses {
                guard let polylines = bucketed[status], !polylines.isEmpty else { continue }
                let overlay = MKMultiPolyline(polylines)
                let style = coverageStyle(for: status)
                groups.append(
                    OverlayRenderGroup(
                        id: "coverage-\(level.rawValue)-\(status.rawValue)",
                        overlay: overlay,
                        style: style,
                        semantic: .coverage(status: status)
                    )
                )
            }

            byLevel[level] = groups
        }

        return byLevel
    }

    private static func geometryLevel(for zoomBucket: ZoomBucket) -> GeometryDetailLevel {
        switch zoomBucket {
        case .low: .low
        case .mid: .medium
        case .high: .full
        }
    }

    private static func timeBucket(for timestamp: Date, in range: DateInterval) -> Int {
        let start = range.start.timeIntervalSince1970
        let end = range.end.timeIntervalSince1970
        guard end > start else { return 7 }

        let raw = (timestamp.timeIntervalSince1970 - start) / (end - start)
        let clamped = max(0, min(1, raw))
        return min(7, max(0, Int(clamped * 7.999)))
    }

    private static func tripBucketColor(bucket: Int) -> UIColor {
        let t = max(0, min(1, Double(bucket) / 7.0))
        let old = (red: 0.22, green: 0.38, blue: 0.60)
        let recent = (red: 0.30, green: 0.85, blue: 1.0)

        return UIColor(
            red: old.red + (recent.red - old.red) * t,
            green: old.green + (recent.green - old.green) * t,
            blue: old.blue + (recent.blue - old.blue) * t,
            alpha: 1
        )
    }

    private static func coverageStyle(for status: CoverageStreetStatus) -> OverlayLineStyle {
        switch status {
        case .driven:
            OverlayLineStyle(
                color: UIColor(red: 0.26, green: 0.79, blue: 0.52, alpha: 1),
                lineWidth: 4.2,
                alpha: 0.96
            )
        case .undriven:
            OverlayLineStyle(
                color: UIColor(red: 0.96, green: 0.64, blue: 0.20, alpha: 1),
                lineWidth: 3.1,
                alpha: 0.94
            )
        case .undriveable:
            OverlayLineStyle(
                color: UIColor(white: 0.72, alpha: 1),
                lineWidth: 1.7,
                alpha: 0.58,
                dashPattern: [6, 4]
            )
        case .unknown:
            OverlayLineStyle(
                color: UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1),
                lineWidth: 2.0,
                alpha: 0.60,
                dashPattern: [2, 6]
            )
        }
    }
}
