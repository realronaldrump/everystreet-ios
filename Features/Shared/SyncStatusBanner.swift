import SwiftUI

struct SyncStatusBanner: View {
    let state: SyncState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .syncing:
            Label("Syncing trips…", systemImage: "arrow.triangle.2.circlepath")
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(AppTheme.accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .stale(lastUpdated):
            Label(staleMessage(lastUpdated), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(AppTheme.accentWarm.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func staleMessage(_ date: Date?) -> String {
        guard let date else { return "Showing cached trips" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Showing cached trips (updated \(formatter.localizedString(for: date, relativeTo: .now)))"
    }
}
