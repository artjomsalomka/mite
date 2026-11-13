import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Own-post service. Feed delivery stays separate so a future discovery screen cannot
/// accidentally query a broad collection and weaken the post visibility model.
@MainActor
final class PostService: ObservableObject {
    enum ServiceError: LocalizedError {
        case invalidResponse
        case functionsError(FunctionsErrorCode, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Die Antwort konnte nicht verarbeitet werden."
            case .functionsError(let code, let message):
                switch code {
                case .failedPrecondition: return message
                case .permissionDenied: return "Du darfst diesen Beitrag nicht bearbeiten."
                case .unauthenticated: return "Bitte melde dich erneut an."
                case .invalidArgument: return message
                default: return "Etwas ist schiefgelaufen: \(message)"
                }
            }
        }
    }

    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?

    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningField: String?
    private var listeningOwnerID: String?
    private var listeningSession: UUID?

    func startListening(coupleId: String) {
        startListening(field: "ownerCoupleId", ownerID: coupleId)
    }

    func startListening(ownerUid: String) {
        // Personal posts retain the person's UID as their ownership namespace even if they
        // later join or leave a pair. Pair-owned history is deliberately not mixed in here.
        startListening(field: "ownerCoupleId", ownerID: ownerUid)
    }

    private func startListening(field: String, ownerID: String) {
        stopListening()
        let session = UUID()
        listeningField = field
        listeningOwnerID = ownerID
        listeningSession = session
        isLoading = true
        loadErrorMessage = nil

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.listeningSession == session,
                self.isLoading
            else { return }

            self.isLoading = false
            self.loadErrorMessage = "Eure Momente konnten nicht geladen werden."
        }

        listener = Firestore.firestore().collection("posts")
            .whereField(field, isEqualTo: ownerID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ own posts listener error: \(error)")
                        self.loadErrorMessage = "Eure Momente konnten nicht geladen werden."
                        return
                    }
                    self.posts = (snapshot?.documents.compactMap { try? $0.data(as: SocialPost.self) } ?? [])
                        .sorted { $0.createdAt.dateValue() > $1.createdAt.dateValue() }
                }
            }
    }

    func createAndPublish(
        sourceDateId: String?,
        sourceEventId: String? = nil,
        caption: String,
        visibility: SocialPostVisibility,
        city: String,
        categories: [String],
        media: [PostMediaDraft],
        ownerID: String,
        collaboratorUids: [String] = []
    ) async throws {
        let postId = try await createDraft(sourceDateId: sourceDateId, sourceEventId: sourceEventId, collaboratorUids: collaboratorUids)
        do {
            let uploadedMedia = try await ImageUploadService.uploadPostMedia(media, coupleId: ownerID, postId: postId)
            try await publish(
                postId: postId,
                caption: caption,
                visibility: visibility,
                city: city,
                categories: categories,
                imagePaths: uploadedMedia.filter { $0.kind == .image }.map(\.path),
                media: uploadedMedia
            )
        } catch {
            // A draft is private, but it is still removed on every failed composition. The
            // backend deletes the complete post image prefix, including a partial upload.
            try? await delete(postId: postId)
            throw error
        }
    }

    func delete(post: SocialPost) async throws {
        guard let postId = post.id else { return }
        try await delete(postId: postId)
    }

    /// `publishPost` is deliberately also the edit endpoint: it revalidates the current couple
    /// and updates follower-feed fan-out whenever visibility changes, without exposing a direct
    /// client write to the posts collection.
    func updateVisibility(of post: SocialPost, to visibility: SocialPostVisibility) async throws {
        guard let postId = post.id else { return }
        try await publish(
            postId: postId,
            caption: post.caption,
            visibility: visibility,
            city: post.city,
            categories: post.categories,
            imagePaths: post.imagePaths,
            media: post.media
        )
    }

    func stopListening() {
        listener?.remove()
        initialLoadTask?.cancel()
        listener = nil
        initialLoadTask = nil
        listeningField = nil
        listeningOwnerID = nil
        listeningSession = nil
        posts = []
        isLoading = false
        loadErrorMessage = nil
    }

    func retryLoading() {
        guard let listeningField, let listeningOwnerID else { return }
        startListening(field: listeningField, ownerID: listeningOwnerID)
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }

    private func createDraft(sourceDateId: String?, sourceEventId: String?, collaboratorUids: [String]) async throws -> String {
        let callable = Functions.functions().httpsCallable("createPostDraft")
        do {
            return try await withTimeout(seconds: 15) {
                let result = try await callable.call([
                    "sourceDateId": (sourceDateId as Any?) ?? NSNull(),
                    "sourceEventId": (sourceEventId as Any?) ?? NSNull(),
                    "collaboratorUids": collaboratorUids,
                ])
                guard let data = result.data as? [String: Any], let postId = data["postId"] as? String else {
                    throw ServiceError.invalidResponse
                }
                return postId
            }
        } catch {
            throw mapped(error)
        }
    }

    private func publish(
        postId: String,
        caption: String,
        visibility: SocialPostVisibility,
        city: String,
        categories: [String],
        imagePaths: [String],
        media: [SocialPostMedia]? = nil
    ) async throws {
        let callable = Functions.functions().httpsCallable("publishPost")
        var data: [String: Any] = [
            "postId": postId,
            "caption": caption,
            "visibility": visibility.rawValue,
            "city": city,
            "categories": categories,
            "imagePaths": imagePaths,
        ]
        if let media {
            data["media"] = media.map { item in
                var value: [String: Any] = ["path": item.path, "kind": item.kind.rawValue]
                if let thumbnailPath = item.thumbnailPath { value["thumbnailPath"] = thumbnailPath }
                return value
            }
        }
        let requestData = data
        do {
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(requestData)
            }
        } catch {
            throw mapped(error)
        }
    }

    private func delete(postId: String) async throws {
        let callable = Functions.functions().httpsCallable("deletePost")
        do {
            _ = try await withTimeout(seconds: 15) {
                try await callable.call(["postId": postId])
            }
        } catch {
            throw mapped(error)
        }
    }

    private func mapped(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else { return error }
        let code = FunctionsErrorCode(rawValue: nsError.code) ?? .internal
        return ServiceError.functionsError(code, nsError.localizedDescription)
    }
}
