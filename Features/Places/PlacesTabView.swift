import SwiftUI

struct PlacesTabView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: PlacesViewModel

    init(appModel: AppModel, repository: PlacesRepository) {
        _appModel = Bindable(appModel)
        _viewModel = State(initialValue: PlacesViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.places.isEmpty {
                loadingView
            } else if viewModel.places.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.spacingMD) {
                        placeHeader

                        ForEach(Array(viewModel.places.enumerated()), id: \.element.id) { index, place in
                            placeRow(place, rank: index + 1)
                        }

                        if let selected = viewModel.selectedPlace,
                           let snapshot = viewModel.selectedPlaceTrips
                        {
                            placeTripsSection(selected: selected, snapshot: snapshot)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
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
        .navigationTitle("Places")
        .task {
            if viewModel.places.isEmpty {
                await viewModel.load()
            }
        }
    }

    // MARK: - Header

    private var placeHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            SectionHeaderView("Frequent Destinations", icon: "mappin.circle.fill")

            Text("Ranked by visit frequency")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Place Row

    private func placeRow(_ place: PlaceSummary, rank: Int) -> some View {
        let isSelected = viewModel.selectedPlace?.id == place.id
        let rankColor: Color = rank <= 3 ? AppTheme.accentWarm : AppTheme.textTertiary

        return Button {
            Task {
                await viewModel.select(place: place)
            }
        } label: {
            HStack(spacing: AppTheme.spacingMD) {
                // Rank badge
                Text("\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(rank <= 3 ? .white : AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        rank <= 3 ? rankColor.opacity(0.85) : Color.white.opacity(0.06)
                    , in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: AppTheme.spacingSM) {
                        MetricChipView(icon: "figure.walk", label: "Visits", value: "\(place.totalVisits ?? 0)")
                        MetricChipView(icon: "clock", label: "Avg", value: place.averageTimeSpent ?? "--")
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .glassCard(padding: AppTheme.spacingMD)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    // MARK: - Selected Place Trips

    private func placeTripsSection(selected: PlaceSummary, snapshot: PlaceTripsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            SectionHeaderView("Trips to \(selected.name)", icon: "arrow.triangle.turn.up.right.circle")

            if snapshot.trips.isEmpty {
                Text("No trips recorded for this place")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, AppTheme.spacingSM)
            } else {
                ForEach(snapshot.trips.prefix(12)) { trip in
                    HStack(spacing: AppTheme.spacingMD) {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.3))
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.endTime ?? .now, style: .date)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(trip.timeSpent ?? "--")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        Spacer()

                        Text(String(format: "%.1f mi", trip.distance ?? 0))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(AppTheme.spacingMD)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                }
            }
        }
        .glassCard()
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("Loading places\u{2026}")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.spacingLG) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No Places Found")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Places appear after recording trips")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD)
    }
}
