import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class SingleProfileService: ObservableObject {
    @Published private(set) var profile: SingleProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?

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
        profile = nil
        isLoading = true
        loadErrorMessage = nil
        listener = Firestore.firestore().collection("singleProfiles").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ singleProfiles/\(uid) listener error: \(error)")
                        self.loadErrorMessage = "Dein Single-Profil konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut."
                        return
                    }
                    self.profile = try? snapshot?.data(as: SingleProfile.self)
                }
            }

        // A missing document is a valid first-run state and normally resolves immediately. If
        // Firestore's stream never establishes (for example while a local emulator restarts),
        // surface a recoverable state instead of leaving the entire single flow on a spinner.
        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.listeningSession == session,
                self.isLoading
            else { return }
            print("⚠️ singleProfiles/\(uid) listener never fired within 10s")
            self.isLoading = false
            self.loadErrorMessage = "Die Verbindung zum Profil ist zu lange nicht verfügbar."
        }
    }

    func save(_ draft: SingleProfileDraft, avatarData: Data? = nil) async throws {
        guard let uid = listeningUID else { throw ProfileError.missingUser }
        var data: [String: Any] = [
            "displayName": draft.displayName,
            "city": draft.city,
            "bio": draft.bio,
            "age": draft.age,
            "preferredAgeMinimum": draft.preferredAgeMinimum,
            "preferredAgeMaximum": draft.preferredAgeMaximum,
            "interests": draft.interests,
            "budgetPreference": draft.budgetPreference.rawValue,
            "moods": draft.moods.map(\.rawValue),
            "isMatchingActive": draft.isMatchingActive,
        ]
        if let avatarData {
            data["avatarPath"] = try await ImageUploadService.uploadSingleProfileAvatar(avatarData, uid: uid)
        } else if draft.removesAvatar {
            data["avatarPath"] = NSNull()
        }
        let callable = Functions.functions().httpsCallable("updateSingleProfile")
        let requestData = data
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(requestData)
        }
    }

    private enum ProfileError: LocalizedError {
        case missingUser
        var errorDescription: String? { "Dein Profil ist gerade nicht eindeutig zugeordnet." }
    }

    func stopListening() {
        listener?.remove()
        initialLoadTask?.cancel()
        listener = nil
        initialLoadTask = nil
        listeningUID = nil
        listeningSession = nil
        profile = nil
        isLoading = false
        loadErrorMessage = nil
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }
}
