import MapKit
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class CoverageAreaMapViewModel {
    private let areaID: String
    private let repository: CoverageRepository
    private let coordinateCache = LRUCoordinateCache(memoryLimitBytes: 48 * 1024 * 1024)

    private var hasLoaded = false
    private var overlayGroupsByLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]

    var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    var cameraRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    var cameraRevision = 0

    var zoomBucket: ZoomBucket = .mid
    var filter: CoverageStreetFilter = .all
    var features: [CoverageMapFeature] = []
    var totalInViewport = 0
    var isLoading = false
    var errorMessage: String?

    var visibleSegments: [CoverageMapFeature] {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.08)
        return features.filter { feature in
            filter.matches(feature.status)
                && feature.bbox.asTripBoundingBox.intersects(visibleBox)
        }
    }

    var counts: (driven: Int, undriven: Int, undriveable: Int) {
        features.reduce(into: (driven: 0, undriven: 0, undriveable: 0)) { result, feature in
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

    var activeOverlayGroups: [OverlayRenderGroup] {
        let level = geometryLevel(for: zoomBucket)
        let groups = overlayGroupsByLevel[level] ?? []
        switch filter {
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
                cameraRegion = region
                cameraRevision += 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        await loadBundle()
    }

    func refresh() {
        Task {
            await loadBundle()
        }
    }

    func update(region: MKCoordinateRegion) {
        currentRegion = region
        cameraRegion = region
        zoomBucket = MapGeometry.zoomBucket(for: region)
        updateViewportCount()
    }

    func setFilter(_ filter: CoverageStreetFilter) {
        self.filter = filter
        updateViewportCount()
    }

    private func loadBundle() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let bundle = try await repository.loadCoverageMapBundle(areaID: areaID, status: .all)
            features = bundle.segments
            await rebuildOverlayGroups()
            updateViewportCount()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

    private func updateViewportCount() {
        let visibleBox = MapGeometry.boundingBox(for: currentRegion).expanded(by: 0.08)
        totalInViewport = features.reduce(into: 0) { total, feature in
            guard feature.bbox.asTripBoundingBox.intersects(visibleBox) else { return }
            total += 1
        }
    }

    private func rebuildOverlayGroups() async {
        overlayGroupsByLevel = buildCoverageOverlayGroups(
            features: features,
            coordinateCache: coordinateCache
        )
    }

    private func geometryLevel(for zoomBucket: ZoomBucket) -> GeometryDetailLevel {
        switch zoomBucket {
        case .low: .low
        case .mid: .medium
        case .high: .full
        }
    }
}

private func buildCoverageOverlayGroups(
    features: [CoverageMapFeature],
    coordinateCache: LRUCoordinateCache
) -> [GeometryDetailLevel: [OverlayRenderGroup]] {
    var byLevel: [GeometryDetailLevel: [OverlayRenderGroup]] = [:]
    let statuses: [CoverageStreetStatus] = [.driven, .undriven, .undriveable, .unknown]

    for level in GeometryDetailLevel.allCases {
        var bucketed: [CoverageStreetStatus: [MKPolyline]] = [:]

        for feature in features {
            let cacheKey = "coverage-card-\(feature.id)-\(level.rawValue)"
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
            groups.append(
                OverlayRenderGroup(
                    id: "coverage-card-\(level.rawValue)-\(status.rawValue)",
                    overlay: overlay,
                    style: coverageStyle(status: status),
                    semantic: .coverage(status: status)
                )
            )
        }

        byLevel[level] = groups
    }

    return byLevel
}

private func coverageStyle(status: CoverageStreetStatus) -> OverlayLineStyle {
    switch status {
    case .driven:
        OverlayLineStyle(
            color: UIColor(red: 0.26, green: 0.79, blue: 0.52, alpha: 1),
            lineWidth: 3.0,
            alpha: 0.9
        )
    case .undriven:
        OverlayLineStyle(
            color: UIColor(red: 0.96, green: 0.64, blue: 0.20, alpha: 1),
            lineWidth: 2.4,
            alpha: 0.9
        )
    case .undriveable:
        OverlayLineStyle(
            color: UIColor(white: 0.64, alpha: 1),
            lineWidth: 1.8,
            alpha: 0.55
        )
    case .unknown:
        OverlayLineStyle(
            color: UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1),
            lineWidth: 2.0,
            alpha: 0.65
        )
    }
}
