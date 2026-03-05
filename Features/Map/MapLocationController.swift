import CoreLocation
import Foundation
import Observation

enum MapLocationControlState: Equatable {
    case ready
    case locating
    case needsPermission
    case blocked
}

enum MapLocationPrimaryActionResult {
    case centered(CLLocationCoordinate2D)
    case awaitingFix
    case openSettings
}

@MainActor
@Observable
final class MapLocationController: NSObject, @preconcurrency CLLocationManagerDelegate {
    var authorizationStatus: CLAuthorizationStatus
    var currentCoordinate: CLLocationCoordinate2D?
    var trackedPathSegments: [[CLLocationCoordinate2D]] = []
    var isTripRecording = true
    var locationRevision = 0
    var isResolvingLocation = false

    @ObservationIgnored
    private let manager: CLLocationManager
    @ObservationIgnored
    private var lastTrackedLocation: CLLocation?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        currentCoordinate = manager.location?.coordinate
        super.init()
        configure()
    }

    var canDisplayUserLocation: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    var controlState: MapLocationControlState {
        if canDisplayUserLocation {
            return currentCoordinate == nil || isResolvingLocation ? .locating : .ready
        }

        switch authorizationStatus {
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .blocked
        default:
            return .needsPermission
        }
    }

    var recordedPointCount: Int {
        trackedPathSegments.reduce(0) { $0 + $1.count }
    }

    var hasRecordedPath: Bool {
        trackedPathSegments.contains { $0.count > 1 }
    }

    func prepare() {
        syncAuthorizationStatus()
        if currentCoordinate == nil {
            currentCoordinate = manager.location?.coordinate
        }
    }

    func handlePrimaryAction() -> MapLocationPrimaryActionResult {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let currentCoordinate {
                return .centered(currentCoordinate)
            }

            isResolvingLocation = true
            manager.requestLocation()
            manager.startUpdatingLocation()
            return .awaitingFix
        case .notDetermined:
            isResolvingLocation = true
            manager.requestWhenInUseAuthorization()
            return .awaitingFix
        case .denied, .restricted:
            return .openSettings
        @unknown default:
            return .openSettings
        }
    }

    func toggleTripRecording() {
        isTripRecording.toggle()
        lastTrackedLocation = nil

        if isTripRecording, let liveLocation = manager.location {
            beginTrackedSegmentIfNeeded()
            appendTrackedLocation(liveLocation)
            currentCoordinate = liveLocation.coordinate
            locationRevision += 1
        }
    }

    func clearRecordedTrip() {
        resetTrackedPath()
        locationRevision += 1
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        syncAuthorizationStatus()

        if canDisplayUserLocation {
            isResolvingLocation = currentCoordinate == nil
            manager.startUpdatingLocation()
            manager.requestLocation()
        } else {
            isResolvingLocation = false
            resetTrackedPath()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            appendTrackedLocation(location)
        }

        guard let location = locations.last else { return }
        currentCoordinate = location.coordinate
        locationRevision += 1
        isResolvingLocation = false
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else {
            isResolvingLocation = false
            return
        }

        if clError.code != .locationUnknown {
            isResolvingLocation = false
        }
    }

    private func configure() {
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 4
        manager.pausesLocationUpdatesAutomatically = false

        if canDisplayUserLocation {
            manager.startUpdatingLocation()
        }
    }

    private func syncAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus

        if canDisplayUserLocation {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            resetTrackedPath()
        }
    }

    private func appendTrackedLocation(_ location: CLLocation) {
        guard canDisplayUserLocation, isTripRecording else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65 else { return }

        if let lastTrackedLocation, location.distance(from: lastTrackedLocation) < 3 {
            return
        }

        beginTrackedSegmentIfNeeded()
        trackedPathSegments[trackedPathSegments.index(before: trackedPathSegments.endIndex)].append(location.coordinate)
        lastTrackedLocation = location
    }

    private func resetTrackedPath() {
        trackedPathSegments = []
        lastTrackedLocation = nil
    }

    private func beginTrackedSegmentIfNeeded() {
        guard trackedPathSegments.last != nil else {
            trackedPathSegments = [[]]
            return
        }

        if trackedPathSegments[trackedPathSegments.index(before: trackedPathSegments.endIndex)].isEmpty {
            return
        }

        if lastTrackedLocation == nil {
            trackedPathSegments.append([])
        }
    }
}
