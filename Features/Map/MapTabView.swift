import MapKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MapTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: MapTabViewModel

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
            Map(position: $viewModel.cameraPosition, interactionModes: .all) {
                if viewModel.selectedLayer == .trips {
                    ForEach(viewModel.visibleTrips, id: \.transactionId) { trip in
                        if routeCoordinates(for: trip).count > 1 {
                            MapPolyline(coordinates: routeCoordinates(for: trip))
                                .stroke(
                                    routeColor(for: trip).opacity(selectedOpacity(for: trip)),
                                    style: StrokeStyle(
                                        lineWidth: selectedLineWidth(for: trip),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }

                    ForEach(Array(viewModel.densityPoints.enumerated()), id: \.offset) { _, point in
                        Annotation("", coordinate: point.coordinate) {
                            Circle()
                                .fill(AppTheme.routeRecent.opacity(0.18 + min(Double(point.weight) / 18.0, 0.55)))
                                .frame(
                                    width: 8 + CGFloat(min(point.weight, 18)),
                                    height: 8 + CGFloat(min(point.weight, 18))
                                )
                        }
                    }
                } else {
                    ForEach(viewModel.visibleCoverageSegments) { segment in
                        if segment.coordinates.count > 1 {
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(
                                    streetColor(for: segment.status).opacity(streetOpacity(for: segment.status)),
                                    style: StrokeStyle(
                                        lineWidth: streetLineWidth(for: segment.status),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.update(region: context.region)
            }
            .ignoresSafeArea()

            if viewModel.isCurrentLayerLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
            }

            VStack(spacing: AppTheme.spacingSM) {
                topBar
                layerControls

                if viewModel.selectedLayer == .trips {
                    SyncStatusBanner(state: appModel.syncState)
                    GlobalFilterBar(appModel: appModel, compact: true) {
                        Task {
                            await viewModel.load(query: appModel.activeQuery, appModel: appModel)
                        }
                    }
                }

                if let error = viewModel.currentLayerErrorMessage {
                    errorBanner(error)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.top, 52)
            .frame(maxHeight: .infinity, alignment: .top)

            Group {
                if viewModel.selectedLayer == .trips {
                    tripsBottomTray
                } else {
                    coverageBottomTray
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, 94)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.allTrips.isEmpty {
                await viewModel.load(query: appModel.activeQuery, appModel: appModel)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: AppTheme.spacingMD) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedLayer == .trips ? "Trips Map" : "Coverage Streets")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.refreshCurrentLayer(query: appModel.activeQuery, appModel: appModel)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.pressable)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.isCurrentLayerLoading)
        }
        .glassCard(padding: AppTheme.spacingMD, cornerRadius: AppTheme.radiusMD)
    }

    private var layerControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                Label("Layer Controls", systemImage: "square.3.layers.3d")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                if let area = viewModel.selectedCoverageArea, viewModel.selectedLayer == .coverage {
                    Text(String(format: "%.1f%%", area.coveragePercentage))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, AppTheme.spacingSM)
                        .padding(.vertical, AppTheme.spacingXS)
                        .background(AppTheme.accentMuted, in: Capsule())
                }
            }

            Picker(
                "Map Layer",
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
                    Text(layer.title).tag(layer)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.selectedLayer == .coverage {
                HStack(spacing: AppTheme.spacingSM) {
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
                        HStack(spacing: AppTheme.spacingXS) {
                            Image(systemName: "location.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(viewModel.selectedCoverageArea?.displayName ?? "Choose Area")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(.horizontal, AppTheme.spacingMD)
                        .padding(.vertical, AppTheme.spacingSM)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    }

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
                }

                HStack(spacing: AppTheme.spacingSM) {
                    legendChip(label: "Driven", status: .driven)
                    legendChip(label: "Undriven", status: .undriven)
                    legendChip(label: "Undriveable", status: .undriveable)
                }
            }
        }
        .glassCard(padding: AppTheme.spacingMD, cornerRadius: AppTheme.radiusMD)
    }

    // MARK: - Bottom Trays

    private var tripsBottomTray: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                Text("Visible Trips")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(viewModel.visibleTrips.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingSM)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(AppTheme.accentMuted, in: Capsule())
            }

            if viewModel.visibleTrips.isEmpty {
                Text("Move the map to see trips in this area")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.spacingMD)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(viewModel.visibleTrips.prefix(20)) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.transactionId, repository: repository)
                            } label: {
                                tripCard(trip)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.background.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var coverageBottomTray: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                Text(viewModel.selectedCoverageArea?.displayName ?? "Coverage Streets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(viewModel.visibleCoverageSegments.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingSM)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(AppTheme.accentMuted, in: Capsule())
            }

            if let area = viewModel.selectedCoverageArea {
                HStack(spacing: AppTheme.spacingSM) {
                    metricChip(title: "Overall", value: String(format: "%.1f%%", area.coveragePercentage), color: AppTheme.accent)
                    metricChip(title: "Driven", value: "\(viewModel.coverageCounts.driven)", color: streetColor(for: .driven))
                    metricChip(title: "Undriven", value: "\(viewModel.coverageCounts.undriven)", color: streetColor(for: .undriven))
                }

                Text("Viewport: \(viewModel.coverageTotalInViewport) segments")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)

                if viewModel.coverageTruncated {
                    Text("Results are capped for this viewport. Zoom in for complete coverage.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warning)
                }
            } else {
                Text("Choose a coverage area in Layer Controls to load street coverage.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.background.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Components

    private func tripCard(_ trip: TripSummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text(trip.startTime, style: .date)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)

            Text(distanceLabel(trip.distance))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)

            Text(destinationLabel(for: trip))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(width: 150, alignment: .leading)
        .padding(AppTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
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
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD, cornerRadius: AppTheme.radiusMD)
    }

    // MARK: - Helpers

    private var geometryLevel: GeometryDetailLevel {
        switch viewModel.zoomBucket {
        case .low: .low
        case .mid: .medium
        case .high: .full
        }
    }

    private func routeCoordinates(for trip: TripSummary) -> [CLLocationCoordinate2D] {
        viewModel.coordinates(for: trip, level: geometryLevel)
    }

    private func routeColor(for trip: TripSummary) -> Color {
        let start = appModel.activeDateRange.start.timeIntervalSince1970
        let end = appModel.activeDateRange.end.timeIntervalSince1970
        let value = trip.startTime.timeIntervalSince1970

        guard end > start else { return AppTheme.routeRecent }

        let progress = (value - start) / (end - start)
        let clamped = max(0, min(1, progress))
        let old = (red: 0.22, green: 0.38, blue: 0.60)
        let recent = (red: 0.30, green: 0.85, blue: 1.0)

        return Color(
            red: old.red + (recent.red - old.red) * clamped,
            green: old.green + (recent.green - old.green) * clamped,
            blue: old.blue + (recent.blue - old.blue) * clamped
        )
    }

    private func selectedLineWidth(for trip: TripSummary) -> CGFloat {
        trip.transactionId == viewModel.selectedTrip?.transactionId ? 3.5 : 2.2
    }

    private func selectedOpacity(for trip: TripSummary) -> CGFloat {
        if let selected = viewModel.selectedTrip {
            return selected.transactionId == trip.transactionId ? 1 : 0.45
        }
        return 0.85
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

    private func streetLineWidth(for status: CoverageStreetStatus) -> CGFloat {
        switch status {
        case .driven: 3.0
        case .undriven: 2.4
        case .undriveable: 1.8
        case .unknown: 2.0
        }
    }

    private func streetOpacity(for status: CoverageStreetStatus) -> CGFloat {
        switch status {
        case .driven, .undriven: 0.9
        case .undriveable: 0.55
        case .unknown: 0.65
        }
    }

    private func distanceLabel(_ distance: Double?) -> String {
        guard let distance else { return "-- mi" }
        return String(format: "%.1f mi", distance)
    }

    private func destinationLabel(for trip: TripSummary) -> String {
        if let destination = trip.destination, !destination.isEmpty {
            return destination
        }
        if let startLocation = trip.startLocation, !startLocation.isEmpty {
            return startLocation
        }
        return "Trip \(trip.transactionId.prefix(8))"
    }
}
