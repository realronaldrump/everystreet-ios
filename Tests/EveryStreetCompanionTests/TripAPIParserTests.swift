import CoreLocation
import XCTest
@testable import EveryStreetCompanion

final class TripAPIParserTests: XCTestCase {
    func testParseFeatureCollection() throws {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "LineString",
                "coordinates": [[-97.1,31.5],[-97.0,31.6],[-96.9,31.7]]
              },
              "properties": {
                "transactionId": "trip-1",
                "imei": "123",
                "startTime": "2026-03-01T10:00:00+00:00",
                "endTime": "2026-03-01T10:30:00+00:00",
                "distance": 12.5,
                "destination": "Downtown",
                "startLocation": "Home"
              }
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let trips = try TripAPIParser.parseTripFeatureCollection(data: data)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.transactionId, "trip-1")
        XCTAssertEqual(trips.first?.fullGeometry.count, 3)
    }

    func testParseTripDetail() throws {
        let json = """
        {
          "status": "success",
          "trip": {
            "transactionId": "trip-2",
            "imei": "123",
            "startTime": "2026-03-01T10:00:00+00:00",
            "endTime": "2026-03-01T10:30:00+00:00",
            "gps": {
              "type": "LineString",
              "coordinates": [[-97.1,31.5],[-97.0,31.6]]
            }
          }
        }
        """

        let detail = try TripAPIParser.parseTripDetail(data: Data(json.utf8))
        XCTAssertEqual(detail.transactionId, "trip-2")
        XCTAssertEqual(detail.rawGeometry.count, 2)
    }

    func testParseTripMapBundle() throws {
        let json = """
        {
          "revision": "rev-1",
          "generated_at": "2026-03-04T12:00:00Z",
          "bbox": [-98.0, 30.0, -97.0, 31.0],
          "trip_count": 1,
          "trips": [
            {
              "id": "trip-abc",
              "start_time": "2026-03-01T10:00:00Z",
              "end_time": "2026-03-01T11:00:00Z",
              "imei": "12345",
              "distance_miles": 12.7,
              "start_location": "Home",
              "destination": "Downtown",
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

        let bundle = try TripAPIParser.parseTripMapBundle(data: Data(json.utf8))
        XCTAssertEqual(bundle.revision, "rev-1")
        XCTAssertEqual(bundle.tripCount, 1)
        XCTAssertEqual(bundle.trips.count, 1)
        XCTAssertEqual(bundle.trips.first?.id, "trip-abc")
        XCTAssertEqual(bundle.trips.first?.geom.full, "gvrd{@vsjhxD_q@wj@")
    }

    func testBuildTripMapBundleFromSummaries() {
        let start = Date(timeIntervalSince1970: 1_709_300_000)
        let end = start.addingTimeInterval(1_800)
        let coordinates = [
            CLLocationCoordinate2D(latitude: 31.50, longitude: -97.10),
            CLLocationCoordinate2D(latitude: 31.55, longitude: -97.05),
            CLLocationCoordinate2D(latitude: 31.60, longitude: -97.00)
        ]

        let trip = TripSummary(
            transactionId: "trip-clip-1",
            imei: "imei-1",
            vin: nil,
            vehicleLabel: nil,
            startTime: start,
            endTime: end,
            distance: 8.4,
            duration: 1_800,
            maxSpeed: nil,
            totalIdleDuration: nil,
            fuelConsumed: nil,
            estimatedCost: nil,
            startLocation: "Home",
            destination: "Store",
            status: "completed",
            previewPath: nil,
            boundingBox: nil,
            fullGeometry: coordinates,
            mediumGeometry: coordinates,
            lowGeometry: [coordinates.first!, coordinates.last!]
        )

        let query = TripQuery(
            dateRange: DateInterval(start: start, end: end),
            imei: nil,
            source: .rawTripsOnly,
            coverageAreaID: "area-1"
        )

        let bundle = TripAPIParser.buildTripMapBundle(from: [trip], query: query, generatedAt: start)
        XCTAssertEqual(bundle.tripCount, 1)
        XCTAssertEqual(bundle.trips.count, 1)
        XCTAssertEqual(bundle.trips.first?.id, "trip-clip-1")
        XCTAssertEqual(Polyline6.decode(bundle.trips.first?.geom.full ?? "").count, 3)
        XCTAssertEqual(bundle.bbox.minLon, -97.10, accuracy: 0.0001)
        XCTAssertEqual(bundle.bbox.maxLat, 31.60, accuracy: 0.0001)
    }
}
