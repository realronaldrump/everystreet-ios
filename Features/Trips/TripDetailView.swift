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
            VStack(alignment: .leading, spacing: 14) {
                if let detail = viewModel.detail {
                    mapSection(detail)
                    statsSection(detail)
                    placeSection(detail)
                    relatedSection
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
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

    private func mapSection(_ detail: TripDetail) -> some View {
        Map(position: $cameraPosition) {
            if detail.rawGeometry.count > 1 {
                MapPolyline(coordinates: detail.rawGeometry)
                    .stroke(AppTheme.routeRecent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let start = detail.startGeoPoint {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let end = detail.destinationGeoPoint {
                Annotation("End", coordinate: end) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(AppTheme.accentWarm)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func statsSection(_ detail: TripDetail) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            statCard("Distance", value: formatDistance(detail.distance))
            statCard("Duration", value: formatDuration(detail.duration))
            statCard("Avg Speed", value: formatSpeed(detail.avgSpeed))
            statCard("Max Speed", value: formatSpeed(detail.maxSpeed))
            statCard("Fuel", value: formatFuel(detail.fuelConsumed))
            statCard("Idle", value: formatDuration(detail.totalIdleDuration))
        }
    }

    private func placeSection(_ detail: TripDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label(detail.startLocation?.formattedAddress ?? "Unknown start", systemImage: "arrowtriangle.right.circle.fill")
                Label(detail.destination?.formattedAddress ?? "Unknown destination", systemImage: "mappin.and.ellipse")
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .glassCard()
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Related Trips")
                .font(.headline)

            if viewModel.relatedTrips.isEmpty {
                Text("No related trips found for this day.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(viewModel.relatedTrips.prefix(6)) { trip in
                    NavigationLink {
                        TripDetailView(tripID: trip.transactionId, repository: repository)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.startTime, style: .time)
                                    .font(.subheadline.weight(.semibold))
                                Text(trip.destination ?? trip.startLocation ?? "Unknown route")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatDistance(trip.distance))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    private func statCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func cameraPositionForDetail(_ detail: TripDetail?) -> MapCameraPosition {
        guard let detail, !detail.rawGeometry.isEmpty else { return .automatic }

        if let bbox = TripBoundingBox(coordinates: detail.rawGeometry) {
            let center = CLLocationCoordinate2D(latitude: (bbox.minLat + bbox.maxLat) / 2, longitude: (bbox.minLon + bbox.maxLon) / 2)
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
