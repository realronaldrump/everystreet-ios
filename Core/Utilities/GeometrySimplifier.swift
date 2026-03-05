import CoreLocation
import Foundation

enum GeometrySimplifier {
    static func simplify(_ coordinates: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        let first = coordinates.first!
        let last = coordinates.last!
        var maxDistance = 0.0
        var index = 0

        for i in 1..<(coordinates.count - 1) {
            let distance = perpendicularDistance(point: coordinates[i], lineStart: first, lineEnd: last)
            if distance > maxDistance {
                maxDistance = distance
                index = i
            }
        }

        if maxDistance > tolerance {
            let left = simplify(Array(coordinates[0...index]), tolerance: tolerance)
            let right = simplify(Array(coordinates[index...]), tolerance: tolerance)
            return Array(left.dropLast()) + right
        }

        return [first, last]
    }

    static func computeBoundingBox(_ coordinates: [CLLocationCoordinate2D]) -> TripBoundingBox? {
        TripBoundingBox(coordinates: coordinates)
    }

    private static func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let x0 = point.longitude
        let y0 = point.latitude
        let x1 = lineStart.longitude
        let y1 = lineStart.latitude
        let x2 = lineEnd.longitude
        let y2 = lineEnd.latitude

        let numerator = abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1)
        let denominator = hypot(y2 - y1, x2 - x1)

        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
