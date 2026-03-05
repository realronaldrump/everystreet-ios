import Foundation

enum AppAPIParser {
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
}
