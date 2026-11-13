import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class CollaborationInboxService: ObservableObject {
    @Published private(set) var invitations: [SocialPost] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningUID: String?
    private var listeningSession: UUID?

    func startListening(uid: String) {
        listener?.remove()
        initialLoadTask?.cancel()
        let session = UUID()
        listeningUID = uid
        listeningSession = session
        isLoading = true
        errorMessage = nil
        listener = Firestore.firestore().collection("posts")
            .whereField("pendingCollaboratorUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ collaboration inbox listener error: \(error)")
                        self.errorMessage = "Einladungen konnten gerade nicht geladen werden."
                        return
                    }
                    self.invitations = snapshot?.documents.compactMap { try? $0.data(as: SocialPost.self) } ?? []
                }
            }

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  let self,
                  self.listeningSession == session,
                  self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Die Verbindung zu deinen Einladungen dauert zu lange."
        }
    }

    func retryLoading() {
        guard let listeningUID else { return }
        startListening(uid: listeningUID)
    }

    func respond(to post: SocialPost, accept: Bool) async throws {
        guard let postId = post.id else { return }
        let callable = Functions.functions().httpsCallable("respondToPostCollaboration")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(["postId": postId, "accept": accept])
        }
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }
}
