import MapKit
import SwiftUI
import UIKit

private enum MapTrayDetent: Int {
    case collapsed = 0
    case peek = 1
    case expanded = 2

    func nextUp() -> MapTrayDetent {
        MapTrayDetent(rawValue: min(rawValue + 1, MapTrayDetent.expanded.rawValue)) ?? self
    }

    func nextDown() -> MapTrayDetent {
        MapTrayDetent(rawValue: max(rawValue - 1, MapTrayDetent.collapsed.rawValue)) ?? self
    }

    var chevron: String {
        switch self {
        case .collapsed, .peek:
            return "chevron.up"
        case .expanded:
            return "chevron.down"
        }
    }
}

struct MapAnnotationItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String?
    let glyphSystemName: String
    let tintColor: UIColor
}

struct OverlayMKMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let regionRevision: Int
    let showsUserLocation: Bool
    let overlayGroups: [OverlayRenderGroup]
    let annotationItems: [MapAnnotationItem]
    let selectableSegments: [MapSelectableCoverageSegment]
    let onSelectableSegmentTap: (MapSelectableCoverageSegment) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegionChange: onRegionChange,
            onSelectableSegmentTap: onSelectableSegmentTap
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = showsUserLocation

        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        } else {
            mapView.mapType = .mutedStandard
        }

        mapView.setRegion(region, animated: false)
        context.coordinator.apply(groups: overlayGroups, to: mapView)
        context.coordinator.apply(annotationItems: annotationItems, to: mapView)
        context.coordinator.selectableSegments = selectableSegments
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapRecognizer)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.showsUserLocation != showsUserLocation {
            uiView.showsUserLocation = showsUserLocation
        }

        context.coordinator.apply(groups: overlayGroups, to: uiView)
        context.coordinator.apply(annotationItems: annotationItems, to: uiView)
        context.coordinator.selectableSegments = selectableSegments
        context.coordinator.apply(region: region, revision: regionRevision, to: uiView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private final class StyledPointAnnotation: NSObject, MKAnnotation {
            let id: String
            let titleText: String
            let subtitleText: String?
            let glyphSystemName: String
            let tintColor: UIColor
            dynamic var coordinate: CLLocationCoordinate2D

            init(item: MapAnnotationItem) {
                id = item.id
                titleText = item.title
                subtitleText = item.subtitle
                glyphSystemName = item.glyphSystemName
                tintColor = item.tintColor
                coordinate = item.coordinate
            }

            var title: String? { titleText }
            var subtitle: String? { subtitleText }
        }

        private let onRegionChange: (MKCoordinateRegion) -> Void
        private let onSelectableSegmentTap: (MapSelectableCoverageSegment) -> Void
        private var styleByOverlayID: [ObjectIdentifier: OverlayLineStyle] = [:]
        private var lastRegionRevision = -1
        private var suppressRegionCallback = false
        fileprivate var selectableSegments: [MapSelectableCoverageSegment] = []

        init(
            onRegionChange: @escaping (MKCoordinateRegion) -> Void,
            onSelectableSegmentTap: @escaping (MapSelectableCoverageSegment) -> Void
        ) {
            self.onRegionChange = onRegionChange
            self.onSelectableSegmentTap = onSelectableSegmentTap
        }

        func apply(groups: [OverlayRenderGroup], to mapView: MKMapView) {
            if !mapView.overlays.isEmpty {
                mapView.removeOverlays(mapView.overlays)
            }

            styleByOverlayID.removeAll(keepingCapacity: true)
            for group in groups {
                let id = ObjectIdentifier(group.overlay)
                styleByOverlayID[id] = group.style
                mapView.addOverlay(group.overlay)
            }
        }

        func apply(annotationItems: [MapAnnotationItem], to mapView: MKMapView) {
            let existing = mapView.annotations.compactMap { $0 as? StyledPointAnnotation }
            if !existing.isEmpty {
                mapView.removeAnnotations(existing)
            }

            let annotations = annotationItems.map(StyledPointAnnotation.init(item:))
            if !annotations.isEmpty {
                mapView.addAnnotations(annotations)
            }
        }

        func apply(region: MKCoordinateRegion, revision: Int, to mapView: MKMapView) {
            guard revision != lastRegionRevision else { return }
            lastRegionRevision = revision
            suppressRegionCallback = true
            mapView.setRegion(region, animated: false)
            suppressRegionCallback = false
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let multi = overlay as? MKMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
                if let style = styleByOverlayID[ObjectIdentifier(multi)] {
                    renderer.strokeColor = style.color.withAlphaComponent(style.alpha)
                    renderer.lineWidth = style.lineWidth
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    renderer.lineDashPattern = style.dashPattern
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            guard let annotation = annotation as? StyledPointAnnotation else { return nil }

            let identifier = "navigation-marker"
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = annotation.tintColor
            view.glyphImage = UIImage(systemName: annotation.glyphSystemName)
            view.canShowCallout = false
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            guard !suppressRegionCallback else { return }
            onRegionChange(mapView.region)
        }

        @objc
        func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            guard let matchedSegment = nearestSelectableSegment(to: point, in: mapView) else { return }
            onSelectableSegmentTap(matchedSegment)
        }

        private func nearestSelectableSegment(
            to point: CGPoint,
            in mapView: MKMapView
        ) -> MapSelectableCoverageSegment? {
            let tolerance: CGFloat = 22

            var bestMatch: (segment: MapSelectableCoverageSegment, distance: CGFloat)?
            for segment in selectableSegments {
                let screenPoints = segment.coordinates.map { coordinate in
                    mapView.convert(coordinate, toPointTo: mapView)
                }

                let distance = polylineDistance(from: point, to: screenPoints)
                guard distance <= tolerance else { continue }

                if let currentBest = bestMatch {
                    if distance < currentBest.distance {
                        bestMatch = (segment, distance)
                    }
                } else {
                    bestMatch = (segment, distance)
                }
            }

            return bestMatch?.segment
        }

        private func polylineDistance(
            from point: CGPoint,
            to polyline: [CGPoint]
        ) -> CGFloat {
            guard let first = polyline.first else { return .greatestFiniteMagnitude }
            guard polyline.count > 1 else { return pointDistance(point, first) }

            return zip(polyline, polyline.dropFirst()).reduce(.greatestFiniteMagnitude) { current, pair in
                min(current, pointToSegmentDistance(point, pair.0, pair.1))
            }
        }

        private func pointToSegmentDistance(
            _ point: CGPoint,
            _ segmentStart: CGPoint,
            _ segmentEnd: CGPoint
        ) -> CGFloat {
            let dx = segmentEnd.x - segmentStart.x
            let dy = segmentEnd.y - segmentStart.y

            guard dx != 0 || dy != 0 else {
                return pointDistance(point, segmentStart)
            }

            let projection = ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / ((dx * dx) + (dy * dy))
            let clamped = min(1, max(0, projection))
            let projected = CGPoint(
                x: segmentStart.x + clamped * dx,
                y: segmentStart.y + clamped * dy
            )
            return pointDistance(point, projected)
        }

        private func pointDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            let dx = lhs.x - rhs.x
            let dy = lhs.y - rhs.y
            return sqrt((dx * dx) + (dy * dy))
        }
    }
}

struct MapTabView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var appModel: AppModel
    @State private var viewModel: MapTabViewModel
    @State private var locationController = MapLocationController()
    @State private var navigationController: CoverageNavigationController
    @State private var showFilterSheet = false
    @State private var shouldCenterOnNextLocationFix = false
    @State private var trayDetent: MapTrayDetent = .peek

    private let repository: TripsRepository

    init(
        appModel: AppModel,
        repository: TripsRepository,
        coverageRepository: CoverageRepository,
        coordinateCache: LRUCoordinateCache
    ) {
        _appModel = Bindable(appModel)
        self.repository = repository
        _viewModel = State(
            initialValue: MapTabViewModel(
                repository: repository,
                coverageRepository: coverageRepository,
                coordinateCache: coordinateCache
            )
        )
        _navigationController = State(
            initialValue: CoverageNavigationController(repository: coverageRepository)
        )
    }

    var body: some View {
        ZStack {
            OverlayMKMapView(
                region: viewModel.cameraRegion,
                regionRevision: viewModel.cameraRevision,
                showsUserLocation: locationController.canDisplayUserLocation,
                overlayGroups: mapOverlayGroups,
                annotationItems: navigationAnnotationItems,
                selectableSegments: selectableUndrivenSegments,
                onSelectableSegmentTap: { segment in
                    handleUndrivenSegmentTap(segment)
                },
                onRegionChange: { viewModel.update(region: $0) }
            )
            .ignoresSafeArea()

            if viewModel.isCurrentLayerLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.surfacePanel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.panelBorder, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.32), radius: 10, x: 0, y: 5)
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.top, AppTheme.spacingXS)

                if let error = viewModel.currentLayerErrorMessage {
                    errorBanner(error)
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, AppTheme.spacingSM)
                }

                if navigationHelperVisible, let navigationError = navigationController.errorMessage {
                    errorBanner(navigationError)
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, AppTheme.spacingSM)
                }

                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                commandTray
            }

            VStack(spacing: 0) {
                Spacer()

                HStack {
                    Spacer()
                    mapActionStack
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, trayHeight + AppTheme.spacingLG)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            locationController.prepare()
            navigationController.syncContext(
                selectedLayer: viewModel.selectedLayer,
                areaID: viewModel.selectedCoverageAreaID
            )

            if viewModel.allTrips.isEmpty {
                await viewModel.load(query: appModel.activeQuery, appModel: appModel)
            }

            updateNavigationProgress()
        }
        .onChange(of: locationController.locationRevision) { _, _ in
            centerOnDeferredLocationIfNeeded()
            updateNavigationProgress()
        }
        .onChange(of: locationController.isTripRecording) { _, _ in
            updateNavigationProgress()
        }
        .onChange(of: viewModel.selectedLayer) { _, newValue in
            navigationController.syncContext(
                selectedLayer: newValue,
                areaID: viewModel.selectedCoverageAreaID
            )
            updateNavigationProgress()
        }
        .onChange(of: viewModel.selectedCoverageAreaID) { _, newValue in
            navigationController.syncContext(
                selectedLayer: viewModel.selectedLayer,
                areaID: newValue
            )
            updateNavigationProgress()
        }
        .onChange(of: viewModel.coverageFeatures) { _, _ in
            updateNavigationProgress()
        }
        .onChange(of: navigationController.activeTargetID) { _, _ in
            focusOnActiveNavigationTarget()
            updateNavigationProgress()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await refreshNavigationSuggestionsIfNeeded()
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: AppTheme.spacingSM) {
                layerModeSwitch
                Spacer(minLength: 0)
                syncIndicator
                controlButton(icon: "line.3.horizontal.decrease", tint: hasActiveFilters ? AppTheme.accent : AppTheme.textSecondary, badge: hasActiveFilters) {
                    showFilterSheet = true
                }
                controlButton(icon: "arrow.clockwise", tint: AppTheme.accent) {
                    Task {
                        await viewModel.refreshCurrentLayer(query: appModel.activeQuery, appModel: appModel)
                        if navigationHelperVisible,
                           navigationController.hasSuggestions,
                           let areaID = viewModel.selectedCoverageAreaID
                        {
                            await fetchNavigationSuggestions(areaID: areaID, preserveActiveSelection: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(layerHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(layerSubheadline)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingMD)
        .glassCard(padding: 0, cornerRadius: AppTheme.radiusXL)
    }

    private var layerModeSwitch: some View {
        HStack(spacing: 8) {
            layerToggleButton(
                title: "TRIPS",
                icon: "car.rear.waves.up",
                isOn: tripsLayerEnabled
            ) {
                setLayerSelection(tripsEnabled: !tripsLayerEnabled, streetsEnabled: streetsLayerEnabled)
            }

            layerToggleButton(
                title: "STREETS",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                isOn: streetsLayerEnabled
            ) {
                setLayerSelection(tripsEnabled: tripsLayerEnabled, streetsEnabled: !streetsLayerEnabled)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private var tripsLayerEnabled: Bool {
        viewModel.selectedLayer != .coverage
    }

    private var streetsLayerEnabled: Bool {
        viewModel.selectedLayer != .trips
    }

    private func setLayerSelection(tripsEnabled: Bool, streetsEnabled: Bool) {
        guard let targetLayer = layerMode(forTripsEnabled: tripsEnabled, streetsEnabled: streetsEnabled) else {
            return
        }

        Task {
            await viewModel.setLayer(targetLayer)
        }
    }

    private func layerMode(forTripsEnabled tripsEnabled: Bool, streetsEnabled: Bool) -> MapLayerMode? {
        switch (tripsEnabled, streetsEnabled) {
        case (true, false):
            return .trips
        case (false, true):
            return .coverage
        case (true, true):
            return .combined
        case (false, false):
            return nil
        }
    }

    private func layerToggleButton(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AppTypography.captionHeavy)
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? AppTheme.accent : AppTheme.surfacePanelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isOn ? AppTheme.accent.opacity(0.95) : AppTheme.panelBorderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }

    private func controlButton(
        icon: String,
        tint: Color,
        badge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.panelInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 0.8)
                )
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(.pressable)
    }

    private var mapOverlayGroups: [OverlayRenderGroup] {
        var groups = viewModel.activeOverlayGroups
        if let liveTripOverlayGroup {
            groups.append(liveTripOverlayGroup)
        }
        groups.append(
            contentsOf: viewModel.navigationOverlayGroups(
                suggestions: navigationController.suggestions,
                activeTargetID: navigationController.activeTargetID
            )
        )
        return groups
    }

    private var liveTripOverlayGroup: OverlayRenderGroup? {
        let visibleSegments = trackedTripSegments
        guard !visibleSegments.isEmpty else { return nil }

        let polylines = visibleSegments.map { coordinates in
            MKPolyline(coordinates: coordinates, count: coordinates.count)
        }

        return OverlayRenderGroup(
            id: "live-trip-\(locationController.locationRevision)-\(polylines.count)",
            overlay: MKMultiPolyline(polylines),
            style: OverlayLineStyle(
                color: UIColor(AppTheme.routeRecent),
                lineWidth: 4.8,
                alpha: 0.96
            ),
            semantic: .liveTrip
        )
    }

    private var trackedTripSegments: [[CLLocationCoordinate2D]] {
        locationController.trackedPathSegments.filter { $0.count > 1 }
    }

    private var navigationAnnotationItems: [MapAnnotationItem] {
        guard navigationHelperVisible, let activeTarget = navigationController.activeTarget else { return [] }

        return [
            MapAnnotationItem(
                id: "navigation-target-\(activeTarget.id)",
                coordinate: activeTarget.destination.clLocationCoordinate2D,
                title: activeTarget.title,
                subtitle: activeTarget.reason,
                glyphSystemName: "flag.checkered",
                tintColor: UIColor(AppTheme.accentWarm)
            ),
        ]
    }

    private var selectableUndrivenSegments: [MapSelectableCoverageSegment] {
        guard viewModel.selectedLayer != .trips else { return [] }
        return viewModel.selectableUndrivenSegments()
    }

    private var navigationHelperVisible: Bool {
        viewModel.selectedLayer != .trips &&
            viewModel.selectedCoverageArea != nil &&
            locationController.canDisplayUserLocation
    }

    private var navigationPrimaryTitle: String {
        if navigationController.activeTarget == nil {
            return navigationCurrentCoordinate == nil ? "Waiting for GPS" : "Find Target"
        }

        return navigationController.isLikelyComplete ? "Next Cluster" : "Navigate"
    }

    private var navigationPrimaryIcon: String {
        if navigationController.isLoading {
            return "arrow.triangle.2.circlepath"
        }
        if navigationController.activeTarget == nil {
            return "scope"
        }
        return navigationController.isLikelyComplete ? "point.3.connected.trianglepath.dotted" : "arrow.turn.up.right"
    }

    private var navigationPrimaryTint: Color {
        if navigationController.activeTarget == nil {
            return AppTheme.accent
        }
        return navigationController.isLikelyComplete ? AppTheme.success : AppTheme.accentWarm
    }

    private var navigationCurrentCoordinate: CLLocationCoordinate2D? {
        locationController.currentCoordinate
    }

    private var navigationPrimaryDisabled: Bool {
        if navigationController.isLoading {
            return true
        }
        if navigationController.activeTarget == nil {
            return navigationCurrentCoordinate == nil
        }
        if navigationController.isLikelyComplete {
            return navigationCurrentCoordinate == nil
        }
        return false
    }

    private var mapActionStack: some View {
        VStack(alignment: .trailing, spacing: AppTheme.spacingSM) {
            if navigationHelperVisible {
                recordingControlButton(
                    title: navigationPrimaryTitle,
                    icon: navigationPrimaryIcon,
                    tint: navigationPrimaryTint,
                    action: {
                        Task {
                            await handleNavigationPrimaryAction()
                        }
                    }
                )
                .disabled(navigationPrimaryDisabled)
                .opacity(navigationPrimaryDisabled ? 0.55 : 1)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showTripRecordingControls {
                HStack(spacing: AppTheme.spacingXS) {
                    recordingControlButton(
                        title: locationController.isTripRecording ? "Recording" : "Paused",
                        icon: locationController.isTripRecording ? "record.circle.fill" : "pause.circle.fill",
                        tint: locationController.isTripRecording ? AppTheme.error : AppTheme.accentWarm,
                        action: {
                            locationController.toggleTripRecording()
                        }
                    )

                    if locationController.recordedPointCount > 0 {
                        recordingControlButton(
                            title: "Clear",
                            icon: "trash",
                            tint: AppTheme.textSecondary,
                            action: {
                                locationController.clearRecordedTrip()
                            }
                        )
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let locationStatusTitle, let locationStatusSubtitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text(locationStatusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(locationStatusSubtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingSM + 1)
                .frame(width: 204, alignment: .leading)
                .glassCard(tint: locationAccent, padding: 0, cornerRadius: AppTheme.radiusMD)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                handleLocationPrimaryAction()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.surfacePanelRaised, AppTheme.surfacePanel],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .stroke(locationAccent.opacity(0.52), lineWidth: 1)

                    Circle()
                        .inset(by: 8)
                        .fill(locationAccent.opacity(0.14))

                    if locationController.controlState == .locating {
                        Circle()
                            .stroke(locationAccent.opacity(0.22), lineWidth: 6)
                            .scaleEffect(1.08)
                    }

                    Image(systemName: locationSymbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(locationAccent)
                        .symbolEffect(.pulse, isActive: locationController.controlState == .locating)
                }
                .frame(width: 58, height: 58)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(locationStatusDot)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.surfacePanel, lineWidth: 2)
                        )
                }
                .shadow(color: Color.black.opacity(0.34), radius: 14, x: 0, y: 8)
                .shadow(color: locationAccent.opacity(0.18), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(locationAccessibilityLabel)
            .accessibilityHint(locationAccessibilityHint)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: locationController.controlState)
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: locationController.isTripRecording)
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: locationController.recordedPointCount)
    }

    private var showTripRecordingControls: Bool {
        locationController.canDisplayUserLocation || locationController.recordedPointCount > 0
    }

    private func recordingControlButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.spacingMD)
            .padding(.vertical, AppTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfacePanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 0.9)
            )
            .shadow(color: Color.black.opacity(0.26), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private var syncIndicator: some View {
        switch appModel.syncState {
        case .syncing:
            statusBadge(
                icon: "arrow.triangle.2.circlepath",
                text: "SYNC",
                tint: AppTheme.accent,
                background: AppTheme.accentMuted,
                pulse: true
            )
        case .stale:
            statusBadge(
                icon: "clock.fill",
                text: "CACHED",
                tint: AppTheme.accentWarm,
                background: AppTheme.accentWarmMuted
            )
        case .failed:
            statusBadge(
                icon: "exclamationmark.triangle.fill",
                text: "ERROR",
                tint: AppTheme.error,
                background: AppTheme.error.opacity(0.2)
            )
        case .idle:
            EmptyView()
        }
    }

    private func statusBadge(icon: String, text: String, tint: Color, background: Color, pulse: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .symbolEffect(.pulse, isActive: pulse)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS + 1)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var primaryStreetFilters: [CoverageStreetFilter] {
        [.all, .driven, .undriven]
    }

    private var streetLayerQuickFilter: some View {
        HStack(spacing: AppTheme.spacingSM) {
            ForEach(primaryStreetFilters) { filter in
                let active = viewModel.coverageFilter == filter
                Button {
                    viewModel.setCoverageFilter(filter)
                } label: {
                    Text(filter.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(active ? Color.white : AppTheme.textSecondary)
                        .padding(.horizontal, AppTheme.spacingSM)
                        .padding(.vertical, AppTheme.spacingXS + 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? AppTheme.accent : AppTheme.panelInset)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(active ? AppTheme.accent.opacity(0.7) : AppTheme.panelBorder, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var commandTray: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            Capsule()
                .fill(AppTheme.panelBorderStrong)
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.spacingSM)

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    trayDetent = trayDetent == .expanded ? .collapsed : trayDetent.nextUp()
                }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(traySubtitle)
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer()

                    Image(systemName: trayDetent.chevron)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppTheme.panelInset)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
                        )
                }
                .padding(.horizontal, AppTheme.spacingMD)
            }
            .buttonStyle(.plain)

            if trayDetent != .collapsed {
                trayQuickStats
                    .padding(.horizontal, AppTheme.spacingMD)
            }

            if trayDetent == .expanded {
                ScrollView(.vertical, showsIndicators: false) {
                    trayExpandedContent
                        .padding(.horizontal, AppTheme.spacingMD)
                        .padding(.bottom, AppTheme.spacingMD)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: trayHeight, alignment: .top)
        .background(trayBackground)
        .overlay(trayBorder)
        .gesture(trayGesture)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: trayDetent)
    }

    private var trayBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: AppTheme.radiusXL,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: AppTheme.radiusXL,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [AppTheme.surfacePanelRaised, AppTheme.surfacePanel],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: Color.black.opacity(0.34), radius: 18, x: 0, y: -6)
    }

    private var trayBorder: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: AppTheme.radiusXL,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: AppTheme.radiusXL,
            style: .continuous
        )
        .stroke(AppTheme.panelBorder, lineWidth: 0.9)
    }

    private var trayGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard abs(value.translation.height) > 30 else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    if value.translation.height < 0 {
                        trayDetent = trayDetent.nextUp()
                    } else {
                        trayDetent = trayDetent.nextDown()
                    }
                }
            }
    }

    @ViewBuilder
    private var trayQuickStats: some View {
        switch viewModel.selectedLayer {
        case .trips:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    trayStatTile(title: "Today", value: "\(todayTripsCount) drives", tint: AppTheme.accent)
                    trayStatTile(title: "This Week", value: String(format: "%.1f mi", milesThisWeek), tint: AppTheme.success)
                    trayStatTile(title: "Visible", value: "\(viewModel.visibleTrips.count)", tint: AppTheme.routeRecent)
                }
                .padding(.vertical, AppTheme.spacingXS)
            }

            Text(tripSummaryText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        case .coverage:
            if let area = viewModel.selectedCoverageArea {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        trayStatTile(title: "Coverage", value: String(format: "%.1f%%", area.coveragePercentage), tint: AppTheme.accent)
                        trayStatTile(title: "Driven", value: "\(viewModel.coverageCounts.driven)", tint: streetColor(for: .driven))
                        trayStatTile(title: "Undriven", value: "\(viewModel.coverageCounts.undriven)", tint: streetColor(for: .undriven))
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }

                Text(coverageStatusText(for: area))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("Select coverage area in Filters.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        case .combined:
            if let area = viewModel.selectedCoverageArea {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        trayStatTile(title: "Trips", value: "\(viewModel.visibleTrips.count)", tint: AppTheme.routeRecent)
                        trayStatTile(title: "Streets", value: "\(viewModel.coverageTotalInViewport)", tint: AppTheme.accent)
                        trayStatTile(title: "Coverage", value: String(format: "%.1f%%", area.coveragePercentage), tint: AppTheme.success)
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }

                streetLayerQuickFilter

                Text("Trips: \(viewModel.visibleTrips.count) • Streets: \(viewModel.coverageTotalInViewport)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("Select coverage area in Filters.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var trayExpandedContent: some View {
        switch viewModel.selectedLayer {
        case .trips:
            if viewModel.visibleTrips.isEmpty {
                Text("Move the map to surface trips in this viewport.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, AppTheme.spacingSM)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(viewModel.visibleTrips.prefix(24)) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.id, repository: repository)
                            } label: {
                                tripCard(trip)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }
            }
        case .coverage:
            if let area = viewModel.selectedCoverageArea {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    if navigationHelperVisible {
                        navigationHelperTray
                    }

                    HStack(spacing: AppTheme.spacingSM) {
                        metricChip(title: "Viewport", value: "\(viewModel.coverageTotalInViewport)", color: AppTheme.accent)
                        metricChip(title: "Remaining mi", value: String(format: "%.1f", area.undrivenLengthMiles), color: streetColor(for: .undriven))
                        metricChip(title: "Total mi", value: String(format: "%.1f", area.driveableLengthMiles), color: AppTheme.textSecondary)
                    }

                    Text(coverageDetailText(for: area))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, AppTheme.spacingXS)
            } else {
                Text("Open filters to choose a coverage area.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, AppTheme.spacingXS)
            }
        case .combined:
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                if navigationHelperVisible {
                    navigationHelperTray
                }

                if viewModel.visibleTrips.isEmpty {
                    Text("Move the map to surface trips over this street layer.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, AppTheme.spacingXS)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.spacingSM) {
                            ForEach(viewModel.visibleTrips.prefix(16)) { trip in
                                NavigationLink {
                                    TripDetailView(tripID: trip.id, repository: repository)
                                } label: {
                                    tripCard(trip)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .padding(.vertical, AppTheme.spacingXS)
                    }
                }

                if let area = viewModel.selectedCoverageArea {
                    HStack(spacing: AppTheme.spacingSM) {
                        metricChip(title: "Area", value: area.displayName, color: AppTheme.accent)
                        metricChip(title: "Driven", value: "\(viewModel.coverageCounts.driven)", color: streetColor(for: .driven))
                        metricChip(title: "Undriven", value: "\(viewModel.coverageCounts.undriven)", color: streetColor(for: .undriven))
                    }
                } else {
                    Text("Select coverage area in Filters.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.vertical, AppTheme.spacingXS)
        }
    }

    @ViewBuilder
    private var navigationHelperTray: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: AppTheme.spacingSM) {
                Text("NAVIGATION HELPER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .tracking(0.8)

                Spacer()

                if navigationController.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                }
            }

            if let error = navigationController.errorMessage {
                errorBanner(error)
            }

            if let activeTarget = navigationController.activeTarget {
                navigationActiveTargetCard(activeTarget)
            } else {
                navigationEmptyStateCard
            }

            if !navigationController.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(navigationController.suggestions) { target in
                            navigationSuggestionCard(target)
                        }
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }
            }

            if let activeTarget = navigationController.activeTarget,
               let progress = navigationController.progress
            {
                navigationProgressPanel(progress: progress, target: activeTarget)
            }
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    private var navigationEmptyStateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text(navigationCurrentCoordinate == nil ? "Waiting for a GPS fix." : "No target selected.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(
                navigationCurrentCoordinate == nil
                    ? "The helper will rank nearby undriven clusters once the phone has a current position."
                    : "Use Find Target to rank the best nearby undriven clusters in this coverage area."
            )
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private func navigationActiveTargetCard(_ target: CoverageNavigationTarget) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(alignment: .top, spacing: AppTheme.spacingSM) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(target.reason)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("#\(target.rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingSM)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.accentMuted)
                    )
            }

            HStack(spacing: AppTheme.spacingSM) {
                metricChip(
                    title: "ETA",
                    value: navigationDurationLabel(target.etaMinutes),
                    color: AppTheme.accentWarm
                )
                metricChip(
                    title: "Distance",
                    value: navigationDistanceLabel(target.distanceFromOriginMiles),
                    color: AppTheme.accent
                )
                metricChip(
                    title: "Segments",
                    value: "\(target.undrivenSegmentCount)",
                    color: streetColor(for: .undriven)
                )
            }

            HStack(spacing: AppTheme.spacingSM) {
                navigationActionButton(
                    title: "Navigate",
                    icon: "arrow.turn.up.right",
                    tint: AppTheme.accentWarm,
                    disabled: false
                ) {
                    _ = navigationController.launchNavigation()
                }

                navigationActionButton(
                    title: "Next Cluster",
                    icon: "point.3.connected.trianglepath.dotted",
                    tint: AppTheme.accent,
                    disabled: navigationCurrentCoordinate == nil
                ) {
                    Task {
                        await advanceToNextNavigationTarget()
                    }
                }
            }
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 0.8)
        )
    }

    private func navigationSuggestionCard(_ target: CoverageNavigationTarget) -> some View {
        let isActive = target.id == navigationController.activeTarget?.id

        return Button {
            navigationController.selectTarget(id: target.id)
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                HStack {
                    Text("#\(target.rank)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textTertiary)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Text(target.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text(target.reason)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                Text("\(navigationDistanceLabel(target.distanceFromOriginMiles)) • \(navigationDurationLabel(target.etaMinutes))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(width: 168, alignment: .leading)
            .padding(AppTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? AppTheme.accentMuted : AppTheme.panelInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isActive ? AppTheme.accent.opacity(0.7) : AppTheme.panelBorder, lineWidth: 0.8)
            )
        }
        .buttonStyle(.pressable)
    }

    private func navigationProgressPanel(
        progress: CoverageNavigationProgress,
        target: CoverageNavigationTarget
    ) -> some View {
        let totalSegmentCount = max(target.undrivenSegmentCount, progress.matchedSegmentCount + progress.remainingSegmentCount)

        return VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: AppTheme.spacingSM) {
                metricChip(
                    title: "Covered",
                    value: "\(progress.matchedSegmentCount)/\(max(totalSegmentCount, progress.matchedSegmentCount))",
                    color: AppTheme.success
                )
                metricChip(
                    title: "Local %",
                    value: String(format: "%.0f%%", progress.completionRatio * 100),
                    color: progress.likelyComplete ? AppTheme.success : AppTheme.accent
                )
                metricChip(
                    title: "Remain mi",
                    value: String(format: "%.1f", max(progress.totalLengthMiles - progress.coveredLengthMiles, 0)),
                    color: AppTheme.warning
                )
            }

            Text(navigationProgressMessage(progress: progress))
                .font(.caption)
                .foregroundStyle(progress.trackingActive ? AppTheme.textSecondary : AppTheme.accentWarm)
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(progress.likelyComplete ? AppTheme.success.opacity(0.35) : AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private func navigationActionButton(
        title: String,
        icon: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.spacingMD)
            .padding(.vertical, AppTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfacePanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 0.9)
            )
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private func trayStatTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var trayTitle: String {
        switch viewModel.selectedLayer {
        case .trips:
            return "Trips"
        case .coverage:
            return "Coverage"
        case .combined:
            return "Combined"
        }
    }

    private var traySubtitle: String {
        switch viewModel.selectedLayer {
        case .trips:
            return "\(viewModel.visibleTrips.count) visible routes"
        case .coverage:
            return "\(viewModel.visibleCoverageSegments.count) visible streets"
        case .combined:
            return "\(viewModel.visibleTrips.count) trips • \(viewModel.coverageTotalInViewport) streets"
        }
    }

    private var trayHeight: CGFloat {
        switch trayDetent {
        case .collapsed:
            return 84
        case .peek:
            return 182
        case .expanded:
            return 324
        }
    }

    private var layerHeadline: String {
        switch viewModel.selectedLayer {
        case .trips:
            if let lastTrip = viewModel.allTrips.first {
                return "Last drive: \(lastTrip.startTime.formatted(date: .abbreviated, time: .shortened))"
            }
            return "No trips loaded yet"
        case .coverage:
            if let area = viewModel.selectedCoverageArea {
                return "\(area.displayName) • \(String(format: "%.1f", area.coveragePercentage))% complete"
            }
            return "Select a coverage area"
        case .combined:
            if let area = viewModel.selectedCoverageArea {
                return "Trips over \(area.displayName)"
            }
            return "Trips + street network"
        }
    }

    private var layerSubheadline: String {
        switch viewModel.selectedLayer {
        case .trips:
            return "\(viewModel.visibleTrips.count) visible • \(todayTripsCount) today • \(String(format: "%.1f", milesThisWeek)) mi this week"
        case .coverage:
            return "\(viewModel.coverageTotalInViewport) segments in viewport"
        case .combined:
            let clipSuffix = viewModel.isTripCoverageClipActive ? " • trips clipped to area" : ""
            return "\(viewModel.visibleTrips.count) trips • \(viewModel.coverageTotalInViewport) segments • street layer: \(viewModel.coverageFilter.title)\(clipSuffix)"
        }
    }

    private var todayTripsCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return viewModel.allTrips.filter { $0.startTime >= startOfDay }.count
    }

    private var milesThisWeek: Double {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return viewModel.allTrips
            .filter { $0.startTime >= weekStart }
            .reduce(0) { $0 + ($1.distanceMiles ?? 0) }
    }

    private var tripSummaryText: String {
        let longestVisible = viewModel.visibleTrips.compactMap(\.distanceMiles).max() ?? 0
        return String(
            format: "Trips today: %d • Week miles: %.1f • Longest visible: %.1f mi",
            todayTripsCount,
            milesThisWeek,
            longestVisible
        )
    }

    private func coverageStatusText(for area: CoverageArea) -> String {
        String(
            format: "Coverage: %.1f%% • %d undriven segments • %.1f mi remaining",
            area.coveragePercentage,
            area.undrivenSegments,
            area.undrivenLengthMiles
        )
    }

    private func coverageDetailText(for area: CoverageArea) -> String {
        String(
            format: "Undriven streets: %d • Remaining driveable distance: %.1f mi",
            area.undrivenSegments,
            area.undrivenLengthMiles
        )
    }

    private var filterSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacingXL) {
                        if viewModel.selectedLayer == .trips || viewModel.selectedLayer == .combined {
                            GlobalFilterBar(appModel: appModel, compact: false) {
                                Task {
                                    await viewModel.load(query: appModel.activeQuery, appModel: appModel)
                                }
                            }
                        }

                        if viewModel.selectedLayer == .coverage || viewModel.selectedLayer == .combined {
                            coverageFilterControls
                        }
                    }
                    .padding(AppTheme.spacingLG)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilterSheet = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.surface)
    }

    private var coverageFilterControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            Text("COVERAGE AREA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .tracking(0.8)

            Menu {
                if viewModel.coverageAreas.isEmpty {
                    Text("No coverage areas available")
                } else {
                    ForEach(viewModel.coverageAreas) { area in
                        Button {
                            Task {
                                await viewModel.selectCoverageArea(area.id)
                            }
                        } label: {
                            if area.id == viewModel.selectedCoverageAreaID {
                                Label(area.displayName, systemImage: "checkmark")
                            } else {
                                Text(area.displayName)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(viewModel.selectedCoverageArea?.displayName ?? "Choose Area")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(AppTheme.spacingMD)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .fill(AppTheme.panelInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 0.8)
                )
            }

            if viewModel.selectedLayer == .combined {
                Text("Trip lines are clipped to this boundary in combined mode.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Text("STREET STATUS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .tracking(0.8)
                .padding(.top, AppTheme.spacingSM)

            HStack(spacing: AppTheme.spacingSM) {
                ForEach(CoverageStreetFilter.allCases) { filter in
                    let active = viewModel.coverageFilter == filter
                    Button {
                        viewModel.setCoverageFilter(filter)
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? Color.white : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingSM)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(active ? AppTheme.accent : AppTheme.panelInset)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(active ? AppTheme.accent.opacity(0.7) : AppTheme.panelBorder, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.pressable)
                }
            }

            HStack(spacing: AppTheme.spacingSM) {
                legendChip(label: "Driven", status: .driven)
                legendChip(label: "Undriven", status: .undriven)
                legendChip(label: "Undriveable", status: .undriveable)
            }
        }
        .glassCard(padding: AppTheme.spacingLG, cornerRadius: AppTheme.radiusLG)
    }

    private func tripCard(_ trip: TripMapFeature) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text(trip.startTime, style: .date)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            Text(distanceLabel(trip.distanceMiles))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)

            Text(destinationLabel(for: trip))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(width: 160, alignment: .leading)
        .padding(AppTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.accent)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
    }

    private func legendChip(label: String, status: CoverageStreetStatus) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Circle()
                .fill(streetColor(for: status))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private func metricChip(title: String, value: String, color: Color) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(AppTheme.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .stroke(AppTheme.warning.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var locationSymbol: String {
        switch locationController.controlState {
        case .ready:
            return "location.fill"
        case .locating:
            return "location.circle.fill"
        case .needsPermission:
            return "location.circle"
        case .blocked:
            return "location.slash.fill"
        }
    }

    private var locationAccent: Color {
        switch locationController.controlState {
        case .ready, .locating:
            return AppTheme.accent
        case .needsPermission:
            return AppTheme.accentWarm
        case .blocked:
            return AppTheme.error
        }
    }

    private var locationStatusDot: Color {
        if locationController.canDisplayUserLocation, !locationController.isTripRecording {
            return AppTheme.accentWarm
        }

        switch locationController.controlState {
        case .ready:
            return AppTheme.success
        case .locating:
            return AppTheme.accent
        case .needsPermission:
            return AppTheme.accentWarm
        case .blocked:
            return AppTheme.error
        }
    }

    private var locationStatusTitle: String? {
        if locationController.canDisplayUserLocation, !locationController.isTripRecording {
            return "Recording Paused"
        }

        switch locationController.controlState {
        case .ready:
            return nil
        case .locating:
            return "Finding Your Position"
        case .needsPermission:
            return "Add Your Position"
        case .blocked:
            return "Location Is Blocked"
        }
    }

    private var locationStatusSubtitle: String? {
        if locationController.canDisplayUserLocation, !locationController.isTripRecording {
            let points = locationController.recordedPointCount
            return points > 0
                ? "Current position still updates. Resume to keep extending the \(points)-point live trip line."
                : "Current position still updates. Resume when you want the live trip line to grow again."
        }

        switch locationController.controlState {
        case .ready:
            return nil
        case .locating:
            return "Pulling a fresh GPS fix so you can line up with the street grid."
        case .needsPermission:
            return "Allow location access to see yourself against covered and undriven streets."
        case .blocked:
            return "Open Settings to put your car back on the map."
        }
    }

    private var locationAccessibilityLabel: String {
        switch locationController.controlState {
        case .ready:
            return "Center map on current location"
        case .locating:
            return "Locating current position"
        case .needsPermission:
            return "Enable current location on map"
        case .blocked:
            return "Open settings for location access"
        }
    }

    private var locationAccessibilityHint: String {
        switch locationController.controlState {
        case .ready:
            return "Centers the map on your current street."
        case .locating:
            return "Wait for a GPS fix to center the map."
        case .needsPermission:
            return "Requests location access."
        case .blocked:
            return "Opens the app settings screen."
        }
    }

    private func handleLocationPrimaryAction() {
        switch locationController.handlePrimaryAction() {
        case let .centered(coordinate):
            shouldCenterOnNextLocationFix = false
            viewModel.focus(on: coordinate)
        case .awaitingFix:
            shouldCenterOnNextLocationFix = true
        case .openSettings:
            shouldCenterOnNextLocationFix = false
            openAppSettings()
        }
    }

    private func centerOnDeferredLocationIfNeeded() {
        guard shouldCenterOnNextLocationFix, let coordinate = locationController.currentCoordinate else { return }
        shouldCenterOnNextLocationFix = false
        viewModel.focus(on: coordinate)
    }

    private func handleNavigationPrimaryAction() async {
        guard let areaID = viewModel.selectedCoverageAreaID else { return }
        trayDetent = .expanded

        if navigationController.activeTarget == nil {
            await fetchNavigationSuggestions(areaID: areaID, preserveActiveSelection: false)
            return
        }

        if navigationController.isLikelyComplete {
            await advanceToNextNavigationTarget()
            return
        }

        _ = navigationController.launchNavigation()
    }

    private func fetchNavigationSuggestions(
        areaID: String,
        preserveActiveSelection: Bool
    ) async {
        guard let coordinate = navigationCurrentCoordinate else { return }
        trayDetent = .expanded
        await navigationController.loadSuggestions(
            areaID: areaID,
            origin: coordinate,
            preserveActiveSelection: preserveActiveSelection
        )
        updateNavigationProgress()
        focusOnActiveNavigationTarget()
    }

    private func advanceToNextNavigationTarget() async {
        guard let areaID = viewModel.selectedCoverageAreaID,
              let coordinate = navigationCurrentCoordinate
        else {
            return
        }

        trayDetent = .expanded
        await navigationController.advanceToNextTarget(areaID: areaID, origin: coordinate)
        updateNavigationProgress()
        focusOnActiveNavigationTarget()
    }

    private func refreshNavigationSuggestionsIfNeeded() async {
        guard navigationHelperVisible,
              let areaID = viewModel.selectedCoverageAreaID,
              let coordinate = navigationCurrentCoordinate
        else {
            return
        }

        await navigationController.refreshIfNeededOnReturn(areaID: areaID, origin: coordinate)
        updateNavigationProgress()
        focusOnActiveNavigationTarget()
    }

    private func updateNavigationProgress() {
        navigationController.updateProgress(
            coverageFeatures: viewModel.coverageFeatures,
            trackedPathSegments: locationController.trackedPathSegments,
            isTripRecording: locationController.isTripRecording
        )
    }

    private func handleUndrivenSegmentTap(_ segment: MapSelectableCoverageSegment) {
        trayDetent = .expanded
        _ = navigationController.launchNavigation(to: segment)
    }

    private func focusOnActiveNavigationTarget() {
        guard let activeTarget = navigationController.activeTarget else { return }
        viewModel.focus(on: activeTarget.bbox, including: navigationCurrentCoordinate)
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private var hasActiveFilters: Bool {
        switch viewModel.selectedLayer {
        case .trips:
            return appModel.selectedPreset != .sevenDays
        case .coverage:
            return viewModel.coverageFilter != .all
        case .combined:
            let tripFilters = appModel.selectedPreset != .sevenDays
            return tripFilters || viewModel.coverageFilter != .all || viewModel.isTripCoverageClipActive
        }
    }

    private func streetColor(for status: CoverageStreetStatus) -> Color {
        switch status {
        case .driven:
            return AppTheme.success
        case .undriven:
            return AppTheme.warning
        case .undriveable:
            return AppTheme.textTertiary
        case .unknown:
            return AppTheme.accent
        }
    }

    private func distanceLabel(_ distance: Double?) -> String {
        guard let distance else { return "-- mi" }
        return String(format: "%.1f mi", distance)
    }

    private func navigationDistanceLabel(_ distance: Double?) -> String {
        guard let distance else { return "-- mi" }
        return String(format: "%.1f mi", distance)
    }

    private func navigationDurationLabel(_ etaMinutes: Double?) -> String {
        guard let etaMinutes else { return "-- min" }
        return "\(Int(etaMinutes.rounded())) min"
    }

    private func navigationProgressMessage(progress: CoverageNavigationProgress) -> String {
        if !progress.trackingActive {
            return progress.hasRecordedPath
                ? "Local progress is paused until trip recording resumes."
                : "Drive with trip recording on to estimate when this cluster is likely complete."
        }

        if progress.likelyComplete {
            return "This cluster looks mostly covered from the local path. Use Next Cluster to rotate to the next ranked target."
        }

        return "Local overlap has covered \(progress.matchedSegmentCount) segments so far. Apple Maps still handles the actual turn-by-turn leg."
    }

    private func destinationLabel(for trip: TripMapFeature) -> String {
        if let destination = trip.destination, !destination.isEmpty {
            return destination
        }
        if let startLocation = trip.startLocation, !startLocation.isEmpty {
            return startLocation
        }
        return "Trip \(trip.id.prefix(8))"
    }
}
