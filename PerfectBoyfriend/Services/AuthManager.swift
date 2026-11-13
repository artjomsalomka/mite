import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import UIKit

/// Wraps Firebase Auth (email/password + Sign in with Apple) and keeps the signed-in user's
/// `AppUser` Firestore doc in sync via a live listener, so RootView can branch on `coupleId`
/// without every screen re-fetching it.
@MainActor
final class AuthManager: NSObject, ObservableObject {
    enum AuthError: LocalizedError {
        case missingAppleCredential
        case missingIdentityToken
        case nonceMismatch
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .missingAppleCredential: return "Sign in with Apple lieferte keine gültigen Anmeldedaten."
            case .missingIdentityToken: return "Sign in with Apple lieferte kein Identity-Token."
            case .nonceMismatch: return "Sicherheitsprüfung fehlgeschlagen — bitte erneut versuchen."
            case .notSignedIn: return "Bitte melde dich erneut an."
            }
        }
    }

    @Published private(set) var firebaseUser: FirebaseAuth.User?
    @Published private(set) var appUser: AppUser?
    @Published private(set) var isLoading = true
    @Published private(set) var isEmailVerified = false
    /// A recoverable connection state for the app-profile listener. Keeping this separate from
    /// `isLoading` prevents RootView from mistaking an unloaded profile for a new account.
    @Published private(set) var profileLoadError: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var userDocListener: ListenerRegistration?
    private var profileInitialLoadTask: Task<Void, Never>?
    private var profileListeningSession: UUID?
    private var isRepairingMissingUserDocument = false
    private var currentAppleNonce: String?
    private var appleSignInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    override init() {
        super.init()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.handleAuthStateChange(user: user)
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        userDocListener?.remove()
        profileInitialLoadTask?.cancel()
    }

    private func handleAuthStateChange(user: FirebaseAuth.User?) {
        firebaseUser = user
        isEmailVerified = user?.isEmailVerified ?? false
        userDocListener?.remove()
        profileInitialLoadTask?.cancel()
        userDocListener = nil
        profileInitialLoadTask = nil
        profileListeningSession = nil
        isRepairingMissingUserDocument = false
        profileLoadError = nil

        guard let user else {
            appUser = nil
            isLoading = false
            return
        }

        appUser = nil
        isLoading = true
        let session = UUID()
        profileListeningSession = session
        profileInitialLoadTask = Task { @MainActor [weak self] in
            do {
                // A restored Keychain user may have an invalid refresh token after a password
                // change or emulator import. Validate it before opening Firestore's watch stream.
                _ = try await withTimeout(seconds: 12) {
                    try await user.getIDToken(forcingRefresh: true)
                }
                guard let self, !Task.isCancelled, self.profileListeningSession == session else { return }
                self.startProfileListener(user: user, session: session)
            } catch {
                guard let self, !Task.isCancelled, self.profileListeningSession == session else { return }
                let code = AuthErrorCode(rawValue: (error as NSError).code)
                NSLog("Session validation failed: %@ / %ld", (error as NSError).domain, (error as NSError).code)
                if code == .userTokenExpired || code == .invalidUserToken || code == .userNotFound || code == .userDisabled || Self.isInvalidEmulatorSession(error) {
                    do { try self.signOut() }
                    catch {
                        self.profileLoadError = "Bitte melde dich erneut an."
                        self.isLoading = false
                    }
                } else {
                    self.profileLoadError = "Deine Anmeldung konnte nicht bestätigt werden. Versuche es erneut oder melde dich neu an."
                    self.isLoading = false
                }
            }
        }
    }

    private func startProfileListener(user: FirebaseAuth.User, session: UUID) {
        userDocListener = Firestore.firestore().collection("users").document(user.uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.firebaseUser?.uid == user.uid, self.profileListeningSession == session else { return }
                    self.profileInitialLoadTask?.cancel()
                    if let error {
                        print("⚠️ users/\(user.uid) listener error: \(error)")
                        self.profileLoadError = "Dein Profil konnte gerade nicht geladen werden. Prüfe die Verbindung und versuche es erneut."
                        self.isLoading = false
                        return
                    }

                    guard let snapshot, snapshot.exists else {
                        self.repairUserDocumentIfNeeded(for: user)
                        return
                    }

                    self.isRepairingMissingUserDocument = false
                    self.appUser = try? snapshot.data(as: AppUser.self)
                    if self.appUser == nil {
                        self.profileLoadError = "Dein Profil konnte nicht gelesen werden. Bitte versuche es erneut."
                    } else {
                        self.profileLoadError = nil
                    }
                    self.isLoading = false
                }
            }

        // Fallback so a stalled first connection to Firestore's realtime channel (no cache yet
        // for a brand-new uid, and the network round-trip never completes) can't leave the whole
        // app stuck behind RootView's bare ProgressView forever with zero error ever surfacing —
        // the same class of hang already seen and fixed for SavedDateService's one-shot writes,
        // but this call site is a long-lived listener, not a single awaited call, so it needs its
        // own bounded fallback rather than `withTimeout`.
        profileInitialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.profileListeningSession == session,
                self.firebaseUser?.uid == user.uid,
                self.isLoading
            else { return }
            print("⚠️ users/\(user.uid) listener never fired within 10s — unblocking isLoading")
            self.profileLoadError = "Die Verbindung zu deinem Profil dauert zu lange. Bitte versuche es erneut."
            self.isLoading = false
        }
    }

    /// The emulator returns INVALID_REFRESH_TOKEN for a removed/imported account. This SDK
    /// version wraps that specific response in an internal error instead of invalidUserToken.
    private static func isInvalidEmulatorSession(_ error: Error) -> Bool {
        #if DEBUG
        var current: NSError? = error as NSError
        for _ in 0..<4 {
            guard let value = current else { break }
            if let response = value.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any] {
                let nested = response["error"] as? [String: Any]
                let message = (response["message"] as? String) ?? (nested?["message"] as? String) ?? (response["error"] as? String)
                if message == "INVALID_REFRESH_TOKEN" { return true }
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        #endif
        return false
    }

    /// Existing sessions can outlive a reset or switch of the local Firestore emulator. In that
    /// case Firebase Auth still knows the user, while `users/{uid}` no longer exists. Recreate
    /// the small app profile once so the normal couple-creation flow can continue.
    private func repairUserDocumentIfNeeded(for user: FirebaseAuth.User) {
        guard !isRepairingMissingUserDocument else { return }
        isRepairingMissingUserDocument = true

        Task { @MainActor [weak self] in
            guard let self, self.firebaseUser?.uid == user.uid else { return }
            defer { self.isRepairingMissingUserDocument = false }

            do {
                try await self.createUserDocumentIfNeeded(
                    uid: user.uid,
                    displayName: self.recoveryDisplayName(for: user),
                    email: user.email,
                    provider: self.authProvider(for: user)
                )
            } catch {
                print("⚠️ users/\(user.uid) repair failed: \(error)")
                self.profileLoadError = "Dein Profil konnte nicht wiederhergestellt werden. Bitte versuche es erneut."
                self.isLoading = false
            }
        }
    }

    private func recoveryDisplayName(for user: FirebaseAuth.User) -> String {
        let suppliedName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !suppliedName.isEmpty {
            return suppliedName
        }

        if let emailPrefix = user.email?.split(separator: "@").first, !emailPrefix.isEmpty {
            return String(emailPrefix)
        }

        return "Neues Mitglied"
    }

    private func authProvider(for user: FirebaseAuth.User) -> AuthProviderKind {
        user.providerData.contains { $0.providerID == "apple.com" } ? .apple : .password
    }

    // MARK: - Email/Password

    func signUp(email: String, password: String, displayName: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await withTimeout(seconds: 15) {
            try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
        }
        try await createUserDocumentIfNeeded(uid: result.user.uid, displayName: displayName, email: cleanEmail, provider: .password)
        // Registration remains successful even if the delivery provider is temporarily
        // unavailable. The same action is always available again in Konto & Sicherheit.
        try? await withTimeout(seconds: 12) {
            try await result.user.sendEmailVerification()
        }
    }

    func signIn(email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try await withTimeout(seconds: 15) {
            try await Auth.auth().signIn(withEmail: cleanEmail, password: password)
        }
    }

    func sendPasswordReset(email: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else { throw AccountActionError.missingEmail }
        try await withTimeout(seconds: 15) {
            try await Auth.auth().sendPasswordReset(withEmail: cleanEmail)
        }
    }

    func sendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await withTimeout(seconds: 15) {
            try await user.sendEmailVerification()
        }
    }

    func refreshEmailVerificationState() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await withTimeout(seconds: 15) {
            try await user.reload()
        }
        isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async throws {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce

        let credential = try await requestAppleCredential(hashedNonce: Self.sha256(nonce))

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.missingIdentityToken
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let result = try await withTimeout(seconds: 15) {
            try await Auth.auth().signIn(with: firebaseCredential)
        }

        let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        try await createUserDocumentIfNeeded(
            uid: result.user.uid,
            displayName: displayName.isEmpty ? "Neues Mitglied" : displayName,
            email: credential.email ?? result.user.email,
            provider: .apple
        )
    }

    private func requestAppleCredential(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.appleSignInContinuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Shared

    private func createUserDocumentIfNeeded(uid: String, displayName: String, email: String?, provider: AuthProviderKind) async throws {
        // Wrapped in a timeout for the same reason as SavedDateService's writes: these Firestore
        // calls have no built-in timeout, and a stalled connection here would otherwise hang the
        // sign-in/sign-up spinner forever with no error ever surfacing.
        try await withTimeout(seconds: 15) {
            let docRef = Firestore.firestore().collection("users").document(uid)
            let existing = try await docRef.getDocument()
            guard !existing.exists else { return }
            let newUser = AppUser.newUser(uid: uid, displayName: displayName, email: email, authProvider: provider)
            // Firestore's Codable `setData(from:)` overload is synchronous: it only stages the
            // mutation locally, even when it is written with `await`. Encode first and call the
            // async dictionary overload so the onboarding flow waits for the emulator/server
            // acknowledgement and can surface a real rules or network failure.
            let data = try Firestore.Encoder().encode(newUser)
            try await docRef.setData(data)
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// The destructive work happens in a callable Function so profile documents, storage files,
    /// shared-couple data, and the Firebase Auth account cannot drift apart.
    func deleteOwnAccount() async throws {
        guard firebaseUser != nil else { throw AuthError.notSignedIn }
        let callable = Functions.functions().httpsCallable("deleteOwnAccount")
        _ = try await withTimeout(seconds: 30) {
            try await callable.call([:])
        }
        try? Auth.auth().signOut()
    }

    func disconnectCouple() async throws {
        guard firebaseUser != nil else { throw AuthError.notSignedIn }
        let callable = Functions.functions().httpsCallable("disconnectCouple")
        _ = try await withTimeout(seconds: 30) {
            try await callable.call([:])
        }
    }

    /// Restarts the listener after a transient Firestore or local-emulator interruption without
    /// logging the person out or routing them to the account-type choice prematurely.
    func retryProfileLoad() {
        guard let firebaseUser else { return }
        handleAuthStateChange(user: firebaseUser)
    }

    /// This only chooses the immediate product context. The authenticated person keeps the same
    /// user profile either way; a later couple connection is performed by the callable pairing
    /// flow and never by exposing `coupleId` for direct client writes.
    func chooseAccountMode(_ mode: AccountMode) async throws {
        guard let uid = firebaseUser?.uid else {
            throw AuthError.notSignedIn
        }
        try await withTimeout(seconds: 15) {
            try await Firestore.firestore().collection("users").document(uid)
                .updateData([
                    "accountMode": mode.rawValue,
                    "datingEnabled": mode == .single,
                ])
        }
    }

    /// Personal identity is updated through a callable Function rather than broad client-side
    /// Firestore permissions. When the person belongs to a couple, the server refreshes that
    /// member snapshot atomically so the shared avatar stack never goes stale.
    func updatePersonalProfile(displayName: String, avatarPath: String?) async throws {
        guard firebaseUser != nil else {
            throw AuthError.notSignedIn
        }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw ProfileUpdateError.missingDisplayName
        }

        let payload: [String: Any] = [
            "displayName": cleanName,
            "avatarPath": avatarPath ?? NSNull(),
        ]
        let callable = Functions.functions().httpsCallable("updatePersonalProfile")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(payload)
        }
    }

    // MARK: - Nonce helpers (Apple's documented Sign in with Apple + Firebase replay-protection pattern)

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "Unable to generate nonce.")
            randomBytes.forEach { byte in
                if remainingLength == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private enum ProfileUpdateError: LocalizedError {
    case missingDisplayName

    var errorDescription: String? {
        switch self {
        case .missingDisplayName: return "Bitte gib einen Namen ein."
        }
    }
}

private enum AccountActionError: LocalizedError {
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingEmail: return "Bitte gib deine E-Mail-Adresse ein."
        }
    }
}

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { appleSignInContinuation = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            appleSignInContinuation?.resume(throwing: AuthError.missingAppleCredential)
            return
        }
        appleSignInContinuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { appleSignInContinuation = nil }
        appleSignInContinuation?.resume(throwing: error)
    }
}

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
