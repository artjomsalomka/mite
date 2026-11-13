import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// A private, person-owned index makes the bookmark useful beyond the feed where it was tapped.
/// The server returns IDs only after rechecking current visibility; Firestore remains the source
/// of truth for the actual Moment and its latest counters.
@MainActor
final class SavedMomentsStore: ObservableObject {
    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let callable = Functions.functions().httpsCallable("getSavedPostIds")
            let result = try await withTimeout(seconds: 15) { try await callable.call() }
            guard let data = result.data as? [String: Any], let postIDs = data["postIds"] as? [String] else {
                throw StoreError.invalidResponse
            }

            var loaded: [SocialPost] = []
            for postID in postIDs {
                let snapshot = try await Firestore.firestore().collection("posts").document(postID).getDocument()
                if let post = try? snapshot.data(as: SocialPost.self), post.status == .published {
                    loaded.append(post)
                }
            }
            posts = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum StoreError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "Gespeicherte Momente konnten nicht geladen werden." }
    }
}
