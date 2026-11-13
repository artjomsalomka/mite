import SwiftUI

struct SettingsView: View {
    @ObservedObject var authManager: AuthManager
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text("Einstellungen")
                                .font(PBTheme.Typography.display)
                                .foregroundStyle(PBTheme.textOnDark)
                            Text("Deine Konto- und Anmeldeinformationen.")
                                .font(PBTheme.Typography.body)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        if let appUser = authManager.appUser {
                            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                                accountRow("Name", value: appUser.displayName)
                                if let email = appUser.email {
                                    accountRow("E-Mail", value: email)
                                }
                                accountRow("Anmeldung", value: appUser.authProvider == .apple ? "Apple" : "E-Mail/Passwort")
                            }
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        }

                        Button("Abmelden", role: .destructive) {
                            do {
                                try authManager.signOut()
                            } catch {
                                signOutError = error.localizedDescription
                            }
                        }
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(PBTheme.surface, in: Capsule())

                        if let signOutError {
                            Text(signOutError)
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDark)
                                .padding(PBTheme.Spacing.sm)
                                .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                        }
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func accountRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textSecondary)
            Spacer(minLength: PBTheme.Spacing.md)
            Text(value)
                .font(PBTheme.Typography.body.weight(.medium))
                .foregroundStyle(PBTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
