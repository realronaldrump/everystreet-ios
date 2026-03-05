import MapKit
import SwiftUI

struct CoverageAreasTabView: View {
    @State private var viewModel: CoverageAreasViewModel
    @State private var expandedAreaIDs: Set<String> = []

    private let repository: CoverageRepository

    init(repository: CoverageRepository) {
        self.repository = repository
        _viewModel = State(initialValue: CoverageAreasViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.areas.isEmpty {
                loadingView
            } else if viewModel.areas.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.spacingMD) {
                        coverageSummaryCard

                        ForEach(viewModel.areas) { area in
                            coverageAreaCard(area)
                        }

                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.bottom, AppTheme.spacingXXL)
                }
            }
        }
        .navigationTitle("Coverage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .symbolEffect(.rotate, isActive: viewModel.isLoading)
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if viewModel.areas.isEmpty {
                await viewModel.load()
            }
        }
    }

    // MARK: - Summary Card

    private var coverageSummaryCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("Overview", icon: "square.3.layers.3d")

            // Big average coverage ring
            HStack(spacing: AppTheme.spacingXL) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.divider, lineWidth: 6)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: min(averageCoverage / 100.0, 1))
                        .stroke(
                            AppTheme.coverageGradient(for: averageCoverage),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", averageCoverage))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.coverageColor(for: averageCoverage))
                        Text("%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    HStack(spacing: AppTheme.spacingSM) {
                        summaryChip(title: "Areas", value: "\(viewModel.areas.count)", icon: "map")
                        summaryChip(title: "Segments", value: "\(totalSegments)", icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    HStack(spacing: AppTheme.spacingSM) {
                        summaryChip(title: "Driven", value: String(format: "%.0f mi", totalDrivenMiles), icon: "car.fill")
                        summaryChip(title: "Remaining", value: String(format: "%.0f mi", totalDriveableMiles - totalDrivenMiles), icon: "road.lanes")
                    }
                }
            }
        }
        .glassCard()
    }

    private func summaryChip(title: String, value: String, icon: String) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS + 1)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    // MARK: - Area Card (color coded)

    private func coverageAreaCard(_ area: CoverageArea) -> some View {
        let isExpanded = expandedAreaIDs.contains(area.id)
        let tierColor = AppTheme.coverageColor(for: area.coveragePercentage)

        return VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            // Header row
            HStack(alignment: .top, spacing: AppTheme.spacingSM) {
                // Colored ring indicator
                ZStack {
                    Circle()
                        .stroke(AppTheme.divider, lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: min(area.coveragePercentage / 100.0, 1))
                        .stroke(tierColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))

                    Text(String(format: "%.0f", area.coveragePercentage))
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tierColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(area.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(area.areaType.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .tracking(0.8)
                }

                Spacer()

                HStack(spacing: AppTheme.spacingXS) {
                    Circle()
                        .fill(statusColor(for: area))
                        .frame(width: 6, height: 6)
                    Text(area.status.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, AppTheme.spacingSM)
                .padding(.vertical, AppTheme.spacingXS)
                .background(statusColor(for: area).opacity(0.10), in: Capsule())
            }

            // Coverage bar
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tierColor, tierColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(max(CGFloat(area.coveragePercentage / 100.0), 0), 1), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Stats row
            HStack(spacing: AppTheme.spacingSM) {
                metricChip(title: "Driven", value: "\(area.drivenSegments)", color: AppTheme.success)
                metricChip(title: "Remaining", value: "\(area.undrivenSegments)", color: AppTheme.warning)
                metricChip(title: "Miles", value: String(format: "%.1f", area.drivenLengthMiles), color: tierColor)
            }

            // Expand button
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    if isExpanded {
                        expandedAreaIDs.remove(area.id)
                    } else {
                        expandedAreaIDs.insert(area.id)
                    }
                }
            } label: {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: isExpanded ? "chevron.up" : "map")
                        .font(.caption.weight(.semibold))
                    Text(isExpanded ? "Hide Map" : "View Map")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tierColor)
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingSM)
                .background(tierColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.pressable)

            if isExpanded {
                CoverageAreaMapPanel(area: area, repository: repository)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .glassCard(tint: tierColor)
    }

    private func metricChip(title: String, value: String, color: Color) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("Loading coverage areas\u{2026}")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No Coverage Areas")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Add coverage areas on the server,\nthen pull to refresh.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD)
    }

    // MARK: - Computed

    private var averageCoverage: Double {
        guard !viewModel.areas.isEmpty else { return 0 }
        return viewModel.areas.reduce(0) { $0 + $1.coveragePercentage } / Double(viewModel.areas.count)
    }

    private var totalDrivenMiles: Double {
        viewModel.areas.reduce(0) { $0 + $1.drivenLengthMiles }
    }

    private var totalDriveableMiles: Double {
        viewModel.areas.reduce(0) { $0 + $1.driveableLengthMiles }
    }

    private var totalSegments: Int {
        viewModel.areas.reduce(0) { $0 + $1.totalSegments }
    }

    private func statusColor(for area: CoverageArea) -> Color {
        let health = area.health?.lowercased() ?? ""
        if health == "healthy" || area.status.lowercased() == "ready" {
            return AppTheme.success
        }
        if health == "degraded" || area.status.lowercased() == "processing" {
            return AppTheme.warning
        }
        return AppTheme.textTertiary
    }
}

private struct CoverageAreaMapPanel: View {
    let area: CoverageArea
    @State private var viewModel: CoverageAreaMapViewModel

    init(area: CoverageArea, repository: CoverageRepository) {
        self.area = area
        _viewModel = State(initialValue: CoverageAreaMapViewModel(areaID: area.id, repository: repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                Text("Street Coverage Map")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.pressable)
            }

            Picker(
                "Street Status",
                selection: Binding(
                    get: { viewModel.filter },
                    set: { viewModel.setFilter($0) }
                )
            ) {
                ForEach(CoverageStreetFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            ZStack {
                Map(position: $viewModel.cameraPosition, interactionModes: .all) {
                    ForEach(viewModel.renderedSegments) { segment in
                        if segment.coordinates.count > 1 {
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(
                                    streetColor(for: segment.status).opacity(streetOpacity(for: segment.status)),
                                    style: StrokeStyle(
                                        lineWidth: streetWidth(for: segment.status),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }
                .mapStyle(
                    .standard(
                        elevation: .flat,
                        emphasis: .muted,
                        pointsOfInterest: .excludingAll,
                        showsTraffic: false
                    )
                )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.update(region: context.region)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .padding(AppTheme.spacingSM)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                }
            }

            HStack(spacing: AppTheme.spacingSM) {
                legendChip("Driven", color: streetColor(for: .driven), count: viewModel.counts.driven)
                legendChip("Undriven", color: streetColor(for: .undriven), count: viewModel.counts.undriven)
                legendChip("Undriveable", color: streetColor(for: .undriveable), count: viewModel.counts.undriveable)
            }

            Text("Viewport: \(viewModel.totalInViewport) segments")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)

            if viewModel.isRenderingCapped {
                Text("Map is rendering \(viewModel.renderedSegments.count) streets for smoother performance.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warning)
            }

            if viewModel.truncated {
                Text("Viewport results are capped. Zoom in for complete local detail.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warning)
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.warning)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(AppTheme.spacingMD)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func legendChip(_ label: String, color: Color, count: Int) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS)
        .background(Color.white.opacity(0.06), in: Capsule())
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

    private func streetWidth(for status: CoverageStreetStatus) -> CGFloat {
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
}
