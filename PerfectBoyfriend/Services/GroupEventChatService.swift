import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class GroupEventChatService: ObservableObject {
    @Published private(set) var messages: [GroupEventChatMessage] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var listenerGeneration = UUID()

    func startListening(eventId: String) {
        stopListening()
        let generation = listenerGeneration
        guard !eventId.isEmpty else { return }
        listener = Firestore.firestore().collection("groupEvents").document(eventId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == generation else { return }
                    if let error {
                        self.errorMessage = "Planraum konnte nicht geladen werden: \(error.localizedDescription)"
                        return
                    }
                    self.messages = snapshot?.documents.compactMap { try? $0.data(as: GroupEventChatMessage.self) } ?? []
                    self.errorMessage = nil
                }
            }
    }

    @discardableResult
    func send(eventId: String, body: String) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return await call("sendGroupEventMessage", data: ["eventId": eventId, "body": text])
    }

    @discardableResult
    func proposeTime(eventId: String, scheduledAt: Date, note: String) async -> Bool {
        await call("proposeGroupEventTime", data: [
            "eventId": eventId,
            "scheduledAt": ISO8601DateFormatter().string(from: scheduledAt),
            "body": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }

    @discardableResult
    func proposeStep(eventId: String, stepID: String, title: String, note: String) async -> Bool {
        await call("proposeGroupEventStep", data: [
            "eventId": eventId,
            "stepId": stepID,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }

    @discardableResult
    func acceptTimeProposal(eventId: String, messageId: String) async -> Bool {
        await call("acceptGroupEventTimeProposal", data: ["eventId": eventId, "messageId": messageId])
    }

    @discardableResult
    func acceptStepProposal(eventId: String, messageId: String) async -> Bool {
        await call("acceptGroupEventStepProposal", data: ["eventId": eventId, "messageId": messageId])
    }

    func stopListening() {
        listenerGeneration = UUID()
        listener?.remove()
        listener = nil
        messages = []
        errorMessage = nil
    }

    deinit { listener?.remove() }

    private func call(_ name: String, data: [String: Any]) async -> Bool {
        guard !isSending else { return false }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let callable = Functions.functions().httpsCallable(name)
            _ = try await withTimeout(seconds: 15) { try await callable.call(data) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
