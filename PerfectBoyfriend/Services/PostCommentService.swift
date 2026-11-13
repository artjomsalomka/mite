import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class PostCommentService: ObservableObject {
    @Published private(set) var comments: [SocialPostComment] = []
    @Published private(set) var isLoading = true
    @Published var actionError: String?
    @Published var confirmationMessage: String?

    private let postID: String
    private var listener: ListenerRegistration?

    init(postID: String) {
        self.postID = postID
        listener = Firestore.firestore().collection("posts").document(postID).collection("comments")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        print("⚠️ post comment listener error: \(error)")
                        self.actionError = "Kommentare konnten nicht geladen werden."
                        return
                    }
                    self.comments = snapshot?.documents.compactMap { try? $0.data(as: SocialPostComment.self) } ?? []
                }
            }
    }

    func add(body: String) async {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        do {
            let callable = Functions.functions().httpsCallable("addPostComment")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(["postId": self.postID, "body": normalized])
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func delete(_ comment: SocialPostComment) async {
        guard let commentID = comment.id else { return }
        do {
            let callable = Functions.functions().httpsCallable("deletePostComment")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(["postId": self.postID, "commentId": commentID])
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func report(_ comment: SocialPostComment) async {
        guard let commentID = comment.id else { return }
        do {
            let callable = Functions.functions().httpsCallable("reportSocialProfile")
            _ = try await withTimeout(seconds: 15) {
                try await callable.call([
                    "targetUid": comment.authorUid,
                    "reason": "harassment",
                    "postId": self.postID,
                    "commentId": commentID,
                ])
            }
            confirmationMessage = "Der Kommentar wurde zur Prüfung gemeldet."
        } catch {
            actionError = error.localizedDescription
        }
    }

    deinit { listener?.remove() }
}
