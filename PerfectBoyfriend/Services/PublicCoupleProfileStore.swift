import FirebaseFirestore
import Foundation

/// Read-only store for another couple's intentionally public profile document. It never touches
/// private `couples` or `users` membership data.
@MainActor
final class PublicCoupleProfileStore: ObservableObject {
    @Published private(set) var profile: CoupleProfile?
    @Published private(set) var publicPosts: [SocialPost] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingPosts = true
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var postsErrorMessage: String?

    private var listener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private let coupleId: String
    private var listeningSession: UUID?

    init(coupleId: String) {
        self.coupleId = coupleId
        startListening()
    }

    func retryLoading() {
        startListening()
    }

    private func startListening() {
        listener?.remove()
        postsListener?.remove()
        initialLoadTask?.cancel()
        let session = UUID()
        listeningSession = session
        isLoading = true
        isLoadingPosts = true
        loadErrorMessage = nil
        postsErrorMessage = nil

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.listeningSession == session,
                self.isLoading
            else { return }

            self.isLoading = false
            self.loadErrorMessage = "Dieses Profil ist gerade nicht erreichbar."
        }

        listener = Firestore.firestore().collection("coupleProfiles").document(coupleId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ public couple profile listener error: \(error)")
                        self.loadErrorMessage = "Dieses Profil ist gerade nicht erreichbar."
                        return
                    }
                    self.profile = try? snapshot?.data(as: CoupleProfile.self)
                }
            }

        // A public profile intentionally exposes only public, published moments. Followers-only
        // posts stay in the per-follower feed projection; private couple history is never part
        // of this query or this screen.
        postsListener = Firestore.firestore().collection("posts")
            .whereField("ownerCoupleId", isEqualTo: coupleId)
            .whereField("visibility", isEqualTo: SocialPostVisibility.public.rawValue)
            .order(by: "publishedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.isLoadingPosts = false
                    if let error {
                        print("⚠️ public profile posts listener error: \(error)")
                        self.postsErrorMessage = "Öffentliche Momente konnten nicht geladen werden."
                        return
                    }
                    self.publicPosts = (snapshot?.documents.compactMap { document in
                        guard let post = try? document.data(as: SocialPost.self), post.status == .published else { return nil }
                        return post
                    } ?? [])
                }
            }
    }

    deinit {
        listener?.remove()
        postsListener?.remove()
        initialLoadTask?.cancel()
    }
}
