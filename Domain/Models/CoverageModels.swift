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
    case undriveable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .driven: "Driven"
        case .undriven: "Undriven"
        case .undriveable: "Undriveable"
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
        case .undriveable:
            status == .undriveable
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

enum CoverageMapStatusFilter: String, CaseIterable, Identifiable {
    case all
    case driven
    case undriven
    case undriveable

    var id: String { rawValue }

    var apiValue: String { rawValue }
}

struct CoverageMapAreaSummary: Hashable {
    let id: String
    let displayName: String
    let coveragePercentage: Double
    let totalSegments: Int
    let drivenSegments: Int
}

struct CoverageMapFeature: Identifiable, Hashable {
    let id: String
    let status: CoverageStreetStatus
    let name: String?
    let bbox: MapBoundingBox
    let geom: EncodedGeometryLOD
}

struct CoverageMapBundle: Hashable {
    let revision: String
    let generatedAt: Date
    let area: CoverageMapAreaSummary
    let bbox: MapBoundingBox
    let segmentCount: Int
    let segments: [CoverageMapFeature]
}

struct CoverageNavigationCoordinate: Hashable, Codable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CoverageNavigationSuggestionSet: Hashable {
    let areaID: String
    let areaDisplayName: String
    let generatedAt: Date
    let origin: CoverageNavigationCoordinate
    let suggestions: [CoverageNavigationTarget]
}

struct CoverageNavigationTarget: Identifiable, Hashable {
    let id: String
    let rank: Int
    let title: String
    let reason: String
    let destination: CoverageNavigationCoordinate
    let bbox: MapBoundingBox
    let segmentIDs: [String]
    let segmentDestinations: [String: CoverageNavigationCoordinate]
    let undrivenSegmentCount: Int
    let undrivenLengthMiles: Double
    let distanceFromOriginMiles: Double?
    let etaMinutes: Double?
    let score: Double?
}

struct CoverageNavigationProgress: Equatable {
    let matchedSegmentIDs: Set<String>
    let matchedSegmentCount: Int
    let remainingSegmentCount: Int
    let coveredLengthMiles: Double
    let totalLengthMiles: Double
    let completionRatio: Double
    let likelyComplete: Bool
    let trackingActive: Bool
    let hasRecordedPath: Bool

    static func placeholder(
        for target: CoverageNavigationTarget,
        trackingActive: Bool,
        hasRecordedPath: Bool,
        preserving current: CoverageNavigationProgress? = nil
    ) -> CoverageNavigationProgress {
        CoverageNavigationProgress(
            matchedSegmentIDs: current?.matchedSegmentIDs ?? [],
            matchedSegmentCount: current?.matchedSegmentCount ?? 0,
            remainingSegmentCount: current?.remainingSegmentCount ?? target.undrivenSegmentCount,
            coveredLengthMiles: current?.coveredLengthMiles ?? 0,
            totalLengthMiles: max(current?.totalLengthMiles ?? 0, target.undrivenLengthMiles),
            completionRatio: current?.completionRatio ?? 0,
            likelyComplete: current?.likelyComplete ?? false,
            trackingActive: trackingActive,
            hasRecordedPath: hasRecordedPath
        )
    }
}
