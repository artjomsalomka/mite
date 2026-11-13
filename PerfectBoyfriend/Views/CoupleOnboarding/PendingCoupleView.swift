import SwiftUI

/// Shown when the signed-in user already has a `coupleId` but the couple is still `pending`
/// (e.g. after relaunching the app before the partner joined) — reads the invite code straight
/// from the live couple doc rather than local view-model state, which wouldn't survive a relaunch.
struct PendingCoupleView: View {
    let couple: Couple
    @ObservedObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                VStack(spacing: PBTheme.Spacing.lg) {
                    Spacer()
                    Image(systemName: "link")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Euer Verbindungscode")
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text(couple.inviteCode)
                        .font(.system(size: 42, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PBTheme.textPrimary)
                        .tracking(6)
                        .padding(.vertical, PBTheme.Spacing.lg)
                        .padding(.horizontal, PBTheme.Spacing.xl)
                        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
                    HStack(spacing: PBTheme.Spacing.sm) {
                        ProgressView().tint(PBTheme.textOnDark)
                        Text("Warte auf die Verbindung …")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    Spacer()
                    Button("Abmelden", role: .destructive) {
                        try? authManager.signOut()
                    }
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(PBTheme.Spacing.lg)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
