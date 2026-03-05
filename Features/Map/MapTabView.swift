import MapKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MapTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: MapTabViewModel

    private let repository: TripsRepository

    init(appModel: AppModel, repository: TripsRepository, coordinateCache: LRUCoordinateCache) {
        _appModel = Bindable(appModel)
        self.repository = repository
        _viewModel = State(initialValue: MapTabViewModel(repository: repository, coordinateCache: coordinateCache))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            Map(position: $viewModel.cameraPosition, interactionModes: .all) {
                ForEach(viewModel.visibleTrips, id: \.transactionId) { trip in
                    if routeCoordinates(for: trip).count > 1 {
                        MapPolyline(coordinates: routeCoordinates(for: trip))
                            .stroke(
                                routeColor(for: trip).opacity(selectedOpacity(for: trip)),
                                style: StrokeStyle(lineWidth: selectedLineWidth(for: trip), lineCap: .round, lineJoin: .round)
                            )
                    }
                }

                ForEach(Array(viewModel.densityPoints.enumerated()), id: \.offset) { _, point in
                    Annotation("", coordinate: point.coordinate) {
                        Circle()
                            .fill(AppTheme.routeRecent.opacity(0.22 + min(Double(point.weight) / 16.0, 0.64)))
                            .frame(width: 10 + CGFloat(min(point.weight, 20)), height: 10 + CGFloat(min(point.weight, 20)))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.update(region: context.region)
            }
            .overlay(alignment: .center) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppTheme.accent)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack {
                    Text("Past Trips Map")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Button {
                        Task {
                            await viewModel.refresh(query: appModel.activeQuery, appModel: appModel)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                            .padding(10)
                            .background(Color.black.opacity(0.28), in: Circle())
                    }
                }
                .glassCard(padding: 10, cornerRadius: 14)

                SyncStatusBanner(state: appModel.syncState)

                GlobalFilterBar(appModel: appModel, compact: true) {
                    Task {
                        await viewModel.load(query: appModel.activeQuery, appModel: appModel)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .frame(maxHeight: .infinity, alignment: .top)

            bottomTray
                .padding(.horizontal, 12)
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

    private var bottomTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Visible Trips")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.visibleTrips.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.visibleTrips.prefix(20)) { trip in
                        NavigationLink {
                            TripDetailView(tripID: trip.transactionId, repository: repository)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(trip.startTime, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(distanceLabel(trip.distance))
                                    .font(.headline)
                                Text(destinationLabel(for: trip))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(11)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.card.opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

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

        return Color(
            red: AppTheme.routeOld.components.red + (AppTheme.routeRecent.components.red - AppTheme.routeOld.components.red) * clamped,
            green: AppTheme.routeOld.components.green + (AppTheme.routeRecent.components.green - AppTheme.routeOld.components.green) * clamped,
            blue: AppTheme.routeOld.components.blue + (AppTheme.routeRecent.components.blue - AppTheme.routeOld.components.blue) * clamped
        )
    }

    private func selectedLineWidth(for trip: TripSummary) -> CGFloat {
        trip.transactionId == viewModel.selectedTrip?.transactionId ? 3.2 : 2.0
    }

    private func selectedOpacity(for trip: TripSummary) -> CGFloat {
        if let selected = viewModel.selectedTrip {
            return selected.transactionId == trip.transactionId ? 1 : 0.55
        }
        return 0.85
    }

    private func distanceLabel(_ distance: Double?) -> String {
        guard let distance else { return "No distance" }
        return String(format: "%.1f mi", distance)
    }

    private func destinationLabel(for trip: TripSummary) -> String {
        trip.destination ?? trip.startLocation ?? "Unknown destination"
    }
}

private extension Color {
    var components: (red: Double, green: Double, blue: Double) {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
        #else
        return (0, 0, 0)
        #endif
    }
}
