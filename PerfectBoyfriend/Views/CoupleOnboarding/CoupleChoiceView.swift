import SwiftUI

struct CoupleChoiceView: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var coupleService: CoupleService

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                VStack(spacing: PBTheme.Spacing.lg) {
                    Spacer()

                    VStack(spacing: PBTheme.Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Verbindet euch")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Eure persönlichen Profile bleiben bestehen. Mit einem sechsstelligen Code verbindet ihr sie zu eurem gemeinsamen Bereich.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: PBTheme.Spacing.md) {
                        NavigationLink {
                            CreateCoupleView(coupleService: coupleService)
                        } label: {
                            PBOptionCard(
                                symbol: "plus.circle",
                                title: "Verbindung starten",
                                subtitle: "Erstelle euren Paarbereich und teile den Code."
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            JoinCoupleView(coupleService: coupleService)
                        } label: {
                            PBOptionCard(
                                symbol: "number.circle",
                                title: "Verbindung annehmen",
                                subtitle: "Du hast einen Code von deiner Person bekommen."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)

                    Button("Abmelden", role: .destructive) {
                        try? authManager.signOut()
                    }
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .padding(.bottom, PBTheme.Spacing.xl)
                }
                .padding(.horizontal, PBTheme.Spacing.md)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
