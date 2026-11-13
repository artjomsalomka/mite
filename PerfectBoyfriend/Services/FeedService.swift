import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class FeedService: ObservableObject {
    private struct ViewerSocialState: Sendable {
        let followingCoupleIds: Set<String>
        let likedPostIds: Set<String>
        let savedPostIds: Set<String>
    }

    enum ReactionKind: String {
        case like
        case save
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case functionsError(FunctionsErrorCode, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Die Antwort konnte nicht verarbeitet werden."
            case .functionsError(let code, let message):
                switch code {
                case .unauthenticated: return "Bitte melde dich erneut an."
                case .permissionDenied: return "Diese Aktion ist nicht erlaubt."
                case .notFound: return "Dieser Beitrag ist nicht mehr verfügbar."
                case .invalidArgument: return message
                default: return "Etwas ist schiefgelaufen: \(message)"
                }
            }
        }
    }

    @Published private(set) var posts: [DiscoverablePost] = []
    @Published private(set) var followedCoupleIds: Set<String> = []
    @Published private(set) var likedPostIds: Set<String> = []
    @Published private(set) var savedPostIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    @Published var actionError: String?

    private var publicPosts: [DiscoverablePost] = []
    private var followingPosts: [DiscoverablePost] = []
    private var publicListener: ListenerRegistration?
    private var followingListener: ListenerRegistration?
    private var stateRefreshTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?
    private var viewerUid: String?
    private var viewerCoupleId: String?
    private var pendingInitialSnapshots = 0
    private var listeningSession: UUID?

    func startListening(viewerUid: String, coupleId: String? = nil) {
        stopListening()
        let session = UUID()
        self.viewerUid = viewerUid
        viewerCoupleId = coupleId
        listeningSession = session
        isLoading = true
        loadErrorMessage = nil
        pendingInitialSnapshots = coupleId == nil ? 1 : 2

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.listeningSession == session,
                self.isLoading
            else { return }

            self.pendingInitialSnapshots = 0
            self.isLoading = false
            self.loadErrorMessage = "Date-Momente konnten nicht geladen werden."
        }

        // A visibility-only equality query uses the built-in single-field index. Drafts are
        // always private, so it cannot return an unpublished post.
        publicListener = Firestore.firestore().collection("posts")
            .whereField("visibility", isEqualTo: SocialPostVisibility.public.rawValue)
            .order(by: "publishedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.resolveInitialSnapshot()
                    if let error {
                        print("⚠️ public feed listener error: \(error)")
                        self.loadErrorMessage = "Date-Momente konnten nicht geladen werden."
                        return
                    }
                    self.publicPosts = (snapshot?.documents.compactMap { document in
                        guard let post = try? document.data(as: SocialPost.self), post.status == .published else { return nil }
                        return DiscoverablePost(post: post)
                    } ?? [])
                    self.rebuildFeed()
                }
            }

        if let coupleId {
            followingListener = Firestore.firestore().collection("couples").document(coupleId).collection("feedItems")
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self, self.listeningSession == session else { return }
                        self.resolveInitialSnapshot()
                        if let error {
                            print("⚠️ following feed listener error: \(error)")
                            self.loadErrorMessage = "Date-Momente konnten nicht geladen werden."
                            return
                        }
                        self.followingPosts = (snapshot?.documents.compactMap { document in
                            guard let item = try? document.data(as: FeedItem.self) else { return nil }
                            return DiscoverablePost(feedItem: item)
                        } ?? [])
                        self.rebuildFeed()
                    }
                }
        }
    }

    func toggleFollow(targetCoupleId: String) async {
        guard targetCoupleId != viewerCoupleId else { return }
        let functionName = followedCoupleIds.contains(targetCoupleId) ? "unfollowCouple" : "followCouple"
        do {
            let callable = Functions.functions().httpsCallable(functionName)
            let following = try await withTimeout(seconds: 15) {
                let result = try await callable.call(["targetCoupleId": targetCoupleId])
                guard let data = result.data as? [String: Any], let isFollowing = data["isFollowing"] as? Bool else {
                    throw ServiceError.invalidResponse
                }
                return isFollowing
            }
            if following {
                followedCoupleIds.insert(targetCoupleId)
            } else {
                followedCoupleIds.remove(targetCoupleId)
            }
        } catch {
            actionError = mapped(error).localizedDescription
        }
    }

    func toggleReaction(post: DiscoverablePost, kind: ReactionKind) async {
        do {
            let callable = Functions.functions().httpsCallable("togglePostReaction")
            let isActive = try await withTimeout(seconds: 15) {
                let result = try await callable.call(["postId": post.id, "kind": kind.rawValue])
                guard let data = result.data as? [String: Any], let active = data["isActive"] as? Bool else {
                    throw ServiceError.invalidResponse
                }
                return active
            }
            switch kind {
            case .like:
                if isActive { likedPostIds.insert(post.id) } else { likedPostIds.remove(post.id) }
            case .save:
                if isActive { savedPostIds.insert(post.id) } else { savedPostIds.remove(post.id) }
            }
            // The public-post listener receives the server's counter update. Do not adjust the
            // displayed count here as well: depending on callback order that would add the same
            // reaction twice (the heart state itself remains immediate above).
        } catch {
            actionError = mapped(error).localizedDescription
        }
    }

    func stopListening() {
        publicListener?.remove()
        followingListener?.remove()
        stateRefreshTask?.cancel()
        initialLoadTask?.cancel()
        publicListener = nil
        followingListener = nil
        stateRefreshTask = nil
        initialLoadTask = nil
        viewerUid = nil
        viewerCoupleId = nil
        listeningSession = nil
        publicPosts = []
        followingPosts = []
        posts = []
        followedCoupleIds = []
        likedPostIds = []
        savedPostIds = []
        isLoading = false
        pendingInitialSnapshots = 0
        loadErrorMessage = nil
    }

    func retryLoading() {
        guard let viewerUid else { return }
        startListening(viewerUid: viewerUid, coupleId: viewerCoupleId)
    }

    /// Search results may contain couples without a current feed post. Refresh the caller's
    /// relationship set independently so their Follow button is still truthful.
    func refreshFollowingState() async {
        do {
            let state = try await viewerSocialState(postIds: [])
            followedCoupleIds = state.followingCoupleIds
        } catch {
            // Searching remains useful if the relationship-state refresh is temporarily down.
        }
    }

    deinit {
        publicListener?.remove()
        followingListener?.remove()
        stateRefreshTask?.cancel()
        initialLoadTask?.cancel()
    }

    private func resolveInitialSnapshot() {
        pendingInitialSnapshots = max(0, pendingInitialSnapshots - 1)
        isLoading = pendingInitialSnapshots > 0
        if !isLoading {
            initialLoadTask?.cancel()
        }
    }

    private func rebuildFeed() {
        guard let viewerUid else { return }
        // Follower projections supply follower-only posts; public posts take precedence when a
        // post appears in both streams so reaction counts stay freshest from the source document.
        var merged = Dictionary(uniqueKeysWithValues: followingPosts.map { ($0.id, $0) })
        publicPosts.forEach { merged[$0.id] = $0 }
        posts = Array(merged.values
            .filter { post in
                post.creator?.uid != viewerUid
                    && (viewerCoupleId == nil || post.ownerCoupleId != viewerCoupleId)
            }
            .sorted { $0.publishedAt.dateValue() > $1.publishedAt.dateValue() }
            .prefix(50))
        refreshViewerState()
    }

    private func refreshViewerState() {
        stateRefreshTask?.cancel()
        let postIds = posts.map(\.id)
        guard !postIds.isEmpty else {
            followedCoupleIds = []
            likedPostIds = []
            savedPostIds = []
            return
        }

        stateRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await self.viewerSocialState(postIds: postIds)
                guard !Task.isCancelled else { return }
                self.followedCoupleIds = state.followingCoupleIds
                self.likedPostIds = state.likedPostIds
                self.savedPostIds = state.savedPostIds
            } catch {
                guard !Task.isCancelled else { return }
                print("⚠️ viewer social state error: \(error)")
            }
        }
    }

    private func viewerSocialState(postIds: [String]) async throws -> ViewerSocialState {
        let callable = Functions.functions().httpsCallable("getViewerSocialState")
        do {
            return try await withTimeout(seconds: 15) {
                let result = try await callable.call(["postIds": postIds])
                guard let data = result.data as? [String: Any] else {
                    throw ServiceError.invalidResponse
                }
                return ViewerSocialState(
                    followingCoupleIds: Set(data["followingCoupleIds"] as? [String] ?? []),
                    likedPostIds: Set(data["likedPostIds"] as? [String] ?? []),
                    savedPostIds: Set(data["savedPostIds"] as? [String] ?? [])
                )
            }
        } catch {
            throw mapped(error)
        }
    }

    private func mapped(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else { return error }
        return ServiceError.functionsError(FunctionsErrorCode(rawValue: nsError.code) ?? .internal, nsError.localizedDescription)
    }
}
