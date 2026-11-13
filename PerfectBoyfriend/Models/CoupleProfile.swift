import FirebaseFirestore
import Foundation

/// Intentionally public, sanitized representation of a couple. This is never derived by reading
/// `Couple` or `AppUser` client-side, because both also contain private membership/account data.
struct CoupleProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var coupleId: String
    var displayName: String
    var handle: String
    var bio: String
    var city: String
    var cityNormalized: String
    var avatarPath: String?
    var createdAt: Timestamp
    var updatedAt: Timestamp

    var socialAuthor: SocialPostAuthor {
        SocialPostAuthor(
            coupleId: coupleId,
            displayName: displayName,
            handle: handle,
            avatarPath: avatarPath
        )
    }
}

struct CoupleProfileDraft: Equatable {
    var displayName: String
    var handle: String
    var bio: String
    var city: String
    var avatarPath: String?

    init(profile: CoupleProfile) {
        displayName = profile.displayName
        handle = profile.handle
        bio = profile.bio
        city = profile.city
        avatarPath = profile.avatarPath
    }

    init(suggestedName: String, suggestedCity: String = "") {
        displayName = suggestedName
        handle = ""
        bio = ""
        city = suggestedCity
        avatarPath = nil
    }
}
