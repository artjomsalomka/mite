import SwiftUI

struct JoinCoupleView: View {
    @StateObject private var viewModel: CoupleOnboardingViewModel
    @FocusState private var isFieldFocused: Bool

    init(coupleService: CoupleService) {
        _viewModel = StateObject(wrappedValue: CoupleOnboardingViewModel(coupleService: coupleService))
    }

    var body: some View {
        PBScreenContainer {
            VStack(spacing: PBTheme.Spacing.lg) {
                Spacer()

                Image(systemName: "number.circle")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
                VStack(spacing: PBTheme.Spacing.sm) {
                    Text("Verbindungscode eingeben")
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Den sechsstelligen Code bekommst du von der Person, mit der du eure Profile verbinden möchtest.")
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.center)
                }

                TextField("000000", text: $viewModel.joinCode)
                    .font(.system(size: 35, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PBTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .focused($isFieldFocused)
                    .onChange(of: viewModel.joinCode) { _, newValue in
                        viewModel.joinCode = String(newValue.filter(\.isNumber).prefix(6))
                    }
                    .padding(.vertical, PBTheme.Spacing.md)
                    .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDark)
                        .multilineTextAlignment(.center)
                        .padding(PBTheme.Spacing.sm)
                        .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                }

                PBPrimaryButton(title: "Profile verbinden", symbol: "arrow.right", isLoading: viewModel.isSubmitting) {
                    Task { await viewModel.joinCouple() }
                }
                .disabled(!viewModel.canSubmitJoinCode || viewModel.isSubmitting)

                Spacer()
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.vertical, PBTheme.Spacing.lg)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { isFieldFocused = true }
    }
}
