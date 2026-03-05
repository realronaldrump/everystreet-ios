import SwiftUI

struct GlobalFilterBar: View {
    @Bindable var appModel: AppModel
    var compact: Bool = false
    var onFilterChange: () -> Void

    @State private var showCustomRangeSheet = false
    @State private var draftStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var draftEnd = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DateRangePreset.allCases) { preset in
                        Button {
                            if preset == .custom {
                                draftStart = appModel.customDateRange.start
                                draftEnd = appModel.customDateRange.end
                                showCustomRangeSheet = true
                            } else {
                                appModel.setPreset(preset)
                                onFilterChange()
                            }
                        } label: {
                            Text(preset.rawValue)
                                .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                                .padding(.horizontal, compact ? 10 : 12)
                                .padding(.vertical, compact ? 6 : 8)
                                .background(
                                    Capsule()
                                        .fill(appModel.selectedPreset == preset ? AppTheme.accent.opacity(0.28) : Color.white.opacity(0.10))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(appModel.selectedPreset == preset ? AppTheme.accent : Color.white.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button("All Vehicles") {
                        appModel.setSelectedVehicle(nil)
                        onFilterChange()
                    }

                    ForEach(appModel.vehicles) { vehicle in
                        Button(vehicle.displayName) {
                            appModel.setSelectedVehicle(vehicle.imei)
                            onFilterChange()
                        }
                    }
                } label: {
                    Label(vehicleLabel, systemImage: "car")
                        .font(compact ? .subheadline.weight(.medium) : .subheadline.weight(.medium))
                }

                Spacer()

                Text(appModel.activeDateRange.shortLabel)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .glassCard(padding: compact ? 10 : 14, cornerRadius: compact ? 16 : 18)
        .sheet(isPresented: $showCustomRangeSheet) {
            NavigationStack {
                Form {
                    DatePicker("Start", selection: $draftStart, displayedComponents: [.date])
                    DatePicker("End", selection: $draftEnd, displayedComponents: [.date])
                }
                .navigationTitle("Custom Range")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomRangeSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            appModel.setCustomRange(start: draftStart, end: draftEnd)
                            onFilterChange()
                            showCustomRangeSheet = false
                        }
                    }
                }
            }
        }
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
