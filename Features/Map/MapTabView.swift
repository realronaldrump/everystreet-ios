import MapKit
import SwiftUI

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
    @State private var showBottomTray = true

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
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
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

                Group {
                    if viewModel.selectedLayer == .trips {
                        tripsBottomTray
                    } else {
                        coverageBottomTray
                    }
                }
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
        HStack(spacing: AppTheme.spacingSM) {
            Picker(
                "Layer",
                selection: Binding(
                    get: { viewModel.selectedLayer },
                    set: { newLayer in
                        Task {
                            await viewModel.setLayer(newLayer)
                        }
                    }
                )
            ) {
                ForEach(MapLayerMode.allCases) { layer in
                    Text(layer.shortTitle).tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            Spacer()

            syncIndicator

            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasActiveFilters ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .overlay(alignment: .topTrailing) {
                        if hasActiveFilters {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 7, height: 7)
                                .offset(x: 1, y: -1)
                        }
                    }
            }
            .buttonStyle(.pressable)

            Button {
                Task {
                    await viewModel.refreshCurrentLayer(query: appModel.activeQuery, appModel: appModel)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .rotationEffect(.degrees(viewModel.isCurrentLayerLoading ? 360 : 0))
                    .animation(
                        viewModel.isCurrentLayerLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isCurrentLayerLoading
                    )
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var syncIndicator: some View {
        switch appModel.syncState {
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse, isActive: true)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentMuted, in: Circle())
        case .stale:
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accentWarm)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentWarmMuted, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.error)
                .frame(width: 28, height: 28)
                .background(AppTheme.error.opacity(0.15), in: Circle())
        case .idle:
            EmptyView()
        }
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
        .presentationBackground(AppTheme.background)
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
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
            }

            Text("STREET STATUS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .tracking(0.8)
                .padding(.top, AppTheme.spacingSM)

            Picker(
                "Street Status",
                selection: Binding(
                    get: { viewModel.coverageFilter },
                    set: { viewModel.setCoverageFilter($0) }
                )
            ) {
                ForEach(CoverageStreetFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: AppTheme.spacingMD) {
                legendChip(label: "Driven", status: .driven)
                legendChip(label: "Undriven", status: .undriven)
                legendChip(label: "Undriveable", status: .undriveable)
            }
        }
        .glassCard(padding: AppTheme.spacingLG, cornerRadius: AppTheme.radiusLG)
    }

    private var tripsBottomTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showBottomTray.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Text("\(viewModel.visibleTrips.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 22)
                        .padding(.horizontal, AppTheme.spacingXS)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentMuted, in: Capsule())

                    Text("Visible Trips")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Image(systemName: showBottomTray ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingSM)
            }
            .buttonStyle(.plain)

            if showBottomTray {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    if viewModel.visibleTrips.isEmpty {
                        Text("Move the map to see trips")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppTheme.spacingSM)
                            .padding(.horizontal, AppTheme.spacingMD)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacingSM) {
                                ForEach(viewModel.visibleTrips.prefix(20)) { trip in
                                    NavigationLink {
                                        TripDetailView(tripID: trip.id, repository: repository)
                                    } label: {
                                        tripCard(trip)
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                            .padding(.horizontal, AppTheme.spacingMD)
                            .padding(.bottom, AppTheme.spacingSM)
                        }
                    }
                }
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: AppTheme.radiusMD, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: AppTheme.radiusMD, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: AppTheme.radiusMD, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var coverageBottomTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showBottomTray.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Text("\(viewModel.visibleCoverageSegments.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 22)
                        .padding(.horizontal, AppTheme.spacingXS)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentMuted, in: Capsule())

                    Text(viewModel.selectedCoverageArea?.displayName ?? "Coverage")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: showBottomTray ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingSM)
            }
            .buttonStyle(.plain)

            if showBottomTray {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    if let area = viewModel.selectedCoverageArea {
                        HStack(spacing: AppTheme.spacingSM) {
                            metricChip(title: "Overall", value: String(format: "%.1f%%", area.coveragePercentage), color: AppTheme.accent)
                            metricChip(title: "Driven", value: "\(viewModel.coverageCounts.driven)", color: streetColor(for: .driven))
                            metricChip(title: "Undriven", value: "\(viewModel.coverageCounts.undriven)", color: streetColor(for: .undriven))
                        }

                        Text("Viewport: \(viewModel.coverageTotalInViewport) segments")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        Text("Open filters to choose a coverage area")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.bottom, AppTheme.spacingSM)
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: AppTheme.radiusMD, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: AppTheme.radiusMD, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: AppTheme.radiusMD, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func tripCard(_ trip: TripMapFeature) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text(trip.startTime, style: .date)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)

            Text(distanceLabel(trip.distanceMiles))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)

            Text(destinationLabel(for: trip))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(width: 140, alignment: .leading)
        .padding(AppTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
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
        .background(Color.white.opacity(0.05), in: Capsule())
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
        .background(Color.white.opacity(0.06), in: Capsule())
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
