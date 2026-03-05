import CoreLocation
import Foundation

enum CoverageStreetStatus: String, CaseIterable, Identifiable {
    case driven
    case undriven
    case undriveable
    case unknown

    var id: String { rawValue }

    init(apiValue: String?) {
        switch apiValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "driven":
            self = .driven
        case "undriven":
            self = .undriven
        case "undriveable":
            self = .undriveable
        default:
            self = .unknown
        }
    }
}

enum CoverageStreetFilter: String, CaseIterable, Identifiable {
    case all
    case driven
    case undriven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .driven: "Driven"
        case .undriven: "Undriven"
        }
    }

    func matches(_ status: CoverageStreetStatus) -> Bool {
        switch self {
        case .all:
            true
        case .driven:
            status == .driven
        case .undriven:
            status == .undriven
        }
    }
}

struct CoverageArea: Identifiable, Hashable {
    let id: String
    let displayName: String
    let areaType: String
    let status: String
    let health: String?
    let totalLengthMiles: Double
    let driveableLengthMiles: Double
    let drivenLengthMiles: Double
    let coveragePercentage: Double
    let totalSegments: Int
    let drivenSegments: Int
    let createdAt: Date?
    let lastSynced: Date?
    let hasOptimalRoute: Bool

    var undrivenSegments: Int {
        max(totalSegments - drivenSegments, 0)
    }

    var undrivenLengthMiles: Double {
        max(driveableLengthMiles - drivenLengthMiles, 0)
    }
}

struct CoverageAreaDetail {
    let area: CoverageArea
    let boundingBox: TripBoundingBox?
    let hasOptimalRoute: Bool
}

struct CoverageStreetSegment: Identifiable {
    let id: String
    let status: CoverageStreetStatus
    let name: String?
    let coordinates: [CLLocationCoordinate2D]
}

struct CoverageStreetsSnapshot {
    let segments: [CoverageStreetSegment]
    let totalInViewport: Int
    let truncated: Bool
}
