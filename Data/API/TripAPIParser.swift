import CoreLocation
import Foundation

enum TripAPIParser {
    static func parseTripFeatureCollection(data: Data) throws -> [TripSummary] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "Trip feature collection root")
        }

        guard let features = root["features"] as? [[String: Any]] else {
            throw APIError.decodingFailed(context: "Missing features array")
        }

        var trips: [TripSummary] = []
        trips.reserveCapacity(features.count)

        for feature in features {
            guard let summary = parseFeature(feature) else {
                continue
            }
            trips.append(summary)
        }

        return trips.sorted { $0.startTime > $1.startTime }
    }

    static func parseTripDetail(data: Data) throws -> TripDetail {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "Trip detail root")
        }
        guard let trip = root["trip"] as? [String: Any] else {
            throw APIError.decodingFailed(context: "Trip detail payload")
        }

        let gps = JSONHelpers.coordinates(from: trip["gps"])
        let matched = JSONHelpers.coordinates(from: trip["matchedGps"])
        let route = gps.isEmpty ? matched : gps

        let startLocation = parseLocationDisplay(trip["startLocation"])
        let destination = parseLocationDisplay(trip["destination"])

        let startGeoPoint = parsePoint(from: trip["startGeoPoint"])
        let destinationGeoPoint = parsePoint(from: trip["destinationGeoPoint"])

        return TripDetail(
            transactionId: trip.string("transactionId") ?? "unknown",
            imei: trip.string("imei"),
            vin: trip.string("vin"),
            status: trip.string("status"),
            matchStatus: trip.string("matchStatus"),
            startTime: trip.date("startTime"),
            endTime: trip.date("endTime"),
            distance: trip.double("distance"),
            duration: trip.double("duration"),
            avgSpeed: trip.double("avgSpeed"),
            maxSpeed: trip.double("maxSpeed"),
            currentSpeed: trip.double("currentSpeed"),
            totalIdleDuration: trip.double("totalIdleDuration"),
            fuelConsumed: trip.double("fuelConsumed"),
            pointsRecorded: trip.int("pointsRecorded"),
            hardBrakingCounts: trip.int("hardBrakingCounts"),
            hardAccelerationCounts: trip.int("hardAccelerationCounts"),
            startLocation: startLocation,
            destination: destination,
            startGeoPoint: startGeoPoint,
            destinationGeoPoint: destinationGeoPoint,
            rawGeometry: route
        )
    }

    static func parseRecentTrips(data: Data) throws -> [TripSummary] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "Recent trips root")
        }

        guard let trips = root["trips"] as? [[String: Any]] else {
            return []
        }

        return trips.compactMap { record in
            let startTime = record.date("startTime") ?? .distantPast
            return TripSummary(
                transactionId: record.string("transactionId") ?? UUID().uuidString,
                imei: record.string("imei") ?? "",
                vin: record.string("vin"),
                vehicleLabel: nil,
                startTime: startTime,
                endTime: record.date("endTime"),
                distance: record.double("distance"),
                duration: record.double("duration"),
                maxSpeed: record.double("maxSpeed"),
                totalIdleDuration: record.double("totalIdleDuration"),
                fuelConsumed: record.double("fuelConsumed"),
                estimatedCost: nil,
                startLocation: locationString(from: record["startLocation"]),
                destination: locationString(from: record["destination"]),
                status: record.string("status"),
                previewPath: nil,
                boundingBox: nil,
                fullGeometry: [],
                mediumGeometry: [],
                lowGeometry: []
            )
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private static func parseFeature(_ feature: [String: Any]) -> TripSummary? {
        guard let properties = feature["properties"] as? [String: Any] else { return nil }
        guard let transactionId = properties.string("transactionId") else { return nil }
        guard let startTime = properties.date("startTime") else { return nil }

        let full = JSONHelpers.coordinates(from: feature["geometry"])
        let medium = GeometrySimplifier.simplify(full, tolerance: 0.00045)
        let low = GeometrySimplifier.simplify(full, tolerance: 0.0018)

        return TripSummary(
            transactionId: transactionId,
            imei: properties.string("imei") ?? "",
            vin: properties.string("vin"),
            vehicleLabel: properties.string("vehicleLabel"),
            startTime: startTime,
            endTime: properties.date("endTime"),
            distance: properties.double("distance"),
            duration: properties.double("duration"),
            maxSpeed: properties.double("maxSpeed"),
            totalIdleDuration: properties.double("totalIdleDuration"),
            fuelConsumed: properties.double("fuelConsumed"),
            estimatedCost: properties.double("estimated_cost"),
            startLocation: locationString(from: properties["startLocation"]),
            destination: locationString(from: properties["destination"]),
            status: properties.string("status"),
            previewPath: properties.string("previewPath"),
            boundingBox: GeometrySimplifier.computeBoundingBox(full),
            fullGeometry: full,
            mediumGeometry: medium,
            lowGeometry: low
        )
    }

    static func parseTripMapBundle(data: Data) throws -> TripMapBundle {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "trip-map-bundle-root")
        }

        let revision = root.string("revision") ?? ""
        let generatedAt = root.date("generated_at") ?? .now
        guard let bboxArray = root["bbox"] as? [Any] else {
            throw APIError.decodingFailed(context: "trip-map-bundle-bbox")
        }

        let bboxValues = bboxArray.compactMap(JSONHelpers.double(from:))
        guard let bbox = MapBoundingBox(array: bboxValues) else {
            throw APIError.decodingFailed(context: "trip-map-bundle-bbox-values")
        }

        let features = (root["trips"] as? [[String: Any]] ?? []).compactMap(parseTripMapFeature)
        let tripCount = root.int("trip_count") ?? features.count

        return TripMapBundle(
            revision: revision,
            generatedAt: generatedAt,
            bbox: bbox,
            tripCount: tripCount,
            trips: features
        )
    }

    static func buildTripMapBundle(
        from trips: [TripSummary],
        query: TripQuery,
        generatedAt: Date = .now
    ) -> TripMapBundle {
        let features = trips
            .sorted { $0.startTime > $1.startTime }
            .compactMap(mapTripToMapFeature)
        let bbox = mergeBoundingBoxes(features.map(\.bbox))

        return TripMapBundle(
            revision: syntheticRevision(query: query, features: features, generatedAt: generatedAt),
            generatedAt: generatedAt,
            bbox: bbox,
            tripCount: features.count,
            trips: features
        )
    }

    private static func parsePoint(from any: Any?) -> CLLocationCoordinate2D? {
        guard let object = any as? [String: Any] else { return nil }
        guard let coordinates = object["coordinates"] as? [Any] else { return nil }
        return JSONHelpers.parsePoint(coordinates)
    }

    private static func parseLocationDisplay(_ any: Any?) -> LocationDisplay? {
        guard let dict = any as? [String: Any] else {
            if let raw = any as? String {
                return LocationDisplay(formattedAddress: raw, latitude: nil, longitude: nil)
            }
            return nil
        }

        let coords = dict["coordinates"] as? [String: Any]
        return LocationDisplay(
            formattedAddress: dict.string("formatted_address") ?? dict.string("formattedAddress") ?? dict.string("address"),
            latitude: coords?.double("lat") ?? coords?.double("latitude"),
            longitude: coords?.double("lng") ?? coords?.double("longitude")
        )
    }

    private static func locationString(from any: Any?) -> String? {
        if let raw = any as? String, !raw.isEmpty { return raw }
        if let dict = any as? [String: Any] {
            return dict.string("formatted_address") ?? dict.string("formattedAddress")
        }
        return nil
    }

    private static func parseTripMapFeature(_ raw: [String: Any]) -> TripMapFeature? {
        guard let id = raw.string("id") else { return nil }
        guard let startTime = raw.date("start_time") else { return nil }
        guard let imei = raw.string("imei") else { return nil }

        guard let bboxRaw = raw["bbox"] as? [Any] else { return nil }
        let bboxValues = bboxRaw.compactMap(JSONHelpers.double(from:))
        guard let bbox = MapBoundingBox(array: bboxValues) else { return nil }

        guard let geomObject = raw["geom"] as? [String: Any] else { return nil }
        let full = geomObject.string("full") ?? ""
        guard !full.isEmpty else { return nil }

        let geometry = EncodedGeometryLOD(
            full: full,
            medium: geomObject.string("medium") ?? full,
            low: geomObject.string("low") ?? geomObject.string("medium") ?? full
        )

        return TripMapFeature(
            id: id,
            startTime: startTime,
            endTime: raw.date("end_time"),
            imei: imei,
            distanceMiles: raw.double("distance_miles"),
            startLocation: raw.string("start_location"),
            destination: raw.string("destination"),
            bbox: bbox,
            geom: geometry
        )
    }

    private static func mapTripToMapFeature(_ trip: TripSummary) -> TripMapFeature? {
        let full = trip.fullGeometry
        guard full.count > 1 else { return nil }

        let medium = trip.mediumGeometry.isEmpty ? GeometrySimplifier.simplify(full, tolerance: 0.00045) : trip.mediumGeometry
        let low = trip.lowGeometry.isEmpty ? GeometrySimplifier.simplify(full, tolerance: 0.0018) : trip.lowGeometry

        guard let bbox = mapBoundingBox(for: trip, fallbackCoordinates: full) else {
            return nil
        }

        return TripMapFeature(
            id: trip.transactionId,
            startTime: trip.startTime,
            endTime: trip.endTime,
            imei: trip.imei,
            distanceMiles: trip.distance,
            startLocation: trip.startLocation,
            destination: trip.destination,
            bbox: bbox,
            geom: EncodedGeometryLOD(
                full: Polyline6.encode(full),
                medium: Polyline6.encode(medium),
                low: Polyline6.encode(low)
            )
        )
    }

    private static func mapBoundingBox(
        for trip: TripSummary,
        fallbackCoordinates: [CLLocationCoordinate2D]
    ) -> MapBoundingBox? {
        if let bbox = trip.boundingBox {
            return MapBoundingBox(
                minLon: bbox.minLon,
                minLat: bbox.minLat,
                maxLon: bbox.maxLon,
                maxLat: bbox.maxLat
            )
        }

        guard let inferred = TripBoundingBox(coordinates: fallbackCoordinates) else {
            return nil
        }

        return MapBoundingBox(
            minLon: inferred.minLon,
            minLat: inferred.minLat,
            maxLon: inferred.maxLon,
            maxLat: inferred.maxLat
        )
    }

    private static func mergeBoundingBoxes(_ boxes: [MapBoundingBox]) -> MapBoundingBox {
        guard let first = boxes.first else {
            return MapBoundingBox(minLon: 0, minLat: 0, maxLon: 0, maxLat: 0)
        }

        return boxes.dropFirst().reduce(first) { current, next in
            MapBoundingBox(
                minLon: min(current.minLon, next.minLon),
                minLat: min(current.minLat, next.minLat),
                maxLon: max(current.maxLon, next.maxLon),
                maxLat: max(current.maxLat, next.maxLat)
            )
        }
    }

    private static func syntheticRevision(
        query: TripQuery,
        features: [TripMapFeature],
        generatedAt: Date
    ) -> String {
        let latestStart = features.first?.startTime.timeIntervalSince1970 ?? 0
        return "geojson|\(query.cacheKey)|\(features.count)|\(Int(latestStart))|\(Int(generatedAt.timeIntervalSince1970))"
    }
}
