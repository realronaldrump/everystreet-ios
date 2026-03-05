import MapKit
import SwiftUI

struct TripDetailView: View {
    let tripID: String
    let repository: TripsRepository

    @State private var viewModel: TripDetailViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(tripID: String, repository: TripsRepository) {
        self.tripID = tripID
        self.repository = repository
        _viewModel = State(initialValue: TripDetailViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingLG) {
                if let detail = viewModel.detail {
                    mapSection(detail)
                    statsSection(detail)
                    routeSection(detail)
                    relatedSection
                } else if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, AppTheme.spacingXXL)
        }
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.detail == nil {
                await viewModel.load(tripID: tripID)
                cameraPosition = cameraPositionForDetail(viewModel.detail)
            }
        }
    }

    // MARK: - Map Section

    private func mapSection(_ detail: TripDetail) -> some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if detail.rawGeometry.count > 1 {
                    MapPolyline(coordinates: detail.rawGeometry)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.routeOld, AppTheme.routeRecent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }

                if let start = detail.startGeoPoint {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(AppTheme.success)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: AppTheme.success.opacity(0.5), radius: 4)
                    }
                }

                if let end = detail.destinationGeoPoint {
                    Annotation("End", coordinate: end) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.accentWarm)
                            .shadow(color: AppTheme.accentWarm.opacity(0.5), radius: 4)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 300)

            // Gradient fade at bottom
            LinearGradient(
                colors: [.clear, AppTheme.background.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Stats Section

    private func statsSection(_ detail: TripDetail) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.spacingMD) {
            StatCardView(title: "Distance", value: formatDistance(detail.distance), icon: "road.lanes", color: AppTheme.statDistance)
            StatCardView(title: "Duration", value: formatDuration(detail.duration), icon: "clock.fill", color: AppTheme.statDuration)
            StatCardView(title: "Avg Speed", value: formatSpeed(detail.avgSpeed), icon: "gauge.medium", color: AppTheme.statSpeed)
            StatCardView(title: "Max Speed", value: formatSpeed(detail.maxSpeed), icon: "gauge.high", color: AppTheme.statMaxSpeed)
            StatCardView(title: "Fuel", value: formatFuel(detail.fuelConsumed), icon: "fuelpump.fill", color: AppTheme.statFuel)
            StatCardView(title: "Idle Time", value: formatDuration(detail.totalIdleDuration), icon: "pause.circle.fill", color: AppTheme.statIdle)
        }
    }

    // MARK: - Route Section

    private func routeSection(_ detail: TripDetail) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingLG) {
            SectionHeaderView("Route", icon: "point.topleft.down.to.point.bottomright.curvepath")

            VStack(alignment: .leading, spacing: 0) {
                // Start point
                HStack(spacing: AppTheme.spacingMD) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(AppTheme.success)
                            .frame(width: 10, height: 10)
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("START")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .tracking(0.8)
                        Text(detail.startLocation?.formattedAddress ?? "Unknown")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, AppTheme.spacingSM)
                }

                // End point
                HStack(spacing: AppTheme.spacingMD) {
                    Circle()
                        .fill(AppTheme.accentWarm)
                        .frame(width: 10, height: 10)
                        .frame(width: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DESTINATION")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .tracking(0.8)
                        Text(detail.destination?.formattedAddress ?? "Unknown")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, AppTheme.spacingSM)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Related Trips

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("Related Trips", icon: "calendar")

            if viewModel.relatedTrips.isEmpty {
                Text("No other trips on this day")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, AppTheme.spacingSM)
            } else {
                ForEach(viewModel.relatedTrips.prefix(6)) { trip in
                    NavigationLink {
                        TripDetailView(tripID: trip.transactionId, repository: repository)
                    } label: {
                        HStack(spacing: AppTheme.spacingMD) {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.3))
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.startTime, style: .time)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(trip.destination ?? trip.startLocation ?? "Unknown")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(formatDistance(trip.distance))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(AppTheme.spacingMD)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("Loading trip details\u{2026}")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(AppTheme.error)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Helpers

    private func cameraPositionForDetail(_ detail: TripDetail?) -> MapCameraPosition {
        guard let detail, !detail.rawGeometry.isEmpty else { return .automatic }

        if let bbox = TripBoundingBox(coordinates: detail.rawGeometry) {
            let center = CLLocationCoordinate2D(
                latitude: (bbox.minLat + bbox.maxLat) / 2,
                longitude: (bbox.minLon + bbox.maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((bbox.maxLat - bbox.minLat) * 1.8, 0.01),
                longitudeDelta: max((bbox.maxLon - bbox.minLon) * 1.8, 0.01)
            )
            return .region(MKCoordinateRegion(center: center, span: span))
        }

        return .automatic
    }

    private func formatDistance(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f mi", value)
    }

    private func formatSpeed(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f mph", value)
    }

    private func formatDuration(_ value: Double?) -> String {
        guard let value else { return "--" }
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatFuel(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f gal", value)
    }
}
