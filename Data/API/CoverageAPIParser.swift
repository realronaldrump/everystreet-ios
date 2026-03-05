import CoreLocation
import Foundation

enum CoverageAPIParser {
    static func parseAreas(data: Data) throws -> [CoverageArea] {
        let object = try JSONSerialization.jsonObject(with: data)

        if let root = object as? [String: Any] {
            let rawAreas = root["areas"] as? [[String: Any]] ?? []
            return rawAreas.compactMap(parseArea)
        }

        if let rawAreas = object as? [[String: Any]] {
            return rawAreas.compactMap(parseArea)
        }

        throw APIError.decodingFailed(context: "coverage-areas")
    }

    static func parseAreaDetail(data: Data) throws -> CoverageAreaDetail {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "coverage-area-detail")
        }

        guard let areaObject = root["area"] as? [String: Any],
              let area = parseArea(areaObject)
        else {
            throw APIError.decodingFailed(context: "coverage-area-detail-area")
        }

        let boundingBox = parseBoundingBox(root["bounding_box"])
        let hasOptimalRoute = root.bool("has_optimal_route") ?? area.hasOptimalRoute

        return CoverageAreaDetail(
            area: area,
            boundingBox: boundingBox,
            hasOptimalRoute: hasOptimalRoute
        )
    }

    static func parseStreets(data: Data) throws -> CoverageStreetsSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "coverage-streets")
        }

        let features = root["features"] as? [[String: Any]] ?? []
        let segments = features.compactMap(parseStreetFeature)

        return CoverageStreetsSnapshot(
            segments: segments,
            totalInViewport: root.int("total_in_viewport") ?? segments.count,
            truncated: root.bool("truncated") ?? false
        )
    }

    private static func parseArea(_ raw: [String: Any]) -> CoverageArea? {
        guard let id = raw.string("id") else { return nil }
        guard let displayName = raw.string("display_name") ?? raw.string("name") else { return nil }

        return CoverageArea(
            id: id,
            displayName: displayName,
            areaType: raw.string("area_type") ?? "unknown",
            status: raw.string("status") ?? "unknown",
            health: raw.string("health"),
            totalLengthMiles: raw.double("total_length_miles") ?? 0,
            driveableLengthMiles: raw.double("driveable_length_miles") ?? 0,
            drivenLengthMiles: raw.double("driven_length_miles") ?? 0,
            coveragePercentage: raw.double("coverage_percentage") ?? 0,
            totalSegments: raw.int("total_segments") ?? 0,
            drivenSegments: raw.int("driven_segments") ?? 0,
            createdAt: parseDate(raw["created_at"]),
            lastSynced: parseDate(raw["last_synced"]),
            hasOptimalRoute: raw.bool("has_optimal_route") ?? false
        )
    }

    private static func parseStreetFeature(_ raw: [String: Any]) -> CoverageStreetSegment? {
        guard let properties = raw["properties"] as? [String: Any] else { return nil }
        guard let geometry = raw["geometry"] as? [String: Any] else { return nil }

        let coordinates = parseStreetCoordinates(geometry)
        guard coordinates.count > 1 else { return nil }

        let status = CoverageStreetStatus(apiValue: properties.string("status") ?? properties.string("coverage_status"))
        let segmentID = properties.string("segment_id")
            ?? properties.string("segmentId")
            ?? properties.string("id")
            ?? fallbackSegmentID(from: coordinates, status: status)

        return CoverageStreetSegment(
            id: segmentID,
            status: status,
            name: properties.string("name") ?? properties.string("street_name"),
            coordinates: coordinates
        )
    }

    private static func parseStreetCoordinates(_ geometry: [String: Any]) -> [CLLocationCoordinate2D] {
        guard let coordinateArray = geometry["coordinates"] as? [Any] else {
            return []
        }

        let type = geometry.string("type")?.lowercased()
        if type == "multilinestring" {
            return parseMultiLineString(coordinateArray)
        }

        if let line = parseLineString(coordinateArray), !line.isEmpty {
            return line
        }

        return parseMultiLineString(coordinateArray)
    }

    private static func parseLineString(_ raw: [Any]) -> [CLLocationCoordinate2D]? {
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(raw.count)

        for item in raw {
            guard let pair = item as? [Any], pair.count >= 2 else { return nil }
            guard let lon = JSONHelpers.double(from: pair[0]),
                  let lat = JSONHelpers.double(from: pair[1])
            else {
                return nil
            }
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return coordinates
    }

    private static func parseMultiLineString(_ raw: [Any]) -> [CLLocationCoordinate2D] {
        var flattened: [CLLocationCoordinate2D] = []

        for item in raw {
            guard let line = item as? [Any] else { continue }
            guard let parsedLine = parseLineString(line) else { continue }
            flattened.append(contentsOf: parsedLine)
        }

        return flattened
    }

    private static func parseBoundingBox(_ raw: Any?) -> TripBoundingBox? {
        guard let values = raw as? [Any], values.count >= 4 else { return nil }
        guard let a = JSONHelpers.double(from: values[0]),
              let b = JSONHelpers.double(from: values[1]),
              let c = JSONHelpers.double(from: values[2]),
              let d = JSONHelpers.double(from: values[3])
        else {
            return nil
        }

        if let lonLat = makeBoundingBox(minLat: b, maxLat: d, minLon: a, maxLon: c) {
            return lonLat
        }

        return makeBoundingBox(minLat: a, maxLat: c, minLon: b, maxLon: d)
    }

    private static func makeBoundingBox(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> TripBoundingBox? {
        guard (-90 ... 90).contains(minLat), (-90 ... 90).contains(maxLat) else { return nil }
        guard (-180 ... 180).contains(minLon), (-180 ... 180).contains(maxLon) else { return nil }
        guard minLat < maxLat, minLon < maxLon else { return nil }

        return TripBoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        if let parsed = JSONHelpers.date(from: raw) {
            return parsed
        }

        guard let value = raw as? String else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func fallbackSegmentID(from coordinates: [CLLocationCoordinate2D], status: CoverageStreetStatus) -> String {
        guard let first = coordinates.first, let last = coordinates.last else {
            return UUID().uuidString
        }

        return String(
            format: "%@-%.5f-%.5f-%.5f-%.5f",
            status.rawValue,
            first.latitude,
            first.longitude,
            last.latitude,
            last.longitude
        )
    }
}
