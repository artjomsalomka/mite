import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class CoupleProfileService: ObservableObject {
    @Published private(set) var profile: CoupleProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?

    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningCoupleId: String?
    private var listeningSession: UUID?

    func startListening(coupleId: String) {
        stopListening()
        let session = UUID()
        listeningCoupleId = coupleId
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
            self.loadErrorMessage = "Euer gemeinsames Profil ist gerade nicht erreichbar."
        }

        listener = Firestore.firestore().collection("coupleProfiles").document(coupleId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ coupleProfiles/\(coupleId) listener error: \(error)")
                        self.loadErrorMessage = "Euer gemeinsames Profil ist gerade nicht erreichbar."
                        return
                    }
                    self.profile = try? snapshot?.data(as: CoupleProfile.self)
                }
            }
    }

    func save(draft: CoupleProfileDraft, coupleId: String) async throws {
        let data: [String: Any] = [
            "displayName": draft.displayName,
            "handle": draft.handle,
            "bio": draft.bio,
            "city": draft.city,
            "avatarPath": draft.avatarPath ?? NSNull(),
        ]
        let callable = Functions.functions().httpsCallable("updateCoupleProfile")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(data)
        }
    }

    func stopListening() {
        listener?.remove()
        initialLoadTask?.cancel()
        listener = nil
        initialLoadTask = nil
        listeningCoupleId = nil
        listeningSession = nil
        profile = nil
        isLoading = false
        loadErrorMessage = nil
    }

    func retryLoading() {
        guard let listeningCoupleId else { return }
        startListening(coupleId: listeningCoupleId)
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }
}
