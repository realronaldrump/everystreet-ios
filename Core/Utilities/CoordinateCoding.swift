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
