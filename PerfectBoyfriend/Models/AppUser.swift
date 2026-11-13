import Foundation
import FirebaseFirestore

enum AuthProviderKind: String, Codable {
    case apple
    case password
}

/// `AccountMode` describes the last selected product context, never the person's identity.
/// Every authenticated person owns a `users/{uid}` document; a couple is an optional connection
/// through `coupleId`. Existing documents without this field remain valid.
enum AccountMode: String, Codable {
    case couple
    case single
}

enum VerificationStatus: String, Codable {
    case unverified
    case pending
    case verified
    case requiresInput = "requires_input"

    var label: String {
        switch self {
        case .unverified: return "Nicht verifiziert"
        case .pending: return "Wird geprüft"
        case .verified: return "Identität bestätigt"
        case .requiresInput: return "Erneut versuchen"
        }
    }
}

/// Mirrors `users/{uid}` in Firestore.
struct AppUser: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var email: String?
    var authProvider: AuthProviderKind
    var accountMode: AccountMode?
    var coupleId: String?
    /// Optional personal image. It deliberately belongs to the person, not the shared couple
    /// profile, so a connected pair can still show both people distinctly in the UI.
    var avatarPath: String?
    /// The matching area is opt-in and is switched off by the server as soon as a person joins a
    /// couple. Optional for a backwards-compatible read of existing emulator/production users.
    var datingEnabled: Bool?
    var dietaryDefault: [String]
    var verificationStatus: VerificationStatus?
    var verificationUpdatedAt: Timestamp?
    var createdAt: Timestamp
    var updatedAt: Timestamp

    var isDatingEnabled: Bool {
        (datingEnabled ?? (accountMode == .single)) && coupleId == nil
    }

    static func newUser(uid: String, displayName: String, email: String?, authProvider: AuthProviderKind) -> AppUser {
        let now = Timestamp(date: Date())
        return AppUser(
            id: uid,
            displayName: displayName,
            email: email,
            authProvider: authProvider,
            accountMode: nil,
            coupleId: nil,
            avatarPath: nil,
            datingEnabled: nil,
            dietaryDefault: [],
            verificationStatus: nil,
            verificationUpdatedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
