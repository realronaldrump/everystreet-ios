import CoreLocation
import Foundation

struct CodableCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum CoordinateCoding {
    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> Data? {
        let mapped = coordinates.map(CodableCoordinate.init)
        return try? JSONEncoder().encode(mapped)
    }

    static func decode(_ data: Data?) -> [CLLocationCoordinate2D] {
        guard let data else { return [] }
        guard let decoded = try? JSONDecoder().decode([CodableCoordinate].self, from: data) else {
            return []
        }
        return decoded.map(\.clLocation)
    }
}

enum Polyline6 {
    private static let scale: Double = 1_000_000

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }

        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(max(encoded.count / 8, 2))

        let scalars = Array(encoded.unicodeScalars)
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < scalars.count {
            guard let latDelta = decodeDelta(scalars, index: &index),
                  let lonDelta = decodeDelta(scalars, index: &index)
            else {
                break
            }

            latitude += latDelta
            longitude += lonDelta

            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: Double(latitude) / scale,
                    longitude: Double(longitude) / scale
                )
            )
        }

        return coordinates
    }

    private static func decodeDelta(
        _ scalars: [UnicodeScalar],
        index: inout Int
    ) -> Int? {
        var shift = 0
        var result = 0

        while index < scalars.count {
            let byte = Int(scalars[index].value) - 63
            index += 1

            if byte < 0 { return nil }
            result |= (byte & 0x1F) << shift
            shift += 5

            if byte < 0x20 {
                let delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                return delta
            }
        }

        return nil
    }
}
