import FirebaseFirestore
import Foundation

/// Public data deliberately limited to an opted-in social identity and the comment text.
struct SocialPostComment: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var authorUid: String
    var author: SocialPersonIdentity
    var body: String
    var createdAt: Timestamp
    var updatedAt: Timestamp
}
