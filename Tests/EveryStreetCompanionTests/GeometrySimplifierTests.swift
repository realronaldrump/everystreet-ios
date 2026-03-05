import CoreLocation
import XCTest
@testable import EveryStreetCompanion

final class GeometrySimplifierTests: XCTestCase {
    func testSimplifyRetainsEndpoints() {
        let points: [CLLocationCoordinate2D] = [
            .init(latitude: 31.0, longitude: -97.0),
            .init(latitude: 31.001, longitude: -97.001),
            .init(latitude: 31.002, longitude: -97.002),
            .init(latitude: 31.003, longitude: -97.003)
        ]

        let simplified = GeometrySimplifier.simplify(points, tolerance: 0.5)

        XCTAssertEqual(simplified.count, 2)
        guard let simplifiedFirst = simplified.first, let pointsFirst = points.first else {
            return XCTFail("Expected non-empty coordinates")
        }
        guard let simplifiedLast = simplified.last, let pointsLast = points.last else {
            return XCTFail("Expected non-empty coordinates")
        }
        XCTAssertEqual(simplifiedFirst.latitude, pointsFirst.latitude, accuracy: 0.000001)
        XCTAssertEqual(simplifiedLast.longitude, pointsLast.longitude, accuracy: 0.000001)
    }

    func testComputeBoundingBox() {
        let points: [CLLocationCoordinate2D] = [
            .init(latitude: 31.2, longitude: -97.8),
            .init(latitude: 31.6, longitude: -97.1),
            .init(latitude: 31.1, longitude: -97.5)
        ]

        guard let bbox = GeometrySimplifier.computeBoundingBox(points) else {
            return XCTFail("Expected bounding box for non-empty points")
        }
        XCTAssertEqual(bbox.minLat, 31.1, accuracy: 0.0001)
        XCTAssertEqual(bbox.maxLon, -97.1, accuracy: 0.0001)
    }

    func testDecodePolyline6() {
        let encoded = "gvrd{@vsjhxD_q@wj@"
        let coords = Polyline6.decode(encoded)

        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 31.5493, accuracy: 0.000001)
        XCTAssertEqual(coords[0].longitude, -97.1467, accuracy: 0.000001)
        XCTAssertEqual(coords[1].latitude, 31.5501, accuracy: 0.000001)
        XCTAssertEqual(coords[1].longitude, -97.1460, accuracy: 0.000001)
    }
}
