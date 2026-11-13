import FirebaseFirestore
import Foundation

/// A lightweight inbox projection: each event gets only one listener for its newest message.
/// Opening a thread still uses `GroupEventChatService` for the full private conversation.
@MainActor
final class GroupEventConversationStore: ObservableObject {
    @Published private(set) var latestMessages: [String: GroupEventChatMessage] = [:]

    private var listeners: [String: ListenerRegistration] = [:]
    private var generations: [String: UUID] = [:]

    deinit { listeners.values.forEach { $0.remove() } }

    func startListening(events: [GroupEvent]) {
        let activeIDs = Set(events.compactMap(\.id))
        let obsoleteIDs = listeners.keys.filter { !activeIDs.contains($0) }
        for eventID in obsoleteIDs {
            listeners[eventID]?.remove()
            listeners[eventID] = nil
            generations[eventID] = nil
            latestMessages[eventID] = nil
        }
        for eventID in activeIDs where listeners[eventID] == nil {
            let generation = UUID()
            generations[eventID] = generation
            listeners[eventID] = Firestore.firestore()
                .collection("groupEvents").document(eventID).collection("messages")
                .order(by: "createdAt", descending: true).limit(to: 1)
                .addSnapshotListener { [weak self] snapshot, _ in
                    let message = snapshot?.documents.first.flatMap { try? $0.data(as: GroupEventChatMessage.self) }
                    Task { @MainActor in
                        guard let self, self.generations[eventID] == generation else { return }
                        self.latestMessages[eventID] = message
                    }
                }
        }
    }

    func latestMessage(for event: GroupEvent) -> GroupEventChatMessage? {
        guard let id = event.id else { return nil }
        return latestMessages[id]
    }
}
