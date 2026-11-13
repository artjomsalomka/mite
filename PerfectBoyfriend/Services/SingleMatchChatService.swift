import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class SingleMatchChatService: ObservableObject {
    @Published private(set) var messages: [SingleChatMessage] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?

    func startListening(matchId: String) {
        listener?.remove()
        listener = Firestore.firestore()
            .collection("singleMatches").document(matchId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.errorMessage = "Chat konnte nicht geladen werden: \(error.localizedDescription)"
                        return
                    }
                    self.messages = snapshot?.documents.compactMap { try? $0.data(as: SingleChatMessage.self) } ?? []
                }
            }
    }

    @discardableResult
    func send(matchId: String, body: String) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }

        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let callable = Functions.functions().httpsCallable("sendSingleMessage")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(["matchId": matchId, "body": trimmedBody])
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markRead(matchId: String) async {
        do {
            let callable = Functions.functions().httpsCallable("markSingleMatchRead")
            _ = try await withTimeout(seconds: 10) { try await callable.call(["matchId": matchId]) }
        } catch {
            // Reading the chat remains available offline; the next foreground refresh retries.
            print("⚠️ single match read cursor failed: \(error)")
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }
}
