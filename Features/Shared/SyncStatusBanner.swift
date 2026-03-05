import SwiftUI

struct SyncStatusBanner: View {
    let state: SyncState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .syncing:
            statusRow(
                icon: "arrow.triangle.2.circlepath",
                text: "Syncing trips\u{2026}",
                color: AppTheme.accent,
                background: AppTheme.accentMuted
            )
        case let .stale(lastUpdated):
            statusRow(
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                text: staleMessage(lastUpdated),
                color: AppTheme.accentWarm,
                background: AppTheme.accentWarmMuted
            )
        case let .failed(message):
            statusRow(
                icon: "exclamationmark.triangle.fill",
                text: message,
                color: AppTheme.error,
                background: AppTheme.error.opacity(0.12)
            )
        }
    }

    private func statusRow(icon: String, text: String, color: Color, background: Color) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: icon.contains("circlepath"))

            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.vertical, AppTheme.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    private func staleMessage(_ date: Date?) -> String {
        guard let date else { return "Showing cached trips" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Cached \u{2022} \(formatter.localizedString(for: date, relativeTo: .now))"
    }
}
