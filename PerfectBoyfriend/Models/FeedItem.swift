import FirebaseFirestore
import Foundation

/// Mirrors the server-maintained `couples/{coupleId}/feedItems/{postId}` projection. It contains
/// only enough information for a follower-safe feed card; the full post is never fetched through
/// an unrestricted query for follower-only visibility.
struct FeedItem: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var postId: String
    var ownerCoupleId: String
    var visibility: SocialPostVisibility
    var author: SocialPostAuthor
    var creator: SocialPersonIdentity?
    var collaborators: [PostCollaborator]?
    var caption: String
    var city: String
    var cityNormalized: String
    var categories: [String]
    var coverImagePath: String?
    var coverLicensedImage: LicensedImage?
    var imageCount: Int
    var likesCount: Int
    var savesCount: Int
    var commentsCount: Int?
    var publishedAt: Timestamp
}

/// Common display shape for both public-post documents and follower-safe feed projections.
struct DiscoverablePost: Identifiable, Equatable {
    let id: String
    let ownerCoupleId: String
    let visibility: SocialPostVisibility
    let author: SocialPostAuthor
    let creator: SocialPersonIdentity?
    let collaborators: [PostCollaborator]?
    let caption: String
    let city: String
    let categories: [String]
    let coverImagePath: String?
    let coverLicensedImage: LicensedImage?
    let imageCount: Int
    var likesCount: Int
    var savesCount: Int
    var commentsCount: Int?
    let publishedAt: Timestamp

    init(post: SocialPost) {
        id = post.id ?? ""
        ownerCoupleId = post.ownerCoupleId
        visibility = post.visibility
        author = post.author
        creator = post.creator
        collaborators = post.collaborators
        caption = post.caption
        city = post.city
        categories = post.categories
        coverImagePath = post.orderedMedia.first?.previewPath
        coverLicensedImage = post.licensedImages?.first
        imageCount = post.orderedMedia.count
        likesCount = post.likesCount
        savesCount = post.savesCount
        commentsCount = post.commentsCount
        publishedAt = post.publishedAt ?? post.createdAt
    }

    init(feedItem: FeedItem) {
        id = feedItem.postId
        ownerCoupleId = feedItem.ownerCoupleId
        visibility = feedItem.visibility
        author = feedItem.author
        creator = feedItem.creator
        collaborators = feedItem.collaborators
        caption = feedItem.caption
        city = feedItem.city
        categories = feedItem.categories
        coverImagePath = feedItem.coverImagePath
        coverLicensedImage = feedItem.coverLicensedImage
        imageCount = feedItem.imageCount
        likesCount = feedItem.likesCount
        savesCount = feedItem.savesCount
        commentsCount = feedItem.commentsCount
        publishedAt = feedItem.publishedAt
    }

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
}
