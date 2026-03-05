import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design System

enum AppTheme {

    // MARK: - Color Palette

    // Backgrounds — deep dark with subtle blue undertone
    static let background = Color(red: 0.04, green: 0.04, blue: 0.07)
    static let elevatedBackground = Color(red: 0.07, green: 0.07, blue: 0.13)

    // Surfaces — slightly lifted from background
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.18)
    static let surfaceraised = Color(red: 0.13, green: 0.14, blue: 0.23)

    // Card fills for glass morphism
    static let card = Color(red: 0.10, green: 0.11, blue: 0.19)
    static let cardHighlight = Color(red: 0.14, green: 0.16, blue: 0.26)

    // Primary accent — electric cyan
    static let accent = Color(red: 0.24, green: 0.70, blue: 0.95)
    static let accentMuted = Color(red: 0.12, green: 0.25, blue: 0.36)

    // Secondary accent — warm amber
    static let accentWarm = Color(red: 1.0, green: 0.70, blue: 0.28)
    static let accentWarmMuted = Color(red: 0.30, green: 0.20, blue: 0.08)

    // Route visualization
    static let routeRecent = Color(red: 0.30, green: 0.85, blue: 1.0)
    static let routeOld = Color(red: 0.22, green: 0.38, blue: 0.60)

    // Semantic
    static let success = Color(red: 0.30, green: 0.82, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let error = Color(red: 0.92, green: 0.34, blue: 0.38)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)

    // Borders & Dividers
    static let border = Color.white.opacity(0.08)
    static let borderLight = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.06)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 20
    static let spacingXXL: CGFloat = 24

    // MARK: - Corner Radii

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusXL: CGFloat = 20

    // MARK: - Stat Card Colors (for visual variety in grids)

    static let statDistance = Color(red: 0.24, green: 0.70, blue: 0.95)
    static let statDuration = Color(red: 0.65, green: 0.55, blue: 1.0)
    static let statSpeed = Color(red: 0.30, green: 0.82, blue: 0.55)
    static let statFuel = Color(red: 1.0, green: 0.70, blue: 0.28)
    static let statIdle = Color(red: 0.92, green: 0.34, blue: 0.38)
    static let statMaxSpeed = Color(red: 1.0, green: 0.52, blue: 0.60)
}

// MARK: - Gradients

extension LinearGradient {
    static var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.background,
                AppTheme.elevatedBackground,
                Color(red: 0.02, green: 0.02, blue: 0.05),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var glassCard: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.card.opacity(0.80),
                AppTheme.cardHighlight.opacity(0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient.glassCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glassCard(padding: CGFloat = AppTheme.spacingLG, cornerRadius: CGFloat = AppTheme.radiusLG) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Inner Card (for nested elements within glass cards)

struct InnerCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(AppTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func innerCard(cornerRadius: CGFloat = AppTheme.radiusMD) -> some View {
        modifier(InnerCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Accent Strip (colored bar on card edge)

struct AccentStripModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
            content
        }
    }
}

extension View {
    func accentStrip(_ color: Color = AppTheme.accent) -> some View {
        modifier(AccentStripModifier(color: color))
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Themed Accent Button Style

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, AppTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .fill(AppTheme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

// MARK: - Section Header

struct SectionHeaderView: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: AppTheme.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - Stat Card Component

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: AppTheme.spacingSM) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: AppTheme.spacingMD, cornerRadius: AppTheme.radiusMD)
    }
}

// MARK: - Metric Chip Component

struct MetricChipView: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: AppTheme.spacingXS) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingXS)
        .background(Color.white.opacity(0.06), in: Capsule())
    }
}

// MARK: - Tab Bar Appearance Configuration

enum AppAppearance {
    @MainActor static func configure() {
        #if canImport(UIKit)
        // Tab bar
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.background.opacity(0.92))
        tabAppearance.shadowColor = .clear

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.35),
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppTheme.accent),
        ]

        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.35)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppTheme.accent)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(AppTheme.background.opacity(0.85))
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.accent)
        #endif
    }
}
