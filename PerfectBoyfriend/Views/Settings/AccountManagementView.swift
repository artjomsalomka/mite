import SwiftUI

struct AccountManagementView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false
    @State private var isDisconnectConfirmationPresented = false
    @State private var isDeleting = false
    @State private var isDisconnecting = false
    @State private var isUpdatingEmailStatus = false
    @State private var emailStatusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Konto & Sicherheit")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Du behältst die Kontrolle über deinen Zugang und deine Daten.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    infoCard(
                        title: "Für ein gutes Miteinander",
                        symbol: "hand.raised",
                        text: "Teile nur Inhalte, die dir gehören. Melde oder blockiere Profile sofort, wenn etwas unangenehm, irreführend oder unsicher wirkt. Für erste Treffen empfiehlt die App öffentliche Orte."
                    )

                    if authManager.appUser?.authProvider == .password {
                        emailVerificationCard
                    }

                    if authManager.appUser?.coupleId != nil {
                        disconnectCard
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text("Konto löschen")
                            .font(PBTheme.Typography.headline)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(deletionExplanation)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label(isDeleting ? "Konto wird gelöscht …" : "Konto endgültig löschen", systemImage: "trash")
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(PBTheme.destructive.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)
                    }
                    .padding(PBTheme.Spacing.md)
                    .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))

                    Text("Bereits abgegebene Sicherheitsmeldungen können als notwendige Moderationsnachweise bestehen bleiben. Vor einem öffentlichen Start gehören Kontakt- und Datenschutzangaben in die App-Store-Metadaten.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(PBTheme.Spacing.md)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog("Konto endgültig löschen?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text(deletionExplanation)
        }
        .confirmationDialog("Paarverbindung wirklich lösen?", isPresented: $isDisconnectConfirmationPresented, titleVisibility: .visible) {
            Button("Paarverbindung lösen", role: .destructive) {
                Task { await disconnectCouple() }
            }
        } message: {
            Text("Eure gemeinsamen Dates, das Paarprofil und gemeinsam veröffentlichte Beiträge werden gelöscht. Eure persönlichen Profile, Freundschaften und Gruppenevents bleiben bestehen.")
        }
        .alert("Konto konnte nicht gelöscht werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var emailVerificationCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack(spacing: PBTheme.Spacing.sm) {
                Image(systemName: authManager.isEmailVerified ? "checkmark.seal.fill" : "envelope.badge")
                    .foregroundStyle(authManager.isEmailVerified ? PBTheme.accent : PBTheme.textOnDarkSecondary)
                    .frame(width: 36, height: 36)
                    .background(PBTheme.controlSurface, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(authManager.isEmailVerified ? "E-Mail bestätigt" : "E-Mail noch nicht bestätigt")
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text(authManager.appUser?.email ?? "")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            }

            if let emailStatusMessage {
                Text(emailStatusMessage)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            HStack(spacing: PBTheme.Spacing.sm) {
                if !authManager.isEmailVerified {
                    Button("E-Mail erneut senden") {
                        Task { await sendVerification() }
                    }
                    .buttonStyle(.plain)
                }
                Button("Status aktualisieren") {
                    Task { await refreshVerification() }
                }
                .buttonStyle(.plain)
            }
            .font(PBTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(PBTheme.textOnDark)
            .disabled(isUpdatingEmailStatus)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var deletionExplanation: String {
        if authManager.appUser?.coupleId != nil {
            return "Dein Zugang, euer gemeinsamer Paarbereich, geteilte Dates, Beiträge und Bilder werden gelöscht. Die andere Person verliert die Paarverbindung und kann ein eigenes Konto weiter nutzen."
        }
        return "Dein Zugang, Profil, Bilder, Matches und Inhalte werden gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden."
    }

    private var disconnectCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text("Paarverbindung")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            Text("Du kannst in deinen persönlichen Bereich zurückkehren, ohne dein Konto, dein Profil oder Pläne mit Freund:innen zu verlieren.")
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            Button {
                isDisconnectConfirmationPresented = true
            } label: {
                Label(isDisconnecting ? "Verbindung wird gelöst …" : "Paarverbindung lösen", systemImage: "heart.slash")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PBTheme.controlSurface, in: Capsule())
                    .overlay { Capsule().stroke(PBTheme.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(isDisconnecting)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private func infoCard(title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(PBTheme.accent)
                .frame(width: 36, height: 36)
                .background(PBTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
                Text(text).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await authManager.deleteOwnAccount()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnectCouple() async {
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await authManager.disconnectCouple()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendVerification() async {
        isUpdatingEmailStatus = true
        emailStatusMessage = nil
        defer { isUpdatingEmailStatus = false }
        do {
            try await authManager.sendVerificationEmail()
            emailStatusMessage = "Die Bestätigungs-E-Mail wurde gesendet."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshVerification() async {
        isUpdatingEmailStatus = true
        emailStatusMessage = nil
        defer { isUpdatingEmailStatus = false }
        do {
            try await authManager.refreshEmailVerificationState()
            emailStatusMessage = authManager.isEmailVerified ? "Bestätigung erkannt." : "Noch nicht bestätigt. Öffne zuerst den Link in deiner E-Mail."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
