import FirebaseFirestore
import Foundation

/// Public, opt-in social identity. The private account document remains `users/{uid}`.
struct PersonProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var uid: String
    var displayName: String
    var handle: String
    var bio: String
    var city: String
    var cityNormalized: String
    var avatarPath: String?
    var isDiscoverable: Bool
    var followerCount: Int?
    var followingCount: Int?
    var linkedCoupleId: String?
    var createdAt: Timestamp
    var updatedAt: Timestamp

    var socialIdentity: SocialPersonIdentity {
        SocialPersonIdentity(uid: uid, displayName: displayName, handle: handle, avatarPath: avatarPath)
    }
}

struct SocialPersonIdentity: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String
    var handle: String
    var avatarPath: String?
    var id: String { uid }
}

enum PostCollaborationStatus: String, Codable {
    case pending
    case accepted
    case declined
}

struct PostCollaborator: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String
    var handle: String
    var avatarPath: String?
    var status: PostCollaborationStatus
    var id: String { uid }
}
