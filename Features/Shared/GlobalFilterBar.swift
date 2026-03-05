import SwiftUI

struct GlobalFilterBar: View {
    @Bindable var appModel: AppModel
    var compact: Bool = false
    var onFilterChange: () -> Void

    @State private var showCustomRangeSheet = false
    @State private var draftStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var draftEnd = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? AppTheme.spacingSM : AppTheme.spacingMD) {
            // Preset buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    ForEach(DateRangePreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Vehicle selector + date range
            HStack(spacing: AppTheme.spacingSM) {
                Menu {
                    Button {
                        appModel.setSelectedVehicle(nil)
                        onFilterChange()
                    } label: {
                        Label("All Vehicles", systemImage: appModel.selectedIMEI == nil ? "checkmark" : "")
                    }

                    Divider()

                    ForEach(appModel.vehicles) { vehicle in
                        Button {
                            appModel.setSelectedVehicle(vehicle.imei)
                            onFilterChange()
                        } label: {
                            Label(vehicle.displayName, systemImage: appModel.selectedIMEI == vehicle.imei ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.spacingXS) {
                        Image(systemName: "car.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text(vehicleLabel)
                            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, AppTheme.spacingMD)
                    .padding(.vertical, compact ? AppTheme.spacingXS + 2 : AppTheme.spacingSM)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Spacer()

                Text(appModel.activeDateRange.shortLabel)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .glassCard(padding: compact ? AppTheme.spacingMD : AppTheme.spacingLG, cornerRadius: compact ? AppTheme.radiusMD : AppTheme.radiusLG)
        .sheet(isPresented: $showCustomRangeSheet) {
            customRangeSheet
        }
    }

    private func presetButton(_ preset: DateRangePreset) -> some View {
        let isActive = appModel.selectedPreset == preset

        return Button {
            if preset == .custom {
                draftStart = appModel.customDateRange.start
                draftEnd = appModel.customDateRange.end
                showCustomRangeSheet = true
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    appModel.setPreset(preset)
                }
                onFilterChange()
            }
        } label: {
            Text(preset.rawValue)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isActive ? .white : AppTheme.textSecondary)
                .padding(.horizontal, compact ? AppTheme.spacingMD : AppTheme.spacingLG)
                .padding(.vertical, compact ? AppTheme.spacingXS + 2 : AppTheme.spacingSM)
                .background(
                    Capsule()
                        .fill(isActive ? AppTheme.accent.opacity(0.28) : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? AppTheme.accent.opacity(0.45) : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: isActive)
    }

    private var customRangeSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()

                VStack(spacing: AppTheme.spacingXL) {
                    VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                        Text("START DATE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .tracking(0.8)
                        DatePicker("", selection: $draftStart, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                        Text("END DATE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .tracking(0.8)
                        DatePicker("", selection: $draftEnd, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    Spacer()
                }
                .padding(AppTheme.spacingLG)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomRangeSheet = false }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        appModel.setCustomRange(start: draftStart, end: draftEnd)
                        onFilterChange()
                        showCustomRangeSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }

    private var vehicleLabel: String {
        if let imei = appModel.selectedIMEI,
           let vehicle = appModel.vehicles.first(where: { $0.imei == imei })
        {
            return vehicle.displayName
        }
        return "All Vehicles"
    }
}
