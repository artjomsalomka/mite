import Foundation
import FirebaseFirestore

enum CoupleStatus: String, Codable {
    case pending
    case active
}

struct CoupleMember: Codable, Equatable {
    var uid: String
    var displayName: String
    var joinedAt: Timestamp
    /// Snapshot used for an immediate, no-extra-query avatar stack. Older couple documents
    /// decode this as `nil` and fall back to an initials avatar.
    var avatarPath: String?
}

/// Mirrors `couples/{coupleId}` in Firestore. Lifecycle (create/join) is mutated only via
/// Cloud Functions — see CoupleService — never written to directly by the client.
struct Couple: Codable, Identifiable {
    @DocumentID var id: String?
    var status: CoupleStatus
    var inviteCode: String
    var createdByUid: String
    var createdAt: Timestamp
    var memberUids: [String]
    var members: [CoupleMember]
}
