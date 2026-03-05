import CoreLocation
import Foundation
import MapKit

enum ZoomBucket {
    case low
    case mid
    case high
}

enum MapGeometry {
    private struct ProjectedPoint {
        let x: Double
        let y: Double
    }

    static func boundingBox(for region: MKCoordinateRegion) -> TripBoundingBox {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        return TripBoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    static func zoomBucket(for region: MKCoordinateRegion) -> ZoomBucket {
        let delta = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if delta > 3.0 { return .low }
        if delta > 0.45 { return .mid }
        return .high
    }

    static func densityPoints(
        from trips: [TripSummary],
        in visibleBox: TripBoundingBox,
        cellSizeDegrees: Double
    ) -> [(coordinate: CLLocationCoordinate2D, weight: Int)] {
        guard cellSizeDegrees > 0 else { return [] }
        var buckets: [String: (lat: Double, lon: Double, count: Int)] = [:]

        for trip in trips {
            let point = trip.fullGeometry.first ?? trip.fullGeometry.last
            guard let point else { continue }
            guard point.latitude >= visibleBox.minLat, point.latitude <= visibleBox.maxLat else { continue }
            guard point.longitude >= visibleBox.minLon, point.longitude <= visibleBox.maxLon else { continue }

            let latKey = Int(point.latitude / cellSizeDegrees)
            let lonKey = Int(point.longitude / cellSizeDegrees)
            let key = "\(latKey):\(lonKey)"
            if let current = buckets[key] {
                buckets[key] = (current.lat, current.lon, current.count + 1)
            } else {
                buckets[key] = (point.latitude, point.longitude, 1)
            }
        }

        return buckets.values
            .sorted { $0.count > $1.count }
            .map { (coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), weight: $0.count) }
    }

    static func evaluateNavigationProgress(
        target: CoverageNavigationTarget,
        coverageFeatures: [CoverageMapFeature],
        trackedPathSegments: [[CLLocationCoordinate2D]],
        toleranceMeters: Double = 24
    ) -> CoverageNavigationProgress {
        let activePathSegments = trackedPathSegments.filter { $0.count > 0 }
        let uniqueSegmentIDs = orderedUnique(target.segmentIDs)
        let featureByID = Dictionary(uniqueKeysWithValues: coverageFeatures.map { ($0.id, $0) })

        var matchedSegmentIDs = Set<String>()
        var totalLengthMiles = 0.0
        var coveredLengthMiles = 0.0

        for segmentID in uniqueSegmentIDs {
            guard let feature = featureByID[segmentID] else { continue }
            let coordinates = Polyline6.decode(feature.geom.full)
            guard !coordinates.isEmpty else { continue }

            let lengthMiles = polylineLengthMiles(coordinates)
            totalLengthMiles += lengthMiles

            let didMatch = activePathSegments.contains { pathCoordinates in
                polylinesOverlap(pathCoordinates, coordinates, toleranceMeters: toleranceMeters)
            }

            if didMatch {
                matchedSegmentIDs.insert(segmentID)
                coveredLengthMiles += lengthMiles
            }
        }

        let fallbackSegmentCount = uniqueSegmentIDs.isEmpty ? target.undrivenSegmentCount : uniqueSegmentIDs.count
        let totalMiles = max(totalLengthMiles, target.undrivenLengthMiles)
        let completionRatio: Double

        if totalMiles > 0 {
            completionRatio = min(coveredLengthMiles / totalMiles, 1)
        } else if fallbackSegmentCount > 0 {
            completionRatio = min(Double(matchedSegmentIDs.count) / Double(fallbackSegmentCount), 1)
        } else {
            completionRatio = 0
        }

        let remainingSegmentCount = max(fallbackSegmentCount - matchedSegmentIDs.count, 0)
        let likelyComplete = completionRatio >= 0.70 || (remainingSegmentCount <= 1 && !matchedSegmentIDs.isEmpty)

        return CoverageNavigationProgress(
            matchedSegmentIDs: matchedSegmentIDs,
            matchedSegmentCount: matchedSegmentIDs.count,
            remainingSegmentCount: remainingSegmentCount,
            coveredLengthMiles: coveredLengthMiles,
            totalLengthMiles: totalMiles,
            completionRatio: completionRatio,
            likelyComplete: likelyComplete,
            trackingActive: true,
            hasRecordedPath: !activePathSegments.isEmpty
        )
    }

    static func distance(
        from coordinate: CLLocationCoordinate2D,
        toPolyline polyline: [CLLocationCoordinate2D]
    ) -> Double {
        guard !polyline.isEmpty else { return .greatestFiniteMagnitude }

        let projectedPoint = project(coordinate, referenceLatitude: coordinate.latitude)
        let projectedPolyline = polyline.map { project($0, referenceLatitude: coordinate.latitude) }

        return minDistance(from: projectedPoint, toPolyline: projectedPolyline)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values where seen.insert(value).inserted {
            output.append(value)
        }

        return output
    }

    private static func polylineLengthMiles(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }

        let totalMeters = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { partial, pair in
            partial + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }

        return totalMeters / 1_609.344
    }

    private static func polylinesOverlap(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D],
        toleranceMeters: Double
    ) -> Bool {
        guard let lhsFirst = lhs.first, let rhsFirst = rhs.first else { return false }

        let referenceLatitude = (lhsFirst.latitude + rhsFirst.latitude) / 2
        let projectedLHS = lhs.map { project($0, referenceLatitude: referenceLatitude) }
        let projectedRHS = rhs.map { project($0, referenceLatitude: referenceLatitude) }

        if projectedLHS.count == 1 {
            return minDistance(from: projectedLHS[0], toPolyline: projectedRHS) <= toleranceMeters
        }

        if projectedRHS.count == 1 {
            return minDistance(from: projectedRHS[0], toPolyline: projectedLHS) <= toleranceMeters
        }

        for lhsPair in zip(projectedLHS, projectedLHS.dropFirst()) {
            for rhsPair in zip(projectedRHS, projectedRHS.dropFirst()) {
                if segmentDistance(
                    lhsPair.0,
                    lhsPair.1,
                    rhsPair.0,
                    rhsPair.1
                ) <= toleranceMeters {
                    return true
                }
            }
        }

        return false
    }

    private static func minDistance(
        from point: ProjectedPoint,
        toPolyline polyline: [ProjectedPoint]
    ) -> Double {
        guard let first = polyline.first else { return .greatestFiniteMagnitude }
        guard polyline.count > 1 else { return distance(point, first) }

        return zip(polyline, polyline.dropFirst()).reduce(.greatestFiniteMagnitude) { current, pair in
            min(current, pointToSegmentDistance(point, pair.0, pair.1))
        }
    }

    private static func segmentDistance(
        _ a1: ProjectedPoint,
        _ a2: ProjectedPoint,
        _ b1: ProjectedPoint,
        _ b2: ProjectedPoint
    ) -> Double {
        if segmentsIntersect(a1, a2, b1, b2) {
            return 0
        }

        return min(
            pointToSegmentDistance(a1, b1, b2),
            pointToSegmentDistance(a2, b1, b2),
            pointToSegmentDistance(b1, a1, a2),
            pointToSegmentDistance(b2, a1, a2)
        )
    }

    private static func pointToSegmentDistance(
        _ point: ProjectedPoint,
        _ segmentStart: ProjectedPoint,
        _ segmentEnd: ProjectedPoint
    ) -> Double {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y

        guard dx != 0 || dy != 0 else {
            return distance(point, segmentStart)
        }

        let projection = ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / ((dx * dx) + (dy * dy))
        let clamped = min(1, max(0, projection))
        let projected = ProjectedPoint(
            x: segmentStart.x + clamped * dx,
            y: segmentStart.y + clamped * dy
        )
        return distance(point, projected)
    }

    private static func segmentsIntersect(
        _ a1: ProjectedPoint,
        _ a2: ProjectedPoint,
        _ b1: ProjectedPoint,
        _ b2: ProjectedPoint
    ) -> Bool {
        let o1 = orientation(a1, a2, b1)
        let o2 = orientation(a1, a2, b2)
        let o3 = orientation(b1, b2, a1)
        let o4 = orientation(b1, b2, a2)

        if o1 != o2, o3 != o4 {
            return true
        }

        if o1 == 0, onSegment(b1, a1, a2) { return true }
        if o2 == 0, onSegment(b2, a1, a2) { return true }
        if o3 == 0, onSegment(a1, b1, b2) { return true }
        if o4 == 0, onSegment(a2, b1, b2) { return true }

        return false
    }

    private static func orientation(
        _ a: ProjectedPoint,
        _ b: ProjectedPoint,
        _ c: ProjectedPoint
    ) -> Int {
        let value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        let epsilon = 0.000001

        if abs(value) <= epsilon {
            return 0
        }

        return value > 0 ? 1 : 2
    }

    private static func onSegment(
        _ point: ProjectedPoint,
        _ segmentStart: ProjectedPoint,
        _ segmentEnd: ProjectedPoint
    ) -> Bool {
        point.x <= max(segmentStart.x, segmentEnd.x) + 0.000001 &&
            point.x + 0.000001 >= min(segmentStart.x, segmentEnd.x) &&
            point.y <= max(segmentStart.y, segmentEnd.y) + 0.000001 &&
            point.y + 0.000001 >= min(segmentStart.y, segmentEnd.y)
    }

    private static func distance(_ a: ProjectedPoint, _ b: ProjectedPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt((dx * dx) + (dy * dy))
    }

    private static func project(
        _ coordinate: CLLocationCoordinate2D,
        referenceLatitude: Double
    ) -> ProjectedPoint {
        let metersPerDegreeLat = 111_132.92
        let metersPerDegreeLon = max(cos(referenceLatitude * .pi / 180) * 111_320, 1)

        return ProjectedPoint(
            x: coordinate.longitude * metersPerDegreeLon,
            y: coordinate.latitude * metersPerDegreeLat
        )
    }
}
