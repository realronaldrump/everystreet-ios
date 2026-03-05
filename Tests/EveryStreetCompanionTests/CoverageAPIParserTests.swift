import XCTest
@testable import EveryStreetCompanion

final class CoverageAPIParserTests: XCTestCase {
    func testParseAreas() throws {
        let json = """
        {
          "success": true,
          "areas": [
            {
              "id": "area-1",
              "display_name": "Waco, TX",
              "area_type": "city",
              "status": "ready",
              "health": "healthy",
              "total_length_miles": 100.2,
              "driveable_length_miles": 95.0,
              "driven_length_miles": 61.3,
              "coverage_percentage": 64.5,
              "total_segments": 1200,
              "driven_segments": 774,
              "created_at": "2025-12-01T10:00:00Z",
              "last_synced": "2025-12-02T11:00:00Z",
              "optimal_route_generated_at": null,
              "has_optimal_route": false
            }
          ]
        }
        """

        let areas = try CoverageAPIParser.parseAreas(data: Data(json.utf8))
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(areas.first?.id, "area-1")
        XCTAssertEqual(areas.first?.displayName, "Waco, TX")
        let coverage = try XCTUnwrap(areas.first?.coveragePercentage)
        XCTAssertEqual(coverage, 64.5, accuracy: 0.001)
        XCTAssertEqual(areas.first?.undrivenSegments, 426)
    }

    func testParseAreaDetailBoundingBoxLonLatOrder() throws {
        let json = """
        {
          "success": true,
          "area": {
            "id": "area-2",
            "display_name": "Austin, TX",
            "area_type": "city",
            "status": "ready",
            "health": "healthy",
            "total_length_miles": 200.0,
            "driveable_length_miles": 190.0,
            "driven_length_miles": 120.0,
            "coverage_percentage": 63.1,
            "total_segments": 2500,
            "driven_segments": 1600,
            "created_at": "2025-12-01",
            "last_synced": "2025-12-02",
            "optimal_route_generated_at": null,
            "has_optimal_route": true
          },
          "bounding_box": [-98.1, 30.1, -97.5, 30.6],
          "has_optimal_route": true
        }
        """

        let detail = try CoverageAPIParser.parseAreaDetail(data: Data(json.utf8))
        XCTAssertNotNil(detail.boundingBox)
        XCTAssertTrue(detail.hasOptimalRoute)

        let box = try XCTUnwrap(detail.boundingBox)
        XCTAssertEqual(box.minLon, -98.1, accuracy: 0.001)
        XCTAssertEqual(box.minLat, 30.1, accuracy: 0.001)
        XCTAssertEqual(box.maxLon, -97.5, accuracy: 0.001)
        XCTAssertEqual(box.maxLat, 30.6, accuracy: 0.001)
    }

    func testParseCoverageMapBundle() throws {
        let json = """
        {
          "revision": "cov-rev-1",
          "generated_at": "2026-03-04T12:00:00Z",
          "area": {
            "id": "area-1",
            "display_name": "Waco, TX",
            "coverage_percentage": 64.5,
            "total_segments": 1200,
            "driven_segments": 774
          },
          "bbox": [-98.0, 30.0, -97.0, 31.0],
          "segment_count": 1,
          "segments": [
            {
              "id": "seg-1",
              "status": "driven",
              "name": "Main St",
              "bbox": [-97.2, 31.5, -97.1, 31.6],
              "geom": {
                "full": "gvrd{@vsjhxD_q@wj@",
                "medium": "gvrd{@vsjhxD_q@wj@",
                "low": "gvrd{@vsjhxD_q@wj@"
              }
            }
          ]
        }
        """

        let bundle = try CoverageAPIParser.parseCoverageMapBundle(data: Data(json.utf8))
        XCTAssertEqual(bundle.revision, "cov-rev-1")
        XCTAssertEqual(bundle.area.displayName, "Waco, TX")
        XCTAssertEqual(bundle.segmentCount, 1)
        XCTAssertEqual(bundle.segments.first?.id, "seg-1")
        XCTAssertEqual(bundle.segments.first?.status, .driven)
    }
}
