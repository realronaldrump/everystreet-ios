import MapKit
import SwiftUI

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

struct OverlayMKMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let regionRevision: Int
    let overlayGroups: [OverlayRenderGroup]
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegionChange: onRegionChange)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll

        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        } else {
            mapView.mapType = .mutedStandard
        }

        mapView.setRegion(region, animated: false)
        context.coordinator.apply(groups: overlayGroups, to: mapView)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.apply(groups: overlayGroups, to: uiView)
        context.coordinator.apply(region: region, revision: regionRevision, to: uiView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let onRegionChange: (MKCoordinateRegion) -> Void
        private var styleByOverlayID: [ObjectIdentifier: OverlayLineStyle] = [:]
        private var lastRegionRevision = -1
        private var suppressRegionCallback = false

        init(onRegionChange: @escaping (MKCoordinateRegion) -> Void) {
            self.onRegionChange = onRegionChange
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            guard !suppressRegionCallback else { return }
            onRegionChange(mapView.region)
        }
    }
}

struct MapTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: MapTabViewModel
    @State private var showFilterSheet = false
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
    }

    var body: some View {
        ZStack {
            OverlayMKMapView(
                region: viewModel.cameraRegion,
                regionRevision: viewModel.cameraRevision,
                overlayGroups: viewModel.activeOverlayGroups,
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

                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                commandTray
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.allTrips.isEmpty {
                await viewModel.load(query: appModel.activeQuery, appModel: appModel)
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
                trayExpandedContent
                    .padding(.horizontal, AppTheme.spacingMD)
                    .padding(.bottom, AppTheme.spacingMD)
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

                Text(coverageSummaryText(for: area))
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
                    HStack(spacing: AppTheme.spacingSM) {
                        metricChip(title: "Viewport", value: "\(viewModel.coverageTotalInViewport)", color: AppTheme.accent)
                        metricChip(title: "Remaining mi", value: String(format: "%.1f", area.undrivenLengthMiles), color: streetColor(for: .undriven))
                        metricChip(title: "Total mi", value: String(format: "%.1f", area.driveableLengthMiles), color: AppTheme.textSecondary)
                    }

                    Text(nextCoverageGoalLabel(for: area))
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
            return "\(viewModel.visibleTrips.count) trips • \(viewModel.coverageTotalInViewport) segments • street layer: \(viewModel.coverageFilter.title)"
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

    private func coverageSummaryText(for area: CoverageArea) -> String {
        let nextGoal = nextCoverageGoal(for: area.coveragePercentage)
        let milesToGoal = milesToCoverageGoal(area: area, target: nextGoal)
        return String(
            format: "Coverage: %.1f%% • Next goal: %.0f%% • Remaining: %.1f mi",
            area.coveragePercentage,
            nextGoal,
            milesToGoal
        )
    }

    private func nextCoverageGoalLabel(for area: CoverageArea) -> String {
        let nextGoal = nextCoverageGoal(for: area.coveragePercentage)
        let milesToGoal = milesToCoverageGoal(area: area, target: nextGoal)
        return String(format: "Next goal %.0f%% • %.1f mi remaining", nextGoal, milesToGoal)
    }

    private func nextCoverageGoal(for percent: Double) -> Double {
        [50.0, 60.0, 70.0, 80.0, 90.0, 95.0, 100.0].first(where: { $0 > percent }) ?? 100
    }

    private func milesToCoverageGoal(area: CoverageArea, target: Double) -> Double {
        let gapPercent = max(target - area.coveragePercentage, 0)
        return area.driveableLengthMiles * (gapPercent / 100)
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

    private var hasActiveFilters: Bool {
        switch viewModel.selectedLayer {
        case .trips:
            return appModel.selectedPreset != .sevenDays
        case .coverage:
            return viewModel.coverageFilter != .all
        case .combined:
            let tripFilters = appModel.selectedPreset != .sevenDays
            return tripFilters || viewModel.coverageFilter != .all
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
