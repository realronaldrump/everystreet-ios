import CoreLocation
import Foundation

enum TripGeometrySource: String, Codable, CaseIterable {
    case rawTripsOnly
}

struct TripQuery: Hashable {
    var dateRange: DateInterval
    var imei: String?
    var source: TripGeometrySource = .rawTripsOnly
    var coverageAreaID: String? = nil

    var isCoverageClipped: Bool {
        guard let coverageAreaID else { return false }
        return !coverageAreaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func withCoverageArea(id: String?) -> TripQuery {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        var copy = self
        copy.coverageAreaID = (trimmed?.isEmpty == false) ? trimmed : nil
        return copy
    }

    var cacheKey: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return [
            formatter.string(from: dateRange.start),
            formatter.string(from: dateRange.end),
            imei ?? "all",
            source.rawValue,
            coverageAreaID ?? "coverage:none"
        ].joined(separator: "|")
    }
}

enum SyncState: Equatable {
    case idle
    case syncing
    case stale(lastUpdated: Date?)
    case failed(message: String)
}

struct TripBoundingBox: Codable, Hashable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    init?(coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for point in coordinates {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        self.init(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    func intersects(_ other: TripBoundingBox) -> Bool {
        !(maxLon < other.minLon || other.maxLon < minLon || maxLat < other.minLat || other.maxLat < minLat)
    }

    func expanded(by factor: Double) -> TripBoundingBox {
        let latDelta = (maxLat - minLat) * factor
        let lonDelta = (maxLon - minLon) * factor
        return TripBoundingBox(
            minLat: minLat - latDelta,
            maxLat: maxLat + latDelta,
            minLon: minLon - lonDelta,
            maxLon: maxLon + lonDelta
        )
    }
}

struct MapBoundingBox: Hashable, Codable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    init?(array: [Double]) {
        guard array.count >= 4 else { return nil }
        self.init(minLon: array[0], minLat: array[1], maxLon: array[2], maxLat: array[3])
    }

    var asTripBoundingBox: TripBoundingBox {
        TripBoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    var asArray: [Double] {
        [minLon, minLat, maxLon, maxLat]
    }
}

enum GeometryDetailLevel: String, Codable, CaseIterable {
    case full
    case medium
    case low
}

struct EncodedGeometryLOD: Hashable, Codable {
    let full: String
    let medium: String
    let low: String

    func encodedPath(for level: GeometryDetailLevel) -> String {
        switch level {
        case .full:
            return full
        case .medium:
            return medium.isEmpty ? full : medium
        case .low:
            if !low.isEmpty { return low }
            return medium.isEmpty ? full : medium
        }
    }
}

struct TripMapFeature: Identifiable, Hashable {
    let id: String
    let startTime: Date
    let endTime: Date?
    let imei: String
    let distanceMiles: Double?
    let startLocation: String?
    let destination: String?
    let bbox: MapBoundingBox
    let geom: EncodedGeometryLOD
}

struct TripMapBundle: Hashable {
    let revision: String
    let generatedAt: Date
    let bbox: MapBoundingBox
    let tripCount: Int
    let trips: [TripMapFeature]
}

struct TripSummary: Identifiable {
    var id: String { transactionId }

    let transactionId: String
    let imei: String
    let vin: String?
    let vehicleLabel: String?
    let startTime: Date
    let endTime: Date?
    let distance: Double?
    let duration: Double?
    let maxSpeed: Double?
    let totalIdleDuration: Double?
    let fuelConsumed: Double?
    let estimatedCost: Double?
    let startLocation: String?
    let destination: String?
    let status: String?
    let previewPath: String?
    let boundingBox: TripBoundingBox?
    let fullGeometry: [CLLocationCoordinate2D]
    let mediumGeometry: [CLLocationCoordinate2D]
    let lowGeometry: [CLLocationCoordinate2D]

    func geometry(for level: GeometryDetailLevel) -> [CLLocationCoordinate2D] {
        switch level {
        case .full:
            return fullGeometry
        case .medium:
            return mediumGeometry.isEmpty ? fullGeometry : mediumGeometry
        case .low:
            return lowGeometry.isEmpty ? mediumGeometry.isEmpty ? fullGeometry : mediumGeometry : lowGeometry
        }
    }
}

struct TripDetail: Identifiable {
    var id: String { transactionId }

    let transactionId: String
    let imei: String?
    let vin: String?
    let status: String?
    let matchStatus: String?
    let startTime: Date?
    let endTime: Date?
    let distance: Double?
    let duration: Double?
    let avgSpeed: Double?
    let maxSpeed: Double?
    let currentSpeed: Double?
    let totalIdleDuration: Double?
    let fuelConsumed: Double?
    let pointsRecorded: Int?
    let hardBrakingCounts: Int?
    let hardAccelerationCounts: Int?
    let startLocation: LocationDisplay?
    let destination: LocationDisplay?
    let startGeoPoint: CLLocationCoordinate2D?
    let destinationGeoPoint: CLLocationCoordinate2D?
    let rawGeometry: [CLLocationCoordinate2D]
}

struct LocationDisplay: Hashable, Codable {
    let formattedAddress: String?
    let latitude: Double?
    let longitude: Double?
}

struct Vehicle: Identifiable, Hashable, Codable {
    var id: String { imei }

    let imei: String
    let vin: String?
    let customName: String?
    let nickName: String?
    let make: String?
    let model: String?
    let year: Int?
    let isActive: Bool

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let nickName, !nickName.isEmpty { return nickName }
        if let make, let model {
            return "\(make.capitalized) \(model.capitalized)"
        }
        return imei
    }
}
