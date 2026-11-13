import SwiftUI

struct SignInView: View {
    @StateObject private var viewModel: AuthViewModel
    @State private var isPasswordResetPresented = false

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(authManager: authManager))
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(spacing: PBTheme.Spacing.lg) {
                    header

                    // A plain button, not SwiftUI's SignInWithAppleButton view: AuthManager drives
                    // its own ASAuthorizationController so it can thread the nonce through to the
                    // Firebase credential exchange — the built-in view's onCompletion callback would
                    // require re-plumbing the same nonce a second way for no benefit.
                    Button {
                        Task { await viewModel.signInWithApple() }
                    } label: {
                        HStack(spacing: PBTheme.Spacing.sm) {
                            Image(systemName: "apple.logo")
                            Text("Mit Apple fortfahren")
                        }
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(PBTheme.controlSurfaceRaised, in: Capsule())
                        .overlay { Capsule().stroke(PBTheme.controlBorder, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmittingApple)

                    dividerRow

                    emailForm

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .multilineTextAlignment(.center)
                            .padding(PBTheme.Spacing.sm)
                            .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.vertical, PBTheme.Spacing.xl)
            }
        }
        .sheet(isPresented: $isPasswordResetPresented) {
            PasswordResetView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationBackground(PBTheme.midnightRaised)
        }
    }

    private var header: some View {
        VStack(spacing: PBTheme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
            Text("Eure Zeit, gut geplant.")
                .font(PBTheme.Typography.display)
                .foregroundStyle(PBTheme.textOnDark)
            Text("Entdeckt Ideen, Orte und Momente, die zu euch passen.")
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, PBTheme.Spacing.lg)
    }

    private var dividerRow: some View {
        HStack {
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            Text("oder").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
        }
    }

    private var emailForm: some View {
        VStack(spacing: PBTheme.Spacing.md) {
            Picker("Modus", selection: $viewModel.mode) {
                Text("Anmelden").tag(AuthViewModel.Mode.signIn)
                Text("Registrieren").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)
            .tint(PBTheme.controlSelected)
            .padding(4)
            .background(PBTheme.controlSurface, in: Capsule())
            .overlay { Capsule().stroke(PBTheme.controlBorder, lineWidth: 1) }

            if viewModel.mode == .signUp {
                TextField("Anzeigename", text: $viewModel.displayName)
                    .midnightTextField()
            }

            TextField("E-Mail", text: $viewModel.email)
                .midnightTextField()
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            SecureField("Passwort", text: $viewModel.password)
                .midnightTextField()
                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)

            PBPrimaryButton(
                title: viewModel.mode == .signIn ? "Anmelden" : "Konto erstellen",
                isLoading: viewModel.isSubmittingEmail
            ) {
                Task { await viewModel.submitEmailForm() }
            }
            .disabled(!viewModel.canSubmitEmailForm || viewModel.isSubmittingEmail)

            if viewModel.mode == .signIn {
                Button("Passwort vergessen?") {
                    viewModel.resetEmail = viewModel.email
                    viewModel.errorMessage = nil
                    viewModel.passwordResetMessage = nil
                    isPasswordResetPresented = true
                }
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PasswordResetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PBScreenContainer {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Neues Passwort")
                            .font(PBTheme.Typography.title)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Wir senden dir einen sicheren Link an deine E-Mail-Adresse.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    Spacer(minLength: PBTheme.Spacing.sm)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(PBTheme.textOnDark)
                            .frame(width: 34, height: 34)
                            .background(PBTheme.controlSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                TextField("E-Mail", text: $viewModel.resetEmail)
                    .midnightTextField()
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                if let message = viewModel.passwordResetMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDark)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDark)
                }

                PBPrimaryButton(title: viewModel.passwordResetMessage == nil ? "Link senden" : "Fertig", symbol: viewModel.passwordResetMessage == nil ? "paperplane" : "checkmark", isLoading: viewModel.isResettingPassword) {
                    if viewModel.passwordResetMessage != nil {
                        dismiss()
                    } else {
                        Task { _ = await viewModel.resetPassword() }
                    }
                }
                .disabled(viewModel.isResettingPassword || viewModel.resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 0)
            }
            .padding(PBTheme.Spacing.lg)
        }
    }
}

private extension View {
    func midnightTextField() -> some View {
        self
            .font(PBTheme.Typography.body)
            .foregroundStyle(PBTheme.textOnDark)
            .padding(.horizontal, PBTheme.Spacing.md)
            .frame(minHeight: 52)
            .background(PBTheme.controlSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous)
                    .stroke(PBTheme.controlBorder, lineWidth: 1)
            }
    }
}
