import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// A focused listener for a public Moment opened from a profile grid. Keeping this separate
/// from the feed prevents a full-screen detail from depending on whichever tab happened to load
/// it first, while reaction state remains scoped to the viewer's active couple on the server.
@MainActor
final class SocialPostDetailStore: ObservableObject {
    @Published private(set) var post: SocialPost?
    @Published private(set) var isLoading = true
    @Published private(set) var isLiked = false
    @Published private(set) var isSaved = false
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?

    private let postID: String
    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningSession: UUID?

    init(postID: String) {
        self.postID = postID
        startListening()
    }

    func retryLoading() {
        startListening()
    }

    private func startListening() {
        listener?.remove()
        initialLoadTask?.cancel()
        let session = UUID()
        listeningSession = session
        post = nil
        isLoading = true
        errorMessage = nil

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.listeningSession == session, self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Dieser Moment ist gerade nicht erreichbar."
        }

        listener = Firestore.firestore().collection("posts").document(postID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ post detail listener error: \(error)")
                        self.errorMessage = "Dieser Moment ist gerade nicht erreichbar."
                        return
                    }
                    guard let snapshot, snapshot.exists,
                          let post = try? snapshot.data(as: SocialPost.self) else {
                        self.errorMessage = "Dieser Moment ist nicht mehr verfügbar."
                        return
                    }
                    self.post = post
                }
            }
    }

    func refreshViewerReactionState() async {
        guard !postID.isEmpty else { return }
        do {
            let callable = Functions.functions().httpsCallable("getViewerSocialState")
            let result = try await withTimeout(seconds: 15) {
                try await callable.call(["postIds": [self.postID]])
            }
            guard let data = result.data as? [String: Any] else { return }
            isLiked = (data["likedPostIds"] as? [String] ?? []).contains(postID)
            isSaved = (data["savedPostIds"] as? [String] ?? []).contains(postID)
        } catch {
            // Reading the public Moment is still useful if the private reaction-state lookup is
            // temporarily unavailable, so the detail itself stays visible.
            print("⚠️ post detail reaction state error: \(error)")
        }
    }

    func toggleReaction(kind: FeedService.ReactionKind) async {
        do {
            let callable = Functions.functions().httpsCallable("togglePostReaction")
            let result = try await withTimeout(seconds: 15) {
                try await callable.call(["postId": self.postID, "kind": kind.rawValue])
            }
            guard let data = result.data as? [String: Any], let active = data["isActive"] as? Bool else { return }
            switch kind {
            case .like: isLiked = active
            case .save: isSaved = active
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reportPost(authorUID: String) async {
        do {
            let callable = Functions.functions().httpsCallable("reportSocialProfile")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call([
                    "targetUid": authorUID,
                    "reason": "other",
                    "postId": self.postID,
                ])
            }
            confirmationMessage = "Der Beitrag wurde zur Prüfung gemeldet."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func blockAuthor(_ authorUID: String) async -> Bool {
        do {
            let callable = Functions.functions().httpsCallable("blockSocialProfile")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(["targetUid": authorUID])
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }
}
