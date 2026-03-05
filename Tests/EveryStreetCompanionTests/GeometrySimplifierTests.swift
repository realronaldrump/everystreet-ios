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

    func testEvaluateNavigationProgressMatchesTargetSegment() {
        let segmentCoordinates = [
            CLLocationCoordinate2D(latitude: 31.5500, longitude: -97.1400),
            CLLocationCoordinate2D(latitude: 31.5506, longitude: -97.1394),
        ]

        let progress = MapGeometry.evaluateNavigationProgress(
            target: makeTarget(id: "cluster-1", segmentIDs: ["seg-1"]),
            coverageFeatures: [makeCoverageFeature(id: "seg-1", coordinates: segmentCoordinates)],
            trackedPathSegments: [segmentCoordinates]
        )

        XCTAssertEqual(progress.matchedSegmentCount, 1)
        XCTAssertEqual(progress.remainingSegmentCount, 0)
        XCTAssertTrue(progress.likelyComplete)
        XCTAssertGreaterThan(progress.coveredLengthMiles, 0)
    }

    func testEvaluateNavigationProgressRejectsParallelStreetOutsideTolerance() {
        let targetCoordinates = [
            CLLocationCoordinate2D(latitude: 31.5600, longitude: -97.1500),
            CLLocationCoordinate2D(latitude: 31.5608, longitude: -97.1492),
        ]
        let shiftedPath = [
            CLLocationCoordinate2D(latitude: 31.5605, longitude: -97.1500),
            CLLocationCoordinate2D(latitude: 31.5613, longitude: -97.1492),
        ]

        let progress = MapGeometry.evaluateNavigationProgress(
            target: makeTarget(id: "cluster-2", segmentIDs: ["seg-2"]),
            coverageFeatures: [makeCoverageFeature(id: "seg-2", coordinates: targetCoordinates)],
            trackedPathSegments: [shiftedPath]
        )

        XCTAssertEqual(progress.matchedSegmentCount, 0)
        XCTAssertEqual(progress.remainingSegmentCount, 1)
        XCTAssertFalse(progress.likelyComplete)
        XCTAssertEqual(progress.completionRatio, 0, accuracy: 0.0001)
    }

    func testEvaluateNavigationProgressMarksLikelyCompleteWhenOneSegmentRemains() {
        let firstSegment = [
            CLLocationCoordinate2D(latitude: 31.5700, longitude: -97.1600),
            CLLocationCoordinate2D(latitude: 31.5706, longitude: -97.1594),
        ]
        let secondSegment = [
            CLLocationCoordinate2D(latitude: 31.5710, longitude: -97.1588),
            CLLocationCoordinate2D(latitude: 31.5716, longitude: -97.1582),
        ]

        let progress = MapGeometry.evaluateNavigationProgress(
            target: makeTarget(id: "cluster-3", segmentIDs: ["seg-a", "seg-b"]),
            coverageFeatures: [
                makeCoverageFeature(id: "seg-a", coordinates: firstSegment),
                makeCoverageFeature(id: "seg-b", coordinates: secondSegment),
            ],
            trackedPathSegments: [firstSegment]
        )

        XCTAssertEqual(progress.matchedSegmentCount, 1)
        XCTAssertEqual(progress.remainingSegmentCount, 1)
        XCTAssertTrue(progress.likelyComplete)
    }

    private func makeCoverageFeature(
        id: String,
        coordinates: [CLLocationCoordinate2D]
    ) -> CoverageMapFeature {
        let bbox = GeometrySimplifier.computeBoundingBox(coordinates) ?? TripBoundingBox(
            minLat: coordinates[0].latitude,
            maxLat: coordinates[0].latitude,
            minLon: coordinates[0].longitude,
            maxLon: coordinates[0].longitude
        )

        return CoverageMapFeature(
            id: id,
            status: .undriven,
            name: id,
            bbox: MapBoundingBox(
                minLon: bbox.minLon,
                minLat: bbox.minLat,
                maxLon: bbox.maxLon,
                maxLat: bbox.maxLat
            ),
            geom: EncodedGeometryLOD(
                full: Polyline6.encode(coordinates),
                medium: Polyline6.encode(coordinates),
                low: Polyline6.encode(coordinates)
            )
        )
    }

    private func makeTarget(
        id: String,
        segmentIDs: [String]
    ) -> CoverageNavigationTarget {
        CoverageNavigationTarget(
            id: id,
            rank: 1,
            title: "Target \(id)",
            reason: "Nearby undriven cluster",
            destination: CoverageNavigationCoordinate(latitude: 31.55, longitude: -97.14),
            bbox: MapBoundingBox(minLon: -97.20, minLat: 31.50, maxLon: -97.10, maxLat: 31.60),
            segmentIDs: segmentIDs,
            undrivenSegmentCount: segmentIDs.count,
            undrivenLengthMiles: 1.0,
            distanceFromOriginMiles: 0.7,
            etaMinutes: 4,
            score: 0.9
        )
    }
}
