import CoreLocation
import Foundation
import MapKit

enum ZoomBucket {
    case low
    case mid
    case high
}

enum MapGeometry {
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
}
