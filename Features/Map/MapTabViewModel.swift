import MapKit
import Observation
import SwiftUI
import UIKit

enum MapLayerMode: String, CaseIterable, Identifiable {
    case trips
    case coverage
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: "Trips"
        case .coverage: "Coverage Streets"
        case .combined: "Trips + Coverage"
        }
    }

    var shortTitle: String {
        switch self {
        case .trips: "Trips"
        case .coverage: "Coverage"
        case .combined: "Combined"
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
    case liveTrip
    case navigation(targetID: String, isActive: Bool)
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
    private let settings: AppSettingsStore

    private weak var syncAppModel: AppModel?
    private var lastBaseTripQuery: TripQuery?

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

    var isTripCoverageClipActive: Bool {
        activeTripCoverageAreaID != nil
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
        switch selectedLayer {
        case .trips:
            return isLoading
        case .coverage:
            return isCoverageLoading
        case .combined:
            return isLoading || isCoverageLoading
        }
    }

    var currentLayerErrorMessage: String? {
        switch selectedLayer {
        case .trips:
            return errorMessage
        case .coverage:
            return coverageErrorMessage
        case .combined:
            return errorMessage ?? coverageErrorMessage
        }
    }

    var activeOverlayGroups: [OverlayRenderGroup] {
        let level = Self.geometryLevel(for: zoomBucket)
        switch selectedLayer {
        case .trips:
            return tripOverlayGroupsByLevel[level] ?? []
        case .coverage:
            return filteredCoverageGroups(for: level)
        case .combined:
            let coverage = filteredCoverageGroups(for: level).map { group in
                OverlayRenderGroup(
                    id: "combined-\(group.id)",
                    overlay: group.overlay,
                    style: Self.combinedCoverageStyle(from: group.style),
                    semantic: group.semantic
                )
            }
            let trips = (tripOverlayGroupsByLevel[level] ?? []).map { group in
                OverlayRenderGroup(
                    id: "combined-\(group.id)",
                    overlay: group.overlay,
                    style: Self.combinedTripStyle(from: group.style),
                    semantic: group.semantic
                )
            }
            return coverage + trips
        }
    }

    init(
        repository: TripsRepository,
        coverageRepository: CoverageRepository,
        coordinateCache: LRUCoordinateCache,
        settings: AppSettingsStore = .shared
    ) {
        self.repository = repository
        self.coverageRepository = coverageRepository
        self.coordinateCache = coordinateCache
        self.settings = settings
        selectedCoverageAreaID = settings.selectedCoverageAreaID
    }

    func load(query: TripQuery, appModel: AppModel) async {
        syncAppModel = appModel
        lastBaseTripQuery = query

        await loadTripsBundle(
            using: query,
            syncModel: appModel,
            updateSyncState: true
        )
        await loadCoverageAreasIfNeeded()

        switch selectedLayer {
        case .coverage, .combined:
            if let areaID = selectedCoverageAreaID {
                await loadCoverageBundle(areaID: areaID)
            }
        case .trips:
            break
        }
    }

    func refresh(query: TripQuery, appModel: AppModel) async {
        await refreshCurrentLayer(query: query, appModel: appModel)
    }

    func refreshCurrentLayer(query: TripQuery, appModel: AppModel) async {
        syncAppModel = appModel
        lastBaseTripQuery = query

        switch selectedLayer {
        case .trips:
            await loadTripsBundle(
                using: query,
                syncModel: appModel,
                updateSyncState: true
            )
        case .coverage:
            await refreshCoverageLayer()
        case .combined:
            await loadTripsBundle(
                using: query,
                syncModel: appModel,
                updateSyncState: true
            )
            await refreshCoverageLayer()
        }
    }

    func setLayer(_ layer: MapLayerMode) async {
        guard selectedLayer != layer else { return }
        let wasTripClipActive = isTripCoverageClipActive
        selectedLayer = layer

        switch layer {
        case .trips:
            if wasTripClipActive != isTripCoverageClipActive {
                await reloadTripsForCurrentContext()
            }
        case .coverage:
            await loadCoverageAreasIfNeeded()
            if let areaID = selectedCoverageAreaID {
                await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
                await loadCoverageBundle(areaID: areaID)
            }
        case .combined:
            await loadCoverageAreasIfNeeded()
            if let areaID = selectedCoverageAreaID {
                await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: false)
                await loadCoverageBundle(areaID: areaID)
            }
            if wasTripClipActive != isTripCoverageClipActive {
                await reloadTripsForCurrentContext()
            }
        }
    }

    func selectCoverageArea(_ areaID: String) async {
        guard selectedCoverageAreaID != areaID else { return }
        selectedCoverageAreaID = areaID
        settings.selectedCoverageAreaID = areaID
        coverageFeatures = []
        coverageOverlayGroupsByLevel = [:]
        coverageTotalInViewport = 0

        await loadCoverageAreaDetailIfNeeded(areaID: areaID, focusCamera: true)
        await loadCoverageBundle(areaID: areaID)

        if selectedLayer == .combined {
            await reloadTripsForCurrentContext()
        }
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

    func focus(on coordinate: CLLocationCoordinate2D) {
        let currentStreetScaleMeters = max(currentRegion.span.latitudeDelta * 111_000 * 0.75, 320)
        let targetMeters = min(currentStreetScaleMeters, 1_400)
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: targetMeters,
            longitudinalMeters: targetMeters
        )

        currentRegion = region
        cameraRegion = region
        zoomBucket = MapGeometry.zoomBucket(for: region)
        cameraRevision += 1
        updateVisibleTrips()
        updateCoverageViewportCount()
    }

    func focus(on boundingBox: MapBoundingBox, including coordinate: CLLocationCoordinate2D?) {
        applyCamera(for: boundingBox.asTripBoundingBox, including: coordinate)
    }

    private var activeTripCoverageAreaID: String? {
        guard selectedLayer == .combined else { return nil }
        guard let selectedCoverageAreaID else { return nil }
        let trimmed = selectedCoverageAreaID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func effectiveTripQuery(from baseQuery: TripQuery) -> TripQuery {
        baseQuery.withCoverageArea(id: activeTripCoverageAreaID)
    }

    private func loadTripsBundle(
        using baseQuery: TripQuery,
        syncModel: AppModel?,
        updateSyncState: Bool
    ) async {
        isLoading = true
        errorMessage = nil

        if updateSyncState {
            syncModel?.markSyncStarted()
        }

        let query = effectiveTripQuery(from: baseQuery)

        do {
            let bundle = try await repository.loadTripMapBundle(query: query)
            allTrips = bundle.trips.sorted { $0.startTime > $1.startTime }
            updateVisibleTrips()
            await rebuildTripOverlays(query: query)

            if updateSyncState {
                let lastSync = await repository.lastSyncDate(for: baseQuery)
                syncModel?.lastUpdated = lastSync
                syncModel?.markSyncFinished(at: lastSync ?? .now)
            }
        } catch {
            if updateSyncState {
                if !allTrips.isEmpty {
                    syncModel?.markSyncStale()
                } else {
                    syncModel?.markSyncFailure(error.localizedDescription)
                }
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reloadTripsForCurrentContext() async {
        guard let query = lastBaseTripQuery else { return }
        await loadTripsBundle(
            using: query,
            syncModel: syncAppModel,
            updateSyncState: false
        )
    }

    private func loadCoverageAreasIfNeeded() async {
        await loadCoverageAreas(force: false)
    }

    private func refreshCoverageLayer() async {
        let previousClipAreaID = activeTripCoverageAreaID
        await loadCoverageAreas(force: true)
        if let areaID = selectedCoverageAreaID {
            await loadCoverageBundle(areaID: areaID)
        }
        if selectedLayer == .combined, previousClipAreaID != activeTripCoverageAreaID {
            await reloadTripsForCurrentContext()
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
                settings.selectedCoverageAreaID = selectedCoverageAreaID
            } else {
                selectedCoverageAreaID = areas.first?.id
                settings.selectedCoverageAreaID = selectedCoverageAreaID
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
                applyCamera(for: cached, including: nil)
            }
            return
        }

        do {
            let detail = try await coverageRepository.loadCoverageAreaDetail(id: areaID)
            if let boundingBox = detail.boundingBox {
                areaBoundingBoxes[areaID] = boundingBox
                if focusCamera {
                    applyCamera(for: boundingBox, including: nil)
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

    private func applyCamera(for boundingBox: TripBoundingBox, including coordinate: CLLocationCoordinate2D?) {
        let minLat = min(boundingBox.minLat, coordinate?.latitude ?? boundingBox.minLat)
        let maxLat = max(boundingBox.maxLat, coordinate?.latitude ?? boundingBox.maxLat)
        let minLon = min(boundingBox.minLon, coordinate?.longitude ?? boundingBox.minLon)
        let maxLon = max(boundingBox.maxLon, coordinate?.longitude ?? boundingBox.maxLon)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.35, 0.02)
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
            coordinateCache: coordinateCache
        )
    }

    private func rebuildCoverageOverlays() async {
        coverageOverlayGroupsByLevel = Self.buildCoverageOverlayGroups(
            features: coverageFeatures,
            coordinateCache: coordinateCache
        )
    }

    private func filteredCoverageGroups(for level: GeometryDetailLevel) -> [OverlayRenderGroup] {
        let groups = coverageOverlayGroupsByLevel[level] ?? []
        switch coverageFilter {
        case .all:
            return groups
        case .driven:
            return groups.filter { $0.semantic == .coverage(status: .driven) }
        case .undriven:
            return groups.filter { $0.semantic == .coverage(status: .undriven) }
        case .undriveable:
            return groups.filter { $0.semantic == .coverage(status: .undriveable) }
        }
    }

    func navigationOverlayGroups(
        suggestions: [CoverageNavigationTarget],
        activeTargetID: String?
    ) -> [OverlayRenderGroup] {
        let level = Self.geometryLevel(for: zoomBucket)
        let featureByID = Dictionary(uniqueKeysWithValues: coverageFeatures.map { ($0.id, $0) })

        return suggestions.compactMap { suggestion in
            let polylines = suggestion.segmentIDs.compactMap { segmentID -> MKPolyline? in
                guard let feature = featureByID[segmentID] else { return nil }

                let cacheKey = "navigation-\(segmentID)-\(level.rawValue)"
                let coordinates: [CLLocationCoordinate2D]
                if let cached = coordinateCache.value(for: cacheKey) {
                    coordinates = cached
                } else {
                    let decoded = Polyline6.decode(feature.geom.encodedPath(for: level))
                    coordinateCache.set(decoded, for: cacheKey)
                    coordinates = decoded
                }

                guard coordinates.count > 1 else { return nil }
                return MKPolyline(coordinates: coordinates, count: coordinates.count)
            }

            guard !polylines.isEmpty else { return nil }
            let isActive = suggestion.id == activeTargetID

            return OverlayRenderGroup(
                id: "navigation-\(suggestion.id)",
                overlay: MKMultiPolyline(polylines),
                style: Self.navigationStyle(rank: suggestion.rank, isActive: isActive),
                semantic: .navigation(targetID: suggestion.id, isActive: isActive)
            )
        }
    }

    private static func buildTripOverlayGroups(
        features: [TripMapFeature],
        coordinateCache: LRUCoordinateCache
    ) -> [GeometryDetailLevel: [OverlayRenderGroup]] {
        var byLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]

        for level in GeometryDetailLevel.allCases {
            var polylines: [MKPolyline] = []
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
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                polylines.append(polyline)
            }

            var groups: [OverlayRenderGroup] = []
            if !polylines.isEmpty {
                let overlay = MKMultiPolyline(polylines)
                let style = OverlayLineStyle(
                    color: UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1),
                    lineWidth: 2.8,
                    alpha: 0.90
                )
                groups.append(
                    OverlayRenderGroup(
                        id: "trip-\(level.rawValue)-all",
                        overlay: overlay,
                        style: style,
                        semantic: .trip(bucket: 0)
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

    private static func combinedCoverageStyle(from style: OverlayLineStyle) -> OverlayLineStyle {
        OverlayLineStyle(
            color: style.color,
            lineWidth: max(1.2, style.lineWidth * 0.72),
            alpha: min(0.62, style.alpha * 0.55),
            dashPattern: style.dashPattern
        )
    }

    private static func combinedTripStyle(from style: OverlayLineStyle) -> OverlayLineStyle {
        OverlayLineStyle(
            color: style.color,
            lineWidth: style.lineWidth + 0.45,
            alpha: min(1.0, max(0.72, style.alpha)),
            dashPattern: style.dashPattern
        )
    }

    private static func navigationStyle(rank: Int, isActive: Bool) -> OverlayLineStyle {
        if isActive {
            return OverlayLineStyle(
                color: UIColor(red: 0.24, green: 0.86, blue: 1.0, alpha: 1),
                lineWidth: 5.6,
                alpha: 0.98
            )
        }

        let clampedRank = max(rank, 1)
        return OverlayLineStyle(
            color: UIColor(red: 0.99, green: 0.81, blue: 0.28, alpha: 1),
            lineWidth: max(2.0, 3.3 - CGFloat(clampedRank - 1) * 0.35),
            alpha: max(0.30, 0.52 - CGFloat(clampedRank - 1) * 0.08),
            dashPattern: [5, 4]
        )
    }
}

protocol MapsLaunching {
    func openDrivingDirections(for target: CoverageNavigationTarget) -> Bool
}

struct SystemMapsLauncher: MapsLaunching {
    func openDrivingDirections(for target: CoverageNavigationTarget) -> Bool {
        let location = CLLocation(
            latitude: target.destination.latitude,
            longitude: target.destination.longitude
        )
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = target.title

        return mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
            ]
        )
    }
}

@MainActor
@Observable
final class CoverageNavigationController {
    @ObservationIgnored
    private let repository: CoverageRepository
    @ObservationIgnored
    private let mapsLauncher: MapsLaunching
    @ObservationIgnored
    private let nowProvider: () -> Date
    @ObservationIgnored
    private let refreshDistanceMeters: CLLocationDistance
    @ObservationIgnored
    private let suggestionMaxAge: TimeInterval
    @ObservationIgnored
    private let shortlistLimit: Int

    private var currentAreaID: String?
    private var lastFetchedOrigin: CLLocation?

    var suggestionSet: CoverageNavigationSuggestionSet?
    var activeTargetID: String?
    var progress: CoverageNavigationProgress?
    var isLoading = false
    var errorMessage: String?

    init(
        repository: CoverageRepository,
        mapsLauncher: MapsLaunching = SystemMapsLauncher(),
        nowProvider: @escaping () -> Date = { .now },
        refreshDistanceMeters: CLLocationDistance = 250,
        suggestionMaxAge: TimeInterval = 5 * 60,
        shortlistLimit: Int = 3
    ) {
        self.repository = repository
        self.mapsLauncher = mapsLauncher
        self.nowProvider = nowProvider
        self.refreshDistanceMeters = refreshDistanceMeters
        self.suggestionMaxAge = suggestionMaxAge
        self.shortlistLimit = shortlistLimit
    }

    var suggestions: [CoverageNavigationTarget] {
        suggestionSet?.suggestions ?? []
    }

    var activeTarget: CoverageNavigationTarget? {
        guard let suggestionSet else { return nil }

        if let activeTargetID,
           let target = suggestionSet.suggestions.first(where: { $0.id == activeTargetID })
        {
            return target
        }

        return suggestionSet.suggestions.first
    }

    var alternateTargets: [CoverageNavigationTarget] {
        suggestions.filter { $0.id != activeTarget?.id }
    }

    var hasSuggestions: Bool {
        !suggestions.isEmpty
    }

    var isLikelyComplete: Bool {
        progress?.likelyComplete == true
    }

    func syncContext(selectedLayer: MapLayerMode, areaID: String?) {
        guard selectedLayer != .trips, let areaID else {
            clearSession(resetArea: true)
            return
        }

        if currentAreaID != areaID {
            clearSession(resetArea: false)
            currentAreaID = areaID
        }
    }

    func clearSession(resetArea: Bool = false) {
        suggestionSet = nil
        activeTargetID = nil
        progress = nil
        errorMessage = nil
        lastFetchedOrigin = nil

        if resetArea {
            currentAreaID = nil
        }
    }

    func loadSuggestions(
        areaID: String,
        origin: CLLocationCoordinate2D,
        preserveActiveSelection: Bool = true
    ) async {
        guard !isLoading else { return }
        currentAreaID = areaID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let suggestionSet = try await repository.loadNavigationSuggestions(
                areaID: areaID,
                origin: origin,
                limit: shortlistLimit
            )
            applySuggestions(suggestionSet, preserveActiveSelection: preserveActiveSelection)
            lastFetchedOrigin = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshIfNeededOnReturn(
        areaID: String,
        origin: CLLocationCoordinate2D
    ) async {
        guard currentAreaID == areaID, let suggestionSet else { return }

        let movedEnough: Bool
        if let lastFetchedOrigin {
            let currentLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            movedEnough = currentLocation.distance(from: lastFetchedOrigin) >= refreshDistanceMeters
        } else {
            movedEnough = false
        }

        let isStale = nowProvider().timeIntervalSince(suggestionSet.generatedAt) >= suggestionMaxAge

        guard movedEnough || isStale || isLikelyComplete else { return }
        await loadSuggestions(areaID: areaID, origin: origin, preserveActiveSelection: !isLikelyComplete)
    }

    func selectTarget(id: String) {
        guard suggestions.contains(where: { $0.id == id }) else { return }
        activeTargetID = id
    }

    func advanceToNextTarget(
        areaID: String,
        origin: CLLocationCoordinate2D
    ) async {
        guard !suggestions.isEmpty else {
            await loadSuggestions(areaID: areaID, origin: origin, preserveActiveSelection: false)
            return
        }

        if let activeTargetID,
           let index = suggestions.firstIndex(where: { $0.id == activeTargetID }),
           suggestions.indices.contains(index + 1)
        {
            self.activeTargetID = suggestions[index + 1].id
            return
        }

        await loadSuggestions(areaID: areaID, origin: origin, preserveActiveSelection: false)
    }

    @discardableResult
    func launchNavigation() -> Bool {
        guard let activeTarget else {
            errorMessage = "No target selected."
            return false
        }

        let didLaunch = mapsLauncher.openDrivingDirections(for: activeTarget)
        if !didLaunch {
            errorMessage = "Unable to open Apple Maps."
        }
        return didLaunch
    }

    func updateProgress(
        coverageFeatures: [CoverageMapFeature],
        trackedPathSegments: [[CLLocationCoordinate2D]],
        isTripRecording: Bool
    ) {
        guard let activeTarget else {
            progress = nil
            return
        }

        let hasRecordedPath = trackedPathSegments.contains { $0.count > 0 }
        guard isTripRecording, hasRecordedPath else {
            progress = .placeholder(
                for: activeTarget,
                trackingActive: false,
                hasRecordedPath: hasRecordedPath,
                preserving: progress
            )
            return
        }

        progress = MapGeometry.evaluateNavigationProgress(
            target: activeTarget,
            coverageFeatures: coverageFeatures,
            trackedPathSegments: trackedPathSegments
        )
    }

    private func applySuggestions(
        _ suggestionSet: CoverageNavigationSuggestionSet,
        preserveActiveSelection: Bool
    ) {
        self.suggestionSet = suggestionSet

        guard !suggestionSet.suggestions.isEmpty else {
            activeTargetID = nil
            progress = nil
            errorMessage = "No undriven clusters found near your current position."
            return
        }

        errorMessage = nil

        if preserveActiveSelection,
           let activeTargetID,
           suggestionSet.suggestions.contains(where: { $0.id == activeTargetID })
        {
            self.activeTargetID = activeTargetID
        } else {
            activeTargetID = suggestionSet.suggestions.first?.id
        }
    }
}
