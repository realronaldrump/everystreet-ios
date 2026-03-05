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

    static func parseNavigationSuggestionSet(data: Data) throws -> CoverageNavigationSuggestionSet {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "coverage-navigation-root")
        }

        let generatedAt = root.date("generated_at") ?? .now

        let areaObject = root["area"] as? [String: Any]
        let areaID = areaObject?.string("id") ?? root.string("area_id")
        let areaDisplayName = areaObject?.string("display_name") ?? root.string("area_display_name")

        guard let areaID, let areaDisplayName else {
            throw APIError.decodingFailed(context: "coverage-navigation-area")
        }

        guard let origin = parseNavigationCoordinate(root["origin"] ?? root["current_position"]) else {
            throw APIError.decodingFailed(context: "coverage-navigation-origin")
        }

        let suggestions = (root["suggestions"] as? [[String: Any]] ?? []).compactMap(parseNavigationTarget)

        return CoverageNavigationSuggestionSet(
            areaID: areaID,
            areaDisplayName: areaDisplayName,
            generatedAt: generatedAt,
            origin: origin,
            suggestions: suggestions.sorted { lhs, rhs in
                if lhs.rank == rhs.rank {
                    return lhs.id < rhs.id
                }
                return lhs.rank < rhs.rank
            }
        )
    }

    static func parseLegacyNavigationSuggestionSet(
        data: Data,
        areaID: String,
        areaDisplayName: String?,
        origin: CLLocationCoordinate2D
    ) throws -> CoverageNavigationSuggestionSet {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "legacy-coverage-navigation-root")
        }

        let clusters = root["suggested_clusters"] as? [[String: Any]] ?? []
        let suggestions = clusters.enumerated().compactMap { index, cluster in
            parseLegacyNavigationTarget(cluster, rank: index + 1)
        }

        return CoverageNavigationSuggestionSet(
            areaID: areaID,
            areaDisplayName: areaDisplayName ?? areaID,
            generatedAt: .now,
            origin: CoverageNavigationCoordinate(latitude: origin.latitude, longitude: origin.longitude),
            suggestions: suggestions
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

    private static func parseNavigationTarget(_ raw: [String: Any]) -> CoverageNavigationTarget? {
        guard let id = raw.string("id") else { return nil }
        guard let title = raw.string("title") ?? raw.string("name") else { return nil }
        guard let destination = parseNavigationCoordinate(raw["destination_coordinate"] ?? raw["destination"]) else { return nil }

        let bboxRaw = raw["bbox"] as? [Any]
        let bboxValues = bboxRaw?.compactMap(JSONHelpers.double(from:)) ?? []
        guard let bbox = MapBoundingBox(array: bboxValues) else { return nil }

        let segmentIDs = (raw["segment_ids"] as? [Any] ?? []).compactMap(JSONHelpers.string(from:))
        let rank = raw.int("rank") ?? Int(raw.double("rank") ?? 0)

        return CoverageNavigationTarget(
            id: id,
            rank: rank > 0 ? rank : 1,
            title: title,
            reason: raw.string("reason") ?? "Undriven cluster nearby",
            destination: destination,
            bbox: bbox,
            segmentIDs: segmentIDs,
            segmentDestinations: [:],
            undrivenSegmentCount: raw.int("undriven_segment_count") ?? segmentIDs.count,
            undrivenLengthMiles: raw.double("undriven_length_miles") ?? 0,
            distanceFromOriginMiles: raw.double("distance_from_origin_miles"),
            etaMinutes: raw.double("eta_minutes"),
            score: raw.double("score")
        )
    }

    private static func parseNavigationCoordinate(_ raw: Any?) -> CoverageNavigationCoordinate? {
        if let point = raw as? [Any], let coordinate = JSONHelpers.parsePoint(point) {
            return CoverageNavigationCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        guard let object = raw as? [String: Any] else { return nil }

        let latitude = object.double("lat") ?? object.double("latitude")
        let longitude = object.double("lon") ?? object.double("lng") ?? object.double("longitude")

        guard let latitude, let longitude else { return nil }

        return CoverageNavigationCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func parseLegacyNavigationTarget(
        _ raw: [String: Any],
        rank: Int
    ) -> CoverageNavigationTarget? {
        let segmentObjects = raw["segments"] as? [[String: Any]] ?? []
        let segmentIDs = segmentObjects.compactMap { segment in
            segment.string("segment_id")
        }

        let allCoordinates = segmentObjects.flatMap { segment in
            JSONHelpers.coordinates(from: segment["geometry"])
        }

        let bbox = makeMapBoundingBox(from: allCoordinates)
        guard let bbox else { return nil }

        let nearestSegment = raw["nearest_segment"] as? [String: Any]
        let nearestSegmentCoordinates = JSONHelpers.coordinates(from: nearestSegment?["geometry"])
        let destinationCoordinate = midpointCoordinate(of: nearestSegmentCoordinates)
            ?? midpointCoordinate(of: allCoordinates)
            ?? parseNavigationCoordinate(raw["centroid"])?.clLocationCoordinate2D

        guard let destinationCoordinate else { return nil }

        let targetID = raw.string("cluster_id") ?? "cluster-\(rank)"
        let nearestStreetName = nearestSegment?.string("street_name")
        let title = nearestStreetName?.isEmpty == false
            ? "Cluster near \(nearestStreetName!)"
            : "Undriven cluster \(rank)"

        let segmentCount = raw.int("segment_count") ?? segmentIDs.count
        let totalLengthMiles = (raw.double("total_length_m") ?? 0) / 1_609.344
        let distanceMiles = (raw.double("distance_to_cluster_m") ?? 0) / 1_609.344
        let segmentDestinations = Dictionary(uniqueKeysWithValues: segmentObjects.compactMap { segment -> (String, CoverageNavigationCoordinate)? in
            guard let segmentID = segment.string("segment_id") else { return nil }
            let coordinates = JSONHelpers.coordinates(from: segment["geometry"])
            guard let midpoint = midpointCoordinate(of: coordinates) else { return nil }
            return (
                segmentID,
                CoverageNavigationCoordinate(latitude: midpoint.latitude, longitude: midpoint.longitude)
            )
        })

        return CoverageNavigationTarget(
            id: targetID,
            rank: rank,
            title: title,
            reason: String(format: "%d undriven segments • %.1f mi remaining", segmentCount, totalLengthMiles),
            destination: CoverageNavigationCoordinate(
                latitude: destinationCoordinate.latitude,
                longitude: destinationCoordinate.longitude
            ),
            bbox: bbox,
            segmentIDs: segmentIDs,
            segmentDestinations: segmentDestinations,
            undrivenSegmentCount: segmentCount,
            undrivenLengthMiles: totalLengthMiles,
            distanceFromOriginMiles: distanceMiles > 0 ? distanceMiles : nil,
            etaMinutes: nil,
            score: raw.double("efficiency_score")
        )
    }

    private static func makeMapBoundingBox(from coordinates: [CLLocationCoordinate2D]) -> MapBoundingBox? {
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max()
        else {
            return nil
        }

        return MapBoundingBox(
            minLon: minLon,
            minLat: minLat,
            maxLon: maxLon,
            maxLat: maxLat
        )
    }

    private static func midpointCoordinate(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }
        if coordinates.count == 1 {
            return coordinates[0]
        }

        let middleIndex = coordinates.count / 2
        if coordinates.count.isMultiple(of: 2) {
            let first = coordinates[max(middleIndex - 1, 0)]
            let second = coordinates[middleIndex]
            return CLLocationCoordinate2D(
                latitude: (first.latitude + second.latitude) / 2,
                longitude: (first.longitude + second.longitude) / 2
            )
        }

        return coordinates[middleIndex]
    }
}
