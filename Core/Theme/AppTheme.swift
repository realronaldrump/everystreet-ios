import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design System

enum AppTheme {

    // MARK: - Color Palette

    // Backgrounds — rich dark with subtle cool undertone
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let elevatedBackground = Color(red: 0.08, green: 0.08, blue: 0.12)

    // Surfaces — lifted from background
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.16)
    static let surfaceraised = Color(red: 0.14, green: 0.15, blue: 0.21)

    // Card fills for glass morphism
    static let card = Color(red: 0.10, green: 0.11, blue: 0.17)
    static let cardHighlight = Color(red: 0.14, green: 0.16, blue: 0.23)

    // Primary accent — vivid cyan-blue
    static let accent = Color(red: 0.20, green: 0.67, blue: 0.98)
    static let accentMuted = Color(red: 0.10, green: 0.22, blue: 0.34)

    // Secondary accent — warm amber/gold
    static let accentWarm = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let accentWarmMuted = Color(red: 0.28, green: 0.19, blue: 0.07)

    // Route visualization
    static let routeRecent = Color(red: 0.30, green: 0.85, blue: 1.0)
    static let routeOld = Color(red: 0.22, green: 0.38, blue: 0.60)

    // Semantic
    static let success = Color(red: 0.30, green: 0.82, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let error = Color(red: 0.92, green: 0.34, blue: 0.38)

    // Text
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.35)

    // Borders & Dividers
    static let border = Color.white.opacity(0.08)
    static let borderLight = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.06)

    // MARK: - Coverage Tier Colors

    /// Coverage ≥ 80%
    static let coverageExcellent = Color(red: 0.30, green: 0.82, blue: 0.55)
    /// Coverage 50–79%
    static let coverageGood = Color(red: 0.20, green: 0.67, blue: 0.98)
    /// Coverage 25–49%
    static let coverageModerate = Color(red: 1.0, green: 0.72, blue: 0.30)
    /// Coverage < 25%
    static let coverageLow = Color(red: 0.92, green: 0.40, blue: 0.42)

    static func coverageColor(for percentage: Double) -> Color {
        switch percentage {
        case 80...: return coverageExcellent
        case 50..<80: return coverageGood
        case 25..<50: return coverageModerate
        default: return coverageLow
        }
    }

    static func coverageGradient(for percentage: Double) -> LinearGradient {
        let base = coverageColor(for: percentage)
        return LinearGradient(
            colors: [base, base.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 20
    static let spacingXXL: CGFloat = 28

    // MARK: - Corner Radii

    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 14
    static let radiusLG: CGFloat = 18
    static let radiusXL: CGFloat = 22

    // MARK: - Stat Card Colors (for visual variety in grids)

    static let statDistance = Color(red: 0.20, green: 0.67, blue: 0.98)
    static let statDuration = Color(red: 0.62, green: 0.52, blue: 1.0)
    static let statSpeed = Color(red: 0.30, green: 0.82, blue: 0.55)
    static let statFuel = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let statIdle = Color(red: 0.92, green: 0.34, blue: 0.38)
    static let statMaxSpeed = Color(red: 1.0, green: 0.52, blue: 0.60)

    // MARK: - Chart Colors
    static let chartPrimary = Color(red: 0.36, green: 0.75, blue: 1.0)
    static let chartSecondary = Color(red: 0.62, green: 0.52, blue: 1.0)
    static let chartTertiary = Color(red: 0.30, green: 0.82, blue: 0.55)
}

// MARK: - Gradients

extension LinearGradient {
    static var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.background,
                AppTheme.elevatedBackground,
                Color(red: 0.03, green: 0.03, blue: 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var glassCard: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.card.opacity(0.75),
                AppTheme.cardHighlight.opacity(0.50),
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

    static func coverageCardGradient(for percentage: Double) -> LinearGradient {
        let color = AppTheme.coverageColor(for: percentage)
        return LinearGradient(
            colors: [
                AppTheme.card.opacity(0.75),
                color.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let tintColor: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        tintColor.map { color in
                            LinearGradient(
                                colors: [
                                    AppTheme.card.opacity(0.75),
                                    color.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } ?? LinearGradient.glassCard
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (tintColor ?? Color.white).opacity(0.18),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard(padding: CGFloat = AppTheme.spacingLG, cornerRadius: CGFloat = AppTheme.radiusLG) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius, tintColor: nil))
    }

    func glassCard(tint: Color, padding: CGFloat = AppTheme.spacingLG, cornerRadius: CGFloat = AppTheme.radiusLG) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius, tintColor: tint))
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
    let tint: Color

    init(_ title: String, icon: String? = nil, tint: Color = AppTheme.accent) {
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: AppTheme.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(title)
                .font(.headline.weight(.semibold))
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
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 90)
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
        // Tab bar — translucent dark
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.background.opacity(0.85))
        tabAppearance.shadowColor = .clear
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.30),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppTheme.accent),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
        ]

        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.30)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppTheme.accent)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar — translucent with blur
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = UIColor(AppTheme.background.opacity(0.78))
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 32, weight: .bold),
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.accent)
        #endif
    }
}
