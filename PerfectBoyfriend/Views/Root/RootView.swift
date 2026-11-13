import SwiftUI

/// Top-level branch on auth + couple state. Mirrors the Atlas convention of keeping all
/// navigation/tab logic out of the App entry point and inside a single RootView.
struct RootView: View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var coupleService = CoupleService()

    var body: some View {
        Group {
            if authManager.isLoading {
                EntryLoadingView(title: "Willkommen zurück", subtitle: "Dein Bereich wird vorbereitet.")
            } else if authManager.firebaseUser == nil {
                SignInView(authManager: authManager)
            } else if authManager.appUser == nil {
                ProfileConnectionRecoveryView(
                    message: authManager.profileLoadError ?? "Dein Profil wird noch geladen.",
                    retry: authManager.retryProfileLoad
                )
            } else if let appUser = authManager.appUser, let coupleId = appUser.coupleId {
                coupleGatedContent(coupleId: coupleId, viewer: appUser)
            } else if let appUser = authManager.appUser {
                // A person is the permanent account owner. Pairing and dating are optional
                // contexts that can be opened from the personal shell instead of blocking the
                // whole app behind a one-time account-mode decision.
                PersonalRootView(
                    authManager: authManager,
                    coupleService: coupleService,
                    viewer: appUser
                )
            }
        }
        .environmentObject(authManager)
        .animation(.default, value: authManager.isLoading)
        .animation(.default, value: authManager.firebaseUser?.uid)
        .animation(.default, value: authManager.appUser?.coupleId)
        .animation(.default, value: coupleService.couple?.status)
        .task(id: authManager.appUser?.coupleId) {
            if let coupleId = authManager.appUser?.coupleId {
                coupleService.startListening(coupleId: coupleId)
            } else {
                coupleService.stopListening()
            }
        }
    }

    @ViewBuilder
    private func coupleGatedContent(coupleId: String, viewer: AppUser) -> some View {
        if coupleService.isLoading {
            EntryLoadingView(
                title: "Eure Geschichte kommt zusammen",
                subtitle: "Momente, Pläne und gemeinsame Ideen werden vorbereitet."
            )
        } else if let couple = coupleService.couple {
            switch couple.status {
            case .pending:
                PendingCoupleView(couple: couple, authManager: authManager)
            case .active:
                MainTabView(authManager: authManager, couple: couple, viewer: viewer)
            }
        } else {
            ProfileConnectionRecoveryView(
                title: "Paarbereich nicht erreichbar",
                message: coupleService.loadError ?? "Euer Paarbereich wird noch geladen.",
                retry: coupleService.retryLoadingCouple
            )
        }
    }
}

/// A short ambient entry scene replaces the generic system spinner while Firebase restores the
/// shared account. It keeps the wait state in the same visual language as the rest of the app.
private struct EntryLoadingView: View {
    let title: String
    let subtitle: String
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PBScreenContainer {
            VStack(spacing: PBTheme.Spacing.lg) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                        .frame(width: 144, height: 144)
                    Circle()
                        .trim(from: 0.08, to: 0.36)
                        .stroke(PBTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 144, height: 144)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    Circle()
                        .fill(PBTheme.routeSurfaceRaised)
                        .frame(width: 88, height: 88)
                    Image(systemName: "sparkles")
                        .font(.system(size: 31, weight: .ultraLight))
                        .foregroundStyle(PBTheme.textOnDark)
                        .scaleEffect(isAnimating ? 1.08 : 0.94)
                }

                VStack(spacing: PBTheme.Spacing.sm) {
                    Text(title)
                        .font(PBTheme.Typography.greeting)
                        .foregroundStyle(PBTheme.textOnDark)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 310)
            }
            .padding(PBTheme.Spacing.xl)
        }
        .onAppear {
            updateAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateAnimation()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private func updateAnimation() {
        if reduceMotion {
            isAnimating = false
        } else {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

private struct ProfileConnectionRecoveryView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var signOutError: String?
    var title = "Profil nicht erreichbar"
    let message: String
    let retry: () -> Void

    var body: some View {
        PBScreenContainer {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(PBTheme.accent)
            Button("Neu anmelden") {
                do { try authManager.signOut() }
                catch { signOutError = error.localizedDescription }
            }
            .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .foregroundStyle(PBTheme.textOnDark)
        .padding(PBTheme.Spacing.lg)
        }
        .alert("Abmelden nicht möglich", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(signOutError ?? "") }
    }
}
