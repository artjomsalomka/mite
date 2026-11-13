import FirebaseFirestore
import Foundation

/// Private collaboration conversation attached to one group plan. The event itself remains the
/// source of truth; proposal messages merely make a potential time change discussable first.
enum GroupEventMessageKind: String, Codable {
    case text
    case timeProposal
    case stepProposal
}

enum GroupEventProposalStatus: String, Codable {
    case pending
    case accepted
}

struct GroupEventChatMessage: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var senderUid: String
    var sender: SocialPersonIdentity
    var kind: GroupEventMessageKind
    var body: String
    var proposedScheduledAt: Timestamp?
    var proposedStepID: String?
    var proposedStepTitle: String?
    var proposalStatus: GroupEventProposalStatus?
    var createdAt: Timestamp
}
