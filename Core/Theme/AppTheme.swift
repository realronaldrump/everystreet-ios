import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let elevatedBackground = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let card = Color(red: 0.11, green: 0.16, blue: 0.27)
    static let cardHighlight = Color(red: 0.14, green: 0.22, blue: 0.34)
    static let accent = Color(red: 0.18, green: 0.78, blue: 0.93)
    static let accentWarm = Color(red: 0.98, green: 0.67, blue: 0.28)
    static let routeRecent = Color(red: 0.20, green: 0.88, blue: 0.98)
    static let routeOld = Color(red: 0.20, green: 0.39, blue: 0.66)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
}

extension LinearGradient {
    static var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.background,
                AppTheme.elevatedBackground,
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassCard: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.card.opacity(0.92),
                AppTheme.cardHighlight.opacity(0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient.glassCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 10)
    }
}

extension View {
    func glassCard(padding: CGFloat = 14, cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
