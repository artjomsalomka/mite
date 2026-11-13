import FirebaseFirestore
import Foundation

/// Minimal private message shape for a confirmed match. There are intentionally no attachment,
/// contact-card or location fields in this model.
struct SingleChatMessage: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var senderUid: String
    var body: String
    var createdAt: Timestamp
}
