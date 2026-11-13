import SwiftUI

struct SingleVerificationView: View {
    @ObservedObject var authManager: AuthManager
    @StateObject private var verificationService = SingleVerificationService()

    private var status: VerificationStatus {
        authManager.appUser?.verificationStatus ?? .unverified
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Identität")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Optional – für ein vertrauteres Kennenlernen.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    statusCard
                    explanationCard

                    if status != .verified {
                        PBPrimaryButton(
                            title: actionTitle,
                            symbol: "person.badge.shield.checkmark",
                            isLoading: verificationService.isWorking,
                            action: {
                                Task {
                                    if status == .pending {
                                        await verificationService.refreshStatus()
                                    } else {
                                        await verificationService.start()
                                    }
                                }
                            }
                        )
                    }

                    if status != .pending {
                        Button("Prüfstatus aktualisieren") {
                            Task { await verificationService.refreshStatus() }
                        }
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity)
                        .disabled(verificationService.isWorking)
                    }

                    if let message = verificationService.message {
                        Text(message)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Verifizierung nicht möglich", isPresented: Binding(
            get: { verificationService.errorMessage != nil },
            set: { if !$0 { verificationService.errorMessage = nil } }
        )) {
            Button("OK") { verificationService.errorMessage = nil }
        } message: {
            Text(verificationService.errorMessage ?? "")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Image(systemName: status == .verified ? "checkmark.seal.fill" : "person.badge.shield.checkmark")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(status == .verified ? PBTheme.success : PBTheme.accent)
                .frame(width: 58, height: 58)
                .background((status == .verified ? PBTheme.success : PBTheme.accent).opacity(0.14), in: Circle())
            Text(status.label)
                .font(PBTheme.Typography.title)
                .foregroundStyle(PBTheme.textPrimary)
            Text(statusDescription)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("So funktioniert es")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textPrimary)
            verificationPoint("doc.text.viewfinder", "Stripe prüft freiwillig ein Ausweisdokument und ein Live-Selfie.")
            verificationPoint("lock.shield", "Die App speichert keine Ausweisbilder oder extrahierte Ausweisdaten.")
            verificationPoint("eye.slash", "Andere Singles sehen nur die Bestätigung, nie persönliche Dokumentdaten.")
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    private func verificationPoint(_ symbol: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PBTheme.accent)
                .frame(width: 20)
            Text(title)
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textSecondary)
        }
    }

    private var actionTitle: String {
        switch status {
        case .pending: return "Prüfstatus aktualisieren"
        case .requiresInput: return "Verifizierung fortsetzen"
        case .unverified: return "Mit Stripe verifizieren"
        case .verified: return "Identität bestätigt"
        }
    }

    private var statusDescription: String {
        switch status {
        case .verified: return "Dein Profil kann als identitätsbestätigt angezeigt werden."
        case .pending: return "Stripe prüft deine Unterlagen. Du kannst den Status später aktualisieren."
        case .requiresInput: return "Stripe benötigt noch einmal eine gut lesbare Aufnahme."
        case .unverified: return "Die Verifizierung ist optional und erhöht das Vertrauen bei neuen Matches."
        }
    }
}
