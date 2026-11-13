import FirebaseFirestore
import Foundation

@MainActor
final class PublicPersonProfileStore: ObservableObject {
    @Published private(set) var profile: PersonProfile?
    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingPosts = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var postsErrorMessage: String?

    private var profileListener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    private var collaboratorPostsListener: ListenerRegistration?
    private var creatorPosts: [SocialPost] = []
    private var collaboratorPosts: [SocialPost] = []
    private var initialLoadTask: Task<Void, Never>?
    private var postsInitialLoadTask: Task<Void, Never>?
    private let uid: String
    private var listeningSession: UUID?

    init(uid: String) {
        self.uid = uid
        startListening()
    }

    func retryLoading() {
        startListening()
    }

    private func startListening() {
        profileListener?.remove()
        postsListener?.remove()
        collaboratorPostsListener?.remove()
        initialLoadTask?.cancel()
        postsInitialLoadTask?.cancel()

        let session = UUID()
        listeningSession = session
        profile = nil
        posts = []
        creatorPosts = []
        collaboratorPosts = []
        isLoading = true
        isLoadingPosts = true
        errorMessage = nil
        postsErrorMessage = nil

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.listeningSession == session, self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Dieses Profil ist gerade nicht erreichbar."
        }
        postsInitialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.listeningSession == session, self.isLoadingPosts else { return }
            self.isLoadingPosts = false
            self.postsErrorMessage = "Öffentliche Momente konnten nicht geladen werden."
        }

        profileListener = Firestore.firestore().collection("personProfiles").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ public person profile listener error: \(error)")
                        self.errorMessage = "Dieses Profil ist gerade nicht erreichbar."
                        return
                    }
                    guard let snapshot, snapshot.exists else {
                        self.errorMessage = "Dieses Profil ist nicht mehr verfügbar."
                        return
                    }
                    guard let profile = try? snapshot.data(as: PersonProfile.self) else {
                        self.errorMessage = "Dieses Profil konnte nicht geladen werden."
                        return
                    }
                    self.profile = profile
                }
            }
        postsListener = Firestore.firestore().collection("posts")
            .whereField("creator.uid", isEqualTo: uid)
            .whereField("visibility", isEqualTo: SocialPostVisibility.public.rawValue)
            .order(by: "publishedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.postsInitialLoadTask?.cancel()
                    self.isLoadingPosts = false
                    if let error {
                        print("⚠️ public person creator posts listener error: \(error)")
                        self.postsErrorMessage = "Öffentliche Momente konnten nicht geladen werden."
                        return
                    }
                    self.creatorPosts = snapshot?.documents.compactMap { document in
                        guard let post = try? document.data(as: SocialPost.self), post.status == .published else { return nil }
                        return post
                    } ?? []
                    self.rebuildPosts()
                }
            }
        collaboratorPostsListener = Firestore.firestore().collection("posts")
            .whereField("acceptedCollaboratorUids", arrayContains: uid)
            .whereField("visibility", isEqualTo: SocialPostVisibility.public.rawValue)
            .order(by: "publishedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.postsInitialLoadTask?.cancel()
                    self.isLoadingPosts = false
                    if let error {
                        print("⚠️ public person collaborator posts listener error: \(error)")
                        self.postsErrorMessage = "Öffentliche Momente konnten nicht geladen werden."
                        return
                    }
                    self.collaboratorPosts = snapshot?.documents.compactMap { document in
                        guard let post = try? document.data(as: SocialPost.self), post.status == .published else { return nil }
                        return post
                    } ?? []
                    self.rebuildPosts()
                }
            }
    }

    private func rebuildPosts() {
        var unique = Dictionary(uniqueKeysWithValues: creatorPosts.compactMap { post in post.id.map { ($0, post) } })
        collaboratorPosts.forEach { if let id = $0.id { unique[id] = $0 } }
        posts = unique.values.sorted { ($0.publishedAt ?? $0.createdAt).dateValue() > ($1.publishedAt ?? $1.createdAt).dateValue() }
    }

    deinit {
        profileListener?.remove()
        postsListener?.remove()
        collaboratorPostsListener?.remove()
        initialLoadTask?.cancel()
        postsInitialLoadTask?.cancel()
    }
}
