import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var isPasswordFocused: Bool
    @State private var password = ""

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            VStack(spacing: AppTheme.spacingXL) {
                Spacer(minLength: AppTheme.spacingXXL)

                VStack(spacing: AppTheme.spacingMD) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.accent)

                    Text("Owner Session Required")
                        .font(AppTypography.hero)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Every Street Companion now signs in directly to www.everystreet.me so the app can create the owner session cookie required by the API.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                    if appModel.sessionState == .checking || appModel.isBootstrapping {
                        HStack(spacing: AppTheme.spacingMD) {
                            ProgressView()
                                .tint(AppTheme.accent)
                            Text("Checking session...")
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    } else {
                        Text("Owner Password")
                            .font(AppTypography.captionHeavy)
                            .foregroundStyle(AppTheme.textTertiary)
                            .textCase(.uppercase)

                        SecureField("Enter password", text: $password)
                            .textContentType(.password)
                            .focused($isPasswordFocused)
                            .padding(.horizontal, AppTheme.spacingMD)
                            .padding(.vertical, AppTheme.spacingMD)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                                    .fill(AppTheme.panelInset)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                                    .stroke(AppTheme.panelBorder, lineWidth: 0.8)
                            )
                            .foregroundStyle(AppTheme.textPrimary)
                            .submitLabel(.go)
                            .onSubmit {
                                submit()
                            }

                        if let message = appModel.sessionMessage ?? appModel.bootstrapErrorMessage {
                            Text(message)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppTheme.warning)
                        }

                        Button(action: submit) {
                            HStack(spacing: AppTheme.spacingSM) {
                                if appModel.isAuthenticating {
                                    ProgressView()
                                        .tint(AppTheme.textPrimary)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                Text(appModel.isAuthenticating ? "Signing In" : "Sign In")
                                    .font(AppTypography.bodyStrong)
                            }
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingMD)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                                    .fill(LinearGradient.accentGradient)
                            )
                        }
                        .buttonStyle(.pressable)
                        .disabled(appModel.isAuthenticating)

                        Button("Clear Saved Session") {
                            password = ""
                            appModel.clearSession()
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: 460, alignment: .leading)
                .glassCard(tint: AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingLG)

                Spacer()
            }
        }
        .onAppear {
            if appModel.sessionState == .unauthenticated {
                isPasswordFocused = true
            }
        }
    }

    private func submit() {
        let submittedPassword = password
        Task {
            await appModel.signIn(password: submittedPassword)
            if appModel.isAuthenticated {
                password = ""
            }
        }
    }
}