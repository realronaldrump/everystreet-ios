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
        .navigationTitle("Coverage Areas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
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

    private var coverageSummaryCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            SectionHeaderView("Coverage Overview", icon: "square.3.layers.3d")

            HStack(spacing: AppTheme.spacingSM) {
                StatCardView(
                    title: "Areas",
                    value: "\(viewModel.areas.count)",
                    icon: "map",
                    color: AppTheme.accent
                )
                StatCardView(
                    title: "Avg Coverage",
                    value: String(format: "%.1f%%", averageCoverage),
                    icon: "percent",
                    color: AppTheme.success
                )
            }

            HStack(spacing: AppTheme.spacingSM) {
                metricChip(title: "Driven", value: String(format: "%.1f mi", totalDrivenMiles))
                metricChip(title: "Driveable", value: String(format: "%.1f mi", totalDriveableMiles))
                metricChip(title: "Segments", value: "\(totalSegments)")
            }
        }
        .glassCard()
    }

    private func coverageAreaCard(_ area: CoverageArea) -> some View {
        let isExpanded = expandedAreaIDs.contains(area.id)

        return VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(alignment: .top, spacing: AppTheme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(area.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(area.areaType.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .tracking(0.6)
                }

                Spacer()

                HStack(spacing: AppTheme.spacingXS) {
                    Circle()
                        .fill(statusColor(for: area))
                        .frame(width: 7, height: 7)
                    Text(area.status.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, AppTheme.spacingSM)
                .padding(.vertical, AppTheme.spacingXS)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                HStack {
                    Text("Coverage")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                    Text(String(format: "%.1f%%", area.coveragePercentage))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }

                ProgressView(value: min(max(area.coveragePercentage / 100.0, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(AppTheme.accent)
            }

            HStack(spacing: AppTheme.spacingSM) {
                metricChip(title: "Driven", value: "\(area.drivenSegments)")
                metricChip(title: "Undriven", value: "\(area.undrivenSegments)")
                metricChip(title: "Miles", value: String(format: "%.1f", area.drivenLengthMiles))
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isExpanded {
                        expandedAreaIDs.remove(area.id)
                    } else {
                        expandedAreaIDs.insert(area.id)
                    }
                }
            } label: {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.subheadline)
                    Text(isExpanded ? "Hide Interactive Map" : "Show Interactive Map")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingSM)
                .background(AppTheme.accentMuted.opacity(0.5), in: Capsule())
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
        .glassCard()
    }

    private func metricChip(title: String, value: String) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
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
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No Coverage Areas Found")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)
            Text("Add coverage areas from the server first, then refresh this tab.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingLG)
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
                    ForEach(viewModel.visibleSegments) { segment in
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
                .mapStyle(.standard(elevation: .realistic))
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
