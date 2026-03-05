import CoreLocation
import Foundation

enum JSONHelpers {
    static func date(from any: Any?) -> Date? {
        guard let raw = any as? String else { return nil }
        let primary = ISO8601DateFormatter()
        primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = primary.date(from: raw) {
            return parsed
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    static func string(from any: Any?) -> String? {
        if let value = any as? String, !value.isEmpty {
            return value
        }
        if let number = any as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func double(from any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }

    static func int(from any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String { return Int(value) }
        return nil
    }

    static func bool(from any: Any?) -> Bool? {
        if let value = any as? Bool { return value }
        if let value = any as? NSNumber { return value.boolValue }
        if let value = any as? String { return NSString(string: value).boolValue }
        return nil
    }

    static func coordinates(from geometry: Any?) -> [CLLocationCoordinate2D] {
        guard let dict = geometry as? [String: Any] else { return [] }
        guard let coordArray = dict["coordinates"] as? [Any] else { return [] }

        if let point = parsePoint(coordArray) {
            return [point]
        }

        var output: [CLLocationCoordinate2D] = []
        output.reserveCapacity(coordArray.count)

        for item in coordArray {
            guard let pair = item as? [Any], pair.count >= 2 else { continue }
            guard let lon = double(from: pair[0]), let lat = double(from: pair[1]) else { continue }
            output.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return output
    }

    static func parsePoint(_ coordinate: [Any]) -> CLLocationCoordinate2D? {
        guard coordinate.count >= 2 else { return nil }
        guard let lon = double(from: coordinate[0]), let lat = double(from: coordinate[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { JSONHelpers.string(from: self[key]) }
    func double(_ key: String) -> Double? { JSONHelpers.double(from: self[key]) }
    func int(_ key: String) -> Int? { JSONHelpers.int(from: self[key]) }
    func bool(_ key: String) -> Bool? { JSONHelpers.bool(from: self[key]) }
    func date(_ key: String) -> Date? { JSONHelpers.date(from: self[key]) }
}
