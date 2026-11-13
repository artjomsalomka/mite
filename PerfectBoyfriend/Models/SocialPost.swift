import FirebaseFirestore
import Foundation

enum SocialPostVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case followers
    case `public`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: return "Nur Beteiligte"
        case .followers: return "Follower:innen"
        case .public: return "Öffentlich"
        }
    }

    var explanation: String {
        switch self {
        case .private: return "Nur du und bestätigte Mitwirkende sehen diesen Beitrag."
        case .followers: return "Nur Menschen, die dir folgen, können ihn sehen."
        case .public: return "Alle angemeldeten Menschen können ihn entdecken."
        }
    }

    var iconName: String {
        switch self {
        case .private: return "lock.fill"
        case .followers: return "person.2.fill"
        case .public: return "globe.europe.africa.fill"
        }
    }
}

enum SocialPostStatus: String, Codable {
    case draft
    case published
}

/// A post keeps the chosen order across photos and videos. Video entries deliberately carry a
/// still preview, so feeds stay calm and fast while the full clip only loads in the detail view.
enum SocialPostMediaKind: String, Codable, Equatable {
    case image
    case video
}

struct SocialPostMedia: Codable, Identifiable, Equatable {
    var path: String
    var kind: SocialPostMediaKind
    var thumbnailPath: String?

    var id: String { path }
    var previewPath: String { thumbnailPath ?? path }
}

struct SocialPostAuthor: Codable, Equatable {
    var coupleId: String
    var displayName: String
    var handle: String
    var avatarPath: String?
}

/// Mirrors `posts/{postId}`. The post itself contains only public/profile-safe author data;
/// membership data remains in the private couple and user documents.
struct SocialPost: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var ownerCoupleId: String
    /// New social posts are authored by a person. `ownerCoupleId` stays for date history and
    /// backwards-compatible follower delivery of older shared posts.
    var ownerUid: String?
    var status: SocialPostStatus
    var visibility: SocialPostVisibility
    var author: SocialPostAuthor
    var creator: SocialPersonIdentity?
    var collaborators: [PostCollaborator]?
    var pendingCollaboratorUids: [String]?
    var acceptedCollaboratorUids: [String]?
    var caption: String
    var city: String
    var cityNormalized: String
    var categories: [String]
    var imagePaths: [String]
    /// Ordered media for new posts. `imagePaths` remains for all existing moments and older
    /// clients, allowing the social feed to migrate without losing a single post.
    var media: [SocialPostMedia]?
    /// Editorial/demo imagery from an openly licensed source. User uploads remain in
    /// `imagePaths`; these references always carry source and licence attribution.
    var licensedImages: [LicensedImage]?
    var sourceDateId: String?
    var sourceEventId: String?
    var createdAt: Timestamp
    var publishedAt: Timestamp?
    var updatedAt: Timestamp
    var likesCount: Int
    var savesCount: Int
    var commentsCount: Int?

    var visiblePeople: [SocialPersonIdentity] {
        let accepted = (collaborators ?? []).filter { $0.status == .accepted }.map {
            SocialPersonIdentity(uid: $0.uid, displayName: $0.displayName, handle: $0.handle, avatarPath: $0.avatarPath)
        }
        let legacyAuthor = SocialPersonIdentity(
            uid: author.coupleId,
            displayName: author.displayName,
            handle: author.handle,
            avatarPath: author.avatarPath
        )
        return (creator.map { [$0] } ?? [legacyAuthor]) + accepted
    }

    var orderedMedia: [SocialPostMedia] {
        let uploadedMedia = media ?? []
        return uploadedMedia.isEmpty
            ? imagePaths.map { SocialPostMedia(path: $0, kind: .image, thumbnailPath: nil) }
            : uploadedMedia
    }

    var primaryPreviewPath: String? {
        orderedMedia.first?.previewPath
    }
}
