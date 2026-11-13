import SwiftUI

struct PushNotificationSettingsView: View {
    @ObservedObject var authManager: AuthManager
    @StateObject private var pushService = PushNotificationService.shared

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Benachrichtigungen")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Du entscheidest, wann dieses Gerät an gemeinsame Pläne erinnern darf.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                        Label(statusLabel, systemImage: statusSymbol)
                            .font(PBTheme.Typography.headline)
                            .foregroundStyle(pushService.isEnabledForCurrentUser ? PBTheme.success : PBTheme.textPrimary)
                        Text("Dieses Gerät kann neutrale Hinweise zu neuen Matches, Chat-Nachrichten und Date-Plänen erhalten.")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textSecondary)
                        if let uid = authManager.firebaseUser?.uid {
                            if pushService.isEnabledForCurrentUser {
                                Button("Dieses Gerät abmelden", role: .destructive) {
                                    Task { await pushService.disable(for: uid) }
                                }
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.destructive)
                            } else {
                                Button("Benachrichtigungen aktivieren") {
                                    Task { await pushService.enable(for: uid) }
                                }
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.accent)
                            }
                        }
                    }
                    .padding(PBTheme.Spacing.md)
                    .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Privatsphäre")
                        Text("Push-Texte bleiben bewusst allgemein und enthalten keine Chat-Inhalte, Telefonnummern oder genauen Treffpunkte.")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textPrimary)
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: authManager.firebaseUser?.uid) {
            if let uid = authManager.firebaseUser?.uid {
                await pushService.load(for: uid)
            }
        }
        .alert("Benachrichtigungen nicht möglich", isPresented: Binding(
            get: { pushService.errorMessage != nil },
            set: { if !$0 { pushService.errorMessage = nil } }
        )) {
            Button("OK") { pushService.errorMessage = nil }
        } message: {
            Text(pushService.errorMessage ?? "")
        }
    }

    private var statusLabel: String {
        if pushService.isEnabledForCurrentUser { return "Auf diesem Gerät aktiviert" }
        if pushService.authorizationStatus == .denied { return "In iOS deaktiviert" }
        return "Nicht aktiviert"
    }

    private var statusSymbol: String {
        pushService.isEnabledForCurrentUser ? "bell.badge.fill" : "bell.slash"
    }
}
