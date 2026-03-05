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

                mapLegend
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.bottom, legendBottomInset)

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
                controlButton(icon: "arrow.clockwise", tint: AppTheme.accent, spinning: viewModel.isCurrentLayerLoading) {
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
        HStack(spacing: 6) {
            ForEach(MapLayerMode.allCases) { layer in
                let isSelected = viewModel.selectedLayer == layer
                Button {
                    Task {
                        await viewModel.setLayer(layer)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: layer == .trips ? "car.rear.waves.up" : "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text(layer.shortTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? Color.white : AppTheme.textSecondary)
                    .padding(.horizontal, AppTheme.spacingMD)
                    .padding(.vertical, AppTheme.spacingXS + 3)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? AppTheme.accent : Color.clear)
                    )
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.panelInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 0.8)
        )
    }

    private func controlButton(
        icon: String,
        tint: Color,
        spinning: Bool = false,
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
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: spinning
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

    private var syncIndicator: some View {
        let spec = syncBadgeSpec
        return HStack(spacing: 6) {
            Image(systemName: spec.icon)
                .font(.system(size: 10, weight: .bold))
                .symbolEffect(.pulse, isActive: spec.text == "SYNC")
            Text(spec.text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(spec.tint)
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS + 1)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(spec.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(spec.tint.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var syncBadgeSpec: (icon: String, text: String, tint: Color, background: Color) {
        switch appModel.syncState {
        case .syncing:
            return ("arrow.triangle.2.circlepath", "SYNC", AppTheme.accent, AppTheme.accentMuted)
        case .stale:
            return ("clock.fill", "CACHED", AppTheme.accentWarm, AppTheme.accentWarmMuted)
        case .failed:
            return ("exclamationmark.triangle.fill", "ERROR", AppTheme.error, AppTheme.error.opacity(0.2))
        case .idle:
            return ("checkmark.seal.fill", "LIVE", AppTheme.success, AppTheme.success.opacity(0.16))
        }
    }

    private var mapLegend: some View {
        Group {
            if viewModel.selectedLayer == .trips {
                tripLegend
            } else {
                coverageLegend
            }
        }
    }

    private var tripLegend: some View {
        HStack(spacing: AppTheme.spacingSM) {
            Text("Older")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.routeOld, AppTheme.routeRecent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 4)

            Text("Recent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingSM)
        .glassCard(padding: 0, cornerRadius: AppTheme.radiusMD)
    }

    private var coverageLegend: some View {
        HStack(spacing: AppTheme.spacingSM) {
            legendSwatch(label: "Driven", color: streetColor(for: .driven), width: 18)
            legendSwatch(label: "Undriven", color: streetColor(for: .undriven), width: 16)
            legendSwatch(label: "Undriveable", color: streetColor(for: .undriveable), width: 12, dashed: true)
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingSM)
        .glassCard(padding: 0, cornerRadius: AppTheme.radiusMD)
    }

    private func legendSwatch(label: String, color: Color, width: CGFloat, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            Group {
                if dashed {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .foregroundStyle(color)
                } else {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color)
                }
            }
            .frame(width: width, height: 3)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
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

            Text(tripMilestoneText)
                .font(.caption.weight(.medium))
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

                Text(coverageMilestoneText(for: area))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("Pick a coverage area in Filters to start your sweep.")
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

                    Text("\(area.displayName): keep targeting orange streets to push toward the next milestone.")
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
            return "Trip Command Deck"
        case .coverage:
            return "Coverage Command Deck"
        }
    }

    private var traySubtitle: String {
        switch viewModel.selectedLayer {
        case .trips:
            return "\(viewModel.visibleTrips.count) visible routes"
        case .coverage:
            return "\(viewModel.visibleCoverageSegments.count) visible streets"
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

    private var legendBottomInset: CGFloat {
        switch trayDetent {
        case .collapsed:
            return 92
        case .peek:
            return 190
        case .expanded:
            return 332
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
        }
    }

    private var layerSubheadline: String {
        switch viewModel.selectedLayer {
        case .trips:
            return "\(viewModel.visibleTrips.count) visible • \(todayTripsCount) today • \(String(format: "%.1f", milesThisWeek)) mi this week"
        case .coverage:
            return "\(viewModel.coverageTotalInViewport) segments in viewport"
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

    private var tripMilestoneText: String {
        if todayTripsCount >= 5 {
            return "High-output day. You logged \(todayTripsCount) drives today."
        }

        if milesThisWeek >= 120 {
            return "Strong week: \(String(format: "%.0f", milesThisWeek)) miles already logged."
        }

        if let visibleLongest = viewModel.visibleTrips.compactMap(\.distanceMiles).max() {
            return "Longest visible route is \(String(format: "%.1f", visibleLongest)) mi."
        }

        return "Pan into your frequent zones to keep uncovering patterns."
    }

    private func coverageMilestoneText(for area: CoverageArea) -> String {
        let nextGoal = [50.0, 60.0, 70.0, 80.0, 90.0].first(where: { $0 > area.coveragePercentage })

        guard let nextGoal else {
            return "\(area.displayName) is in elite territory. Keep maintenance passes tight."
        }

        let gapPercent = max(nextGoal - area.coveragePercentage, 0)
        let milesToGoal = area.driveableLengthMiles * (gapPercent / 100)
        return String(
            format: "%.1f mi to reach %.0f%% in %@.",
            milesToGoal,
            nextGoal,
            area.displayName
        )
    }

    private var filterSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacingXL) {
                        if viewModel.selectedLayer == .trips {
                            GlobalFilterBar(appModel: appModel, compact: false) {
                                Task {
                                    await viewModel.load(query: appModel.activeQuery, appModel: appModel)
                                }
                            }
                        }

                        if viewModel.selectedLayer == .coverage {
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
            return appModel.selectedIMEI != nil || appModel.selectedPreset != .sevenDays
        case .coverage:
            return viewModel.coverageFilter != .all
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
