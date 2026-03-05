import CoreLocation
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

    func testParseNavigationSuggestionSet() throws {
        let json = """
        {
          "generated_at": "2026-03-05T12:34:56Z",
          "area": {
            "id": "area-nav-1",
            "display_name": "Waco, TX"
          },
          "origin": {
            "lat": 31.5493,
            "lon": -97.1467
          },
          "suggestions": [
            {
              "id": "cluster-1",
              "rank": 1,
              "title": "Downtown East",
              "reason": "8 undriven segments within a short detour",
              "destination_coordinate": {
                "lat": 31.5510,
                "lon": -97.1402
              },
              "bbox": [-97.1500, 31.5480, -97.1380, 31.5540],
              "segment_ids": ["seg-1", "seg-2", "seg-3"],
              "undriven_segment_count": 3,
              "undriven_length_miles": 1.6,
              "distance_from_origin_miles": 0.9,
              "eta_minutes": 4,
              "score": 0.93
            }
          ]
        }
        """

        let suggestionSet = try CoverageAPIParser.parseNavigationSuggestionSet(data: Data(json.utf8))
        XCTAssertEqual(suggestionSet.areaID, "area-nav-1")
        XCTAssertEqual(suggestionSet.areaDisplayName, "Waco, TX")
        XCTAssertEqual(suggestionSet.suggestions.count, 1)
        XCTAssertEqual(suggestionSet.suggestions.first?.id, "cluster-1")
        XCTAssertEqual(suggestionSet.suggestions.first?.segmentIDs.count, 3)
        XCTAssertEqual(suggestionSet.origin.latitude, 31.5493, accuracy: 0.000001)
        let destinationLongitude = try XCTUnwrap(suggestionSet.suggestions.first?.destination.longitude)
        XCTAssertEqual(destinationLongitude, -97.1402, accuracy: 0.000001)
    }

    func testParseLegacyNavigationSuggestionSet() throws {
        let json = """
        {
          "status": "success",
          "suggested_clusters": [
            {
              "cluster_id": 7,
              "segment_count": 2,
              "segments": [
                {
                  "segment_id": "seg-101",
                  "street_name": "Pine Avenue",
                  "geometry": {
                    "type": "LineString",
                    "coordinates": [[-97.1500, 31.5400], [-97.1490, 31.5410]]
                  },
                  "length_m": 150.0
                },
                {
                  "segment_id": "seg-102",
                  "street_name": "Oak Street",
                  "geometry": {
                    "type": "LineString",
                    "coordinates": [[-97.1490, 31.5410], [-97.1480, 31.5420]]
                  },
                  "length_m": 175.0
                }
              ],
              "centroid": [-97.1490, 31.5410],
              "total_length_m": 325.0,
              "distance_to_cluster_m": 804.67,
              "efficiency_score": 0.4,
              "nearest_segment": {
                "segment_id": "seg-101",
                "street_name": "Pine Avenue",
                "geometry": {
                  "type": "LineString",
                  "coordinates": [[-97.1500, 31.5400], [-97.1490, 31.5410]]
                }
              }
            }
          ]
        }
        """

        let suggestionSet = try CoverageAPIParser.parseLegacyNavigationSuggestionSet(
            data: Data(json.utf8),
            areaID: "area-legacy-1",
            areaDisplayName: "Waco, TX",
            origin: CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467)
        )

        XCTAssertEqual(suggestionSet.areaID, "area-legacy-1")
        XCTAssertEqual(suggestionSet.suggestions.count, 1)
        XCTAssertEqual(suggestionSet.suggestions.first?.id, "7")
        XCTAssertEqual(suggestionSet.suggestions.first?.segmentIDs, ["seg-101", "seg-102"])
        XCTAssertEqual(suggestionSet.suggestions.first?.undrivenLengthMiles ?? 0, 325.0 / 1609.344, accuracy: 0.0001)
        XCTAssertEqual(suggestionSet.suggestions.first?.distanceFromOriginMiles ?? 0, 804.67 / 1609.344, accuracy: 0.0001)
    }
}

@MainActor
final class CoverageNavigationControllerTests: XCTestCase {
    func testLoadSuggestionsPreservesSelectedTargetWhenStillPresent() async {
        let repository = MockCoverageRepository()
        repository.navigationResponses = [
            makeSuggestionSet(ids: ["cluster-a", "cluster-b", "cluster-c"], generatedAt: Date(timeIntervalSince1970: 100)),
            makeSuggestionSet(ids: ["cluster-b", "cluster-a", "cluster-d"], generatedAt: Date(timeIntervalSince1970: 200)),
        ]
        let controller = CoverageNavigationController(repository: repository)
        let origin = CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467)

        await controller.loadSuggestions(areaID: "area-1", origin: origin, preserveActiveSelection: false)
        controller.selectTarget(id: "cluster-b")
        await controller.loadSuggestions(areaID: "area-1", origin: origin, preserveActiveSelection: true)

        XCTAssertEqual(controller.activeTarget?.id, "cluster-b")
        XCTAssertEqual(repository.navigationRequests.count, 2)
        XCTAssertEqual(repository.navigationRequests.last?.limit, 3)
    }

    func testRefreshIfNeededOnReturnRefetchesWhenCurrentTargetIsLikelyComplete() async {
        let repository = MockCoverageRepository()
        repository.navigationResponses = [
            makeSuggestionSet(ids: ["cluster-a", "cluster-b", "cluster-c"], generatedAt: Date(timeIntervalSince1970: 100)),
            makeSuggestionSet(ids: ["cluster-z", "cluster-y", "cluster-x"], generatedAt: Date(timeIntervalSince1970: 200)),
        ]
        let controller = CoverageNavigationController(
            repository: repository,
            nowProvider: { Date(timeIntervalSince1970: 220) }
        )
        let origin = CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467)

        await controller.loadSuggestions(areaID: "area-1", origin: origin, preserveActiveSelection: false)
        controller.progress = CoverageNavigationProgress(
            matchedSegmentIDs: ["seg-1", "seg-2"],
            matchedSegmentCount: 2,
            remainingSegmentCount: 1,
            coveredLengthMiles: 1.0,
            totalLengthMiles: 1.2,
            completionRatio: 0.83,
            likelyComplete: true,
            trackingActive: true,
            hasRecordedPath: true
        )

        await controller.refreshIfNeededOnReturn(areaID: "area-1", origin: origin)

        XCTAssertEqual(repository.navigationRequests.count, 2)
        XCTAssertEqual(controller.activeTarget?.id, "cluster-z")
    }

    func testLaunchNavigationUsesMapsLauncher() async {
        let repository = MockCoverageRepository()
        repository.navigationResponses = [makeSuggestionSet(ids: ["cluster-a", "cluster-b", "cluster-c"], generatedAt: Date(timeIntervalSince1970: 100))]
        let launcher = MockMapsLauncher()
        let controller = CoverageNavigationController(repository: repository, mapsLauncher: launcher)
        let origin = CLLocationCoordinate2D(latitude: 31.5493, longitude: -97.1467)

        await controller.loadSuggestions(areaID: "area-1", origin: origin, preserveActiveSelection: false)
        let didLaunch = controller.launchNavigation()

        XCTAssertTrue(didLaunch)
        XCTAssertEqual(launcher.launchedTargetIDs, ["cluster-a"])
    }

    private func makeSuggestionSet(ids: [String], generatedAt: Date) -> CoverageNavigationSuggestionSet {
        CoverageNavigationSuggestionSet(
            areaID: "area-1",
            areaDisplayName: "Waco, TX",
            generatedAt: generatedAt,
            origin: CoverageNavigationCoordinate(latitude: 31.5493, longitude: -97.1467),
            suggestions: ids.enumerated().map { index, id in
                CoverageNavigationTarget(
                    id: id,
                    rank: index + 1,
                    title: "Target \(id)",
                    reason: "Undriven cluster \(index + 1)",
                    destination: CoverageNavigationCoordinate(
                        latitude: 31.5493 + Double(index) * 0.001,
                        longitude: -97.1467 + Double(index) * 0.001
                    ),
                    bbox: MapBoundingBox(
                        minLon: -97.1500 + Double(index) * 0.001,
                        minLat: 31.5480 + Double(index) * 0.001,
                        maxLon: -97.1400 + Double(index) * 0.001,
                        maxLat: 31.5540 + Double(index) * 0.001
                    ),
                    segmentIDs: ["seg-\(index)-a", "seg-\(index)-b"],
                    undrivenSegmentCount: 2,
                    undrivenLengthMiles: 1.0 + Double(index) * 0.2,
                    distanceFromOriginMiles: 0.5 + Double(index) * 0.3,
                    etaMinutes: 3 + Double(index),
                    score: 0.9 - Double(index) * 0.1
                )
            }
        )
    }

    private final class MockCoverageRepository: CoverageRepository {
        var navigationResponses: [CoverageNavigationSuggestionSet] = []
        var navigationRequests: [(areaID: String, origin: CLLocationCoordinate2D, limit: Int)] = []

        func loadCoverageAreas() async throws -> [CoverageArea] { [] }

        func loadCoverageAreaDetail(id: String) async throws -> CoverageAreaDetail {
            CoverageAreaDetail(
                area: CoverageArea(
                    id: id,
                    displayName: "Area",
                    areaType: "city",
                    status: "ready",
                    health: nil,
                    totalLengthMiles: 10,
                    driveableLengthMiles: 9,
                    drivenLengthMiles: 4,
                    coveragePercentage: 44,
                    totalSegments: 100,
                    drivenSegments: 44,
                    createdAt: nil,
                    lastSynced: nil,
                    hasOptimalRoute: false
                ),
                boundingBox: nil,
                hasOptimalRoute: false
            )
        }

        func loadCoverageMapBundle(
            areaID _: String,
            status _: CoverageMapStatusFilter
        ) async throws -> CoverageMapBundle {
            CoverageMapBundle(
                revision: "rev",
                generatedAt: .now,
                area: CoverageMapAreaSummary(
                    id: "area-1",
                    displayName: "Area",
                    coveragePercentage: 44,
                    totalSegments: 100,
                    drivenSegments: 44
                ),
                bbox: MapBoundingBox(minLon: -97.2, minLat: 31.5, maxLon: -97.1, maxLat: 31.6),
                segmentCount: 0,
                segments: []
            )
        }

        func loadNavigationSuggestions(
            areaID: String,
            origin: CLLocationCoordinate2D,
            limit: Int
        ) async throws -> CoverageNavigationSuggestionSet {
            navigationRequests.append((areaID: areaID, origin: origin, limit: limit))
            return navigationResponses.removeFirst()
        }
    }

    private final class MockMapsLauncher: MapsLaunching {
        var launchedTargetIDs: [String] = []

        func openDrivingDirections(for target: CoverageNavigationTarget) -> Bool {
            launchedTargetIDs.append(target.id)
            return true
        }
    }
}
