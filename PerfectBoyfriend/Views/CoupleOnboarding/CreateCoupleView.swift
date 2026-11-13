import SwiftUI

struct CreateCoupleView: View {
    @StateObject private var viewModel: CoupleOnboardingViewModel

    init(coupleService: CoupleService) {
        _viewModel = StateObject(wrappedValue: CoupleOnboardingViewModel(coupleService: coupleService))
    }

    var body: some View {
        PBScreenContainer {
            VStack(spacing: PBTheme.Spacing.lg) {
                Spacer()

                if let code = viewModel.createdInviteCode {
                    VStack(spacing: PBTheme.Spacing.md) {
                        Image(systemName: "link")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Euer Verbindungscode")
                            .font(PBTheme.Typography.title)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(code)
                            .font(.system(size: 42, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PBTheme.textPrimary)
                            .tracking(6)
                            .padding(.vertical, PBTheme.Spacing.lg)
                            .padding(.horizontal, PBTheme.Spacing.xl)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))

                        Text("Teile ihn mit deiner Person. Sobald sie beitritt, werden eure beiden Profile zu einem gemeinsamen Bereich verbunden.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                            .multilineTextAlignment(.center)

                        ShareLink(item: "Mite: Verbinde dein Profil mit meinem gemeinsamen Bereich: \(code)") {
                            Label("Code teilen", systemImage: "square.and.arrow.up")
                                .font(PBTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        .padding(.top, PBTheme.Spacing.xs)

                        HStack(spacing: PBTheme.Spacing.sm) {
                            ProgressView().tint(PBTheme.textOnDark)
                            Text("Warte auf die Verbindung …")
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        .padding(.top, PBTheme.Spacing.md)
                    }
                } else if viewModel.isSubmitting {
                    VStack(spacing: PBTheme.Spacing.md) {
                        ProgressView().tint(PBTheme.textOnDark)
                        Text("Eure Verbindung wird vorbereitet …")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: PBTheme.Spacing.md) {
                        Text(errorMessage)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDark)
                            .multilineTextAlignment(.center)
                        PBPrimaryButton(title: "Erneut versuchen") {
                            Task { await viewModel.createCouple() }
                        }
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                }

                Spacer()
            }
            .padding(PBTheme.Spacing.lg)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if viewModel.createdInviteCode == nil {
                await viewModel.createCouple()
            }
        }
    }
}
