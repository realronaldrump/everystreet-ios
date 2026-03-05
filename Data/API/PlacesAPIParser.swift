import Foundation

enum PlacesAPIParser {
    static func parseVehicles(data: Data) throws -> [Vehicle] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.decodingFailed(context: "vehicles")
        }

        return array.compactMap { item in
            guard let imei = item.string("imei") else { return nil }
            return Vehicle(
                imei: imei,
                vin: item.string("vin"),
                customName: item.string("custom_name"),
                nickName: item.string("nickName"),
                make: item.string("make"),
                model: item.string("model"),
                year: item.int("year"),
                isActive: item.bool("is_active") ?? true
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func parseFirstTripDate(data: Data) throws -> Date? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "first-trip-date")
        }

        if let value = object.string("first_trip_date") {
            return JSONHelpers.date(from: value)
        }

        if let firstValue = object.values.first as? String {
            return JSONHelpers.date(from: firstValue)
        }

        return nil
    }

    static func parsePlaces(data: Data) throws -> [PlaceSummary] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.decodingFailed(context: "places")
        }

        return array.compactMap(parsePlaceSummary)
    }

    static func parsePlaceStatsList(data: Data) throws -> [PlaceSummary] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.decodingFailed(context: "places-statistics")
        }

        return array.compactMap(parsePlaceSummary)
    }

    static func parsePlaceStats(data: Data) throws -> PlaceSummary {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = parsePlaceSummary(object)
        else {
            throw APIError.decodingFailed(context: "place-stats")
        }
        return item
    }

    static func parsePlaceTrips(data: Data) throws -> PlaceTripsSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "place-trips")
        }

        let placeName = object.string("name") ?? "Place"
        let trips = (object["trips"] as? [[String: Any]] ?? []).map { item in
            PlaceTripSummary(
                id: item.string("id") ?? UUID().uuidString,
                transactionId: item.string("transactionId") ?? "",
                endTime: item.date("endTime"),
                departureTime: item.date("departureTime"),
                timeSpent: item.string("timeSpent"),
                timeSinceLastVisit: item.string("timeSinceLastVisit"),
                source: item.string("source"),
                distance: item.double("distance")
            )
        }

        return PlaceTripsSnapshot(placeName: placeName, trips: trips)
    }

    static func parseHealth(data: Data) throws -> ServiceHealthSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingFailed(context: "health")
        }

        let overall = object["overall"] as? [String: Any]
        let status = overall?.string("status") ?? "unknown"
        let message = overall?.string("message") ?? "No details"
        let updated = overall?.date("last_updated")

        return ServiceHealthSnapshot(
            isHealthy: status == "healthy",
            overallStatus: status,
            message: message,
            lastUpdated: updated
        )
    }

    private static func parsePlaceSummary(_ item: [String: Any]) -> PlaceSummary? {
        guard let id = item.string("id") else { return nil }
        return PlaceSummary(
            id: id,
            name: item.string("name") ?? "Unknown Place",
            totalVisits: item.int("totalVisits"),
            averageTimeSpent: item.string("averageTimeSpent"),
            firstVisit: item.date("firstVisit"),
            lastVisit: item.date("lastVisit"),
            averageTimeSinceLastVisit: item.string("averageTimeSinceLastVisit")
        )
    }
}
