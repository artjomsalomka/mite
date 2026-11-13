import FirebaseFirestore
import Foundation

enum GroupEventStatus: String, Codable {
    case planned
    case cancelled
}

enum GroupEventAttendance: String, Codable, CaseIterable {
    case invited
    case going
    case maybe
    case declined

    var title: String {
        switch self {
        case .invited: return "Offen"
        case .going: return "Dabei"
        case .maybe: return "Vielleicht"
        case .declined: return "Abgesagt"
        }
    }
}

struct GroupEventParticipant: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String
    var handle: String
    var avatarPath: String?
    var status: GroupEventAttendance
    var id: String { uid }
}

struct GroupEventPlanStep: Codable, Equatable, Identifiable {
    var id: String
    var title: String
}

struct GroupEvent: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var creatorUid: String
    var creator: SocialPersonIdentity
    var title: String
    var city: String
    var cityNormalized: String
    var note: String
    /// A small, editable representation of a generated group route. Older manually-created
    /// events simply omit this and continue to render from their note/title.
    var planSteps: [GroupEventPlanStep]?
    /// A single editorial image for the plan. It is intentionally separate from a later social
    /// post, so a plan can feel tangible before anyone decides to publish the moment.
    var coverImagePath: String?
    /// The generated route image is the editorial fallback until the organiser deliberately
    /// uploads a personal cover. Keeping both values means a plan never falls back to a generic
    /// placeholder while an own image remains an explicit, reversible choice.
    var coverLicensedImage: LicensedImage?
    var scheduledAt: Timestamp
    var status: GroupEventStatus
    var participants: [GroupEventParticipant]
    var participantUids: [String]
    /// Per-person inbox cursor. Optional keeps all existing events readable.
    var readAtByUid: [String: Timestamp]?
    var createdAt: Timestamp
    var updatedAt: Timestamp

    func attendance(for uid: String) -> GroupEventAttendance? {
        participants.first(where: { $0.uid == uid })?.status
    }

    func isUnread(for uid: String, latestMessageAt: Date?) -> Bool {
        if attendance(for: uid) == .invited { return true }
        guard let latestMessageAt else { return false }
        guard let readAt = readAtByUid?[uid]?.dateValue() else { return true }
        return latestMessageAt > readAt
    }
}
