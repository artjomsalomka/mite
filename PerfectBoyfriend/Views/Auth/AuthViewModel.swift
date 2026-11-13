import FirebaseAuth
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: Hashable {
        case signIn
        case signUp
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    // Kept as two separate flags rather than one shared `isSubmitting`: Sign in with Apple can
    // get stuck indefinitely on the system's own Apple-ID-authentication step with no callback
    // ever firing (a real Simulator limitation, confirmed live — the device-attestation retry
    // loop never resolves for a real Apple ID in the Simulator), and a single shared flag would
    // leave the email/password form permanently disabled by an unrelated, unrecoverable hang.
    @Published var isSubmittingEmail = false
    @Published var isSubmittingApple = false
    @Published var errorMessage: String?
    @Published var resetEmail = ""
    @Published var isResettingPassword = false
    @Published var passwordResetMessage: String?

    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    var canSubmitEmailForm: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp { return !displayName.isEmpty }
        return true
    }

    func submitEmailForm() async {
        errorMessage = nil
        isSubmittingEmail = true
        defer { isSubmittingEmail = false }
        do {
            switch mode {
            case .signIn:
                try await authManager.signIn(email: email, password: password)
            case .signUp:
                try await authManager.signUp(email: email, password: password, displayName: displayName)
            }
        } catch {
            errorMessage = Self.userFacingMessage(for: error, mode: mode)
        }
    }

    func signInWithApple() async {
        errorMessage = nil
        isSubmittingApple = true
        defer { isSubmittingApple = false }
        do {
            try await authManager.signInWithApple()
        } catch {
            let nsError = error as NSError
            let userCancelled = nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001
            if !userCancelled {
                errorMessage = Self.userFacingMessage(for: error, mode: mode)
            }
        }
    }

    func resetPassword() async -> Bool {
        errorMessage = nil
        passwordResetMessage = nil
        isResettingPassword = true
        defer { isResettingPassword = false }
        do {
            try await authManager.sendPasswordReset(email: resetEmail)
            passwordResetMessage = "Wir haben dir einen Link zum Zurücksetzen geschickt."
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error, mode: .signIn)
            return false
        }
    }

    /// Firebase deliberately merges "unknown account" and "wrong password" into
    /// `invalidCredential` when email-enumeration protection is active. Never surface the SDK's
    /// technical English fallback ("credential is malformed or expired") in the product UI.
    private static func userFacingMessage(for error: Error, mode: Mode) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidCredential, .wrongPassword, .userNotFound:
            #if STAGING
            return "Dieses Testkonto existiert in Mite Staging noch nicht oder das Passwort ist falsch. Wähle „Registrieren“, um hier einmalig ein Testkonto anzulegen."
            #else
            return "E-Mail-Adresse oder Passwort ist nicht korrekt."
            #endif
        case .invalidEmail:
            return "Bitte prüfe deine E-Mail-Adresse."
        case .emailAlreadyInUse:
            return "Für diese E-Mail-Adresse gibt es bereits ein Konto. Bitte melde dich an."
        case .weakPassword:
            return "Wähle bitte ein stärkeres Passwort mit mindestens sechs Zeichen."
        case .networkError:
            return "Firebase ist gerade nicht erreichbar. Prüfe deine Verbindung und versuche es erneut."
        case .tooManyRequests:
            return "Zu viele Versuche hintereinander. Warte kurz und probiere es dann erneut."
        case .userDisabled:
            return "Dieses Konto wurde deaktiviert."
        default:
            return error.localizedDescription
        }
    }
}
