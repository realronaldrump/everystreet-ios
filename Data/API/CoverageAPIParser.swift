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

    static func parseCoverageMapBundle(data: Data) throws -> CoverageMapBundle {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "coverage-map-bundle")
        }

        let revision = root.string("revision") ?? ""
        let generatedAt = root.date("generated_at") ?? .now

        guard let areaObject = root["area"] as? [String: Any],
              let area = parseCoverageMapAreaSummary(areaObject)
        else {
            throw APIError.decodingFailed(context: "coverage-map-bundle-area")
        }

        guard let bboxRaw = root["bbox"] as? [Any] else {
            throw APIError.decodingFailed(context: "coverage-map-bundle-bbox")
        }

        let bboxValues = bboxRaw.compactMap(JSONHelpers.double(from:))
        guard let bbox = MapBoundingBox(array: bboxValues) else {
            throw APIError.decodingFailed(context: "coverage-map-bundle-bbox-values")
        }

        let segments = (root["segments"] as? [[String: Any]] ?? []).compactMap(parseCoverageMapFeature)
        let segmentCount = root.int("segment_count") ?? segments.count

        return CoverageMapBundle(
            revision: revision,
            generatedAt: generatedAt,
            area: area,
            bbox: bbox,
            segmentCount: segmentCount,
            segments: segments
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

    private static func parseCoverageMapAreaSummary(_ raw: [String: Any]) -> CoverageMapAreaSummary? {
        guard let id = raw.string("id"), let displayName = raw.string("display_name") else { return nil }
        return CoverageMapAreaSummary(
            id: id,
            displayName: displayName,
            coveragePercentage: raw.double("coverage_percentage") ?? 0,
            totalSegments: raw.int("total_segments") ?? 0,
            drivenSegments: raw.int("driven_segments") ?? 0
        )
    }

    private static func parseCoverageMapFeature(_ raw: [String: Any]) -> CoverageMapFeature? {
        guard let id = raw.string("id") else { return nil }
        let status = CoverageStreetStatus(apiValue: raw.string("status"))

        guard let bboxRaw = raw["bbox"] as? [Any] else { return nil }
        let bboxValues = bboxRaw.compactMap(JSONHelpers.double(from:))
        guard let bbox = MapBoundingBox(array: bboxValues) else { return nil }

        guard let geomObject = raw["geom"] as? [String: Any] else { return nil }
        let full = geomObject.string("full") ?? ""
        guard !full.isEmpty else { return nil }

        let geom = EncodedGeometryLOD(
            full: full,
            medium: geomObject.string("medium") ?? full,
            low: geomObject.string("low") ?? geomObject.string("medium") ?? full
        )

        return CoverageMapFeature(
            id: id,
            status: status,
            name: raw.string("name"),
            bbox: bbox,
            geom: geom
        )
    }
}
