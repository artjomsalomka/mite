import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class PersonProfileService: ObservableObject {
    @Published private(set) var profile: PersonProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var listener: ListenerRegistration?

    deinit { listener?.remove() }

    func startListening(uid: String) {
        listener?.remove()
        isLoading = true
        errorMessage = nil
        listener = Firestore.firestore().collection("personProfiles").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        print("⚠️ person profile listener error: \(error)")
                        self.errorMessage = "Dein öffentliches Profil konnte nicht geladen werden."
                        return
                    }
                    self.profile = try? snapshot?.data(as: PersonProfile.self)
                }
            }
    }

    func save(displayName: String, handle: String, bio: String, city: String, isDiscoverable: Bool, avatarPath: String?) async throws {
        let callable = Functions.functions().httpsCallable("updatePersonProfile")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call([
                "displayName": displayName,
                "handle": handle,
                "bio": bio,
                "city": city,
                "isDiscoverable": isDiscoverable,
                "avatarPath": (avatarPath as Any?) ?? NSNull(),
            ])
        }
    }
}

@MainActor
final class PersonDirectoryStore: ObservableObject {
    @Published private(set) var profiles: [PersonProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var searchTask: Task<Void, Never>?
    private var token = UUID()

    deinit { searchTask?.cancel() }

    func search(_ text: String, excluding uid: String? = nil, immediate: Bool = false) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newToken = UUID()
        token = newToken
        isLoading = true
        errorMessage = nil
        searchTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(240)) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await Self.fetch(query: query)
                guard !Task.isCancelled, let self, self.token == newToken else { return }
                self.profiles = result.filter { $0.uid != uid }
                PBStorageImagePrefetcher.preload(paths: self.profiles.compactMap { profile in
                    guard let path = profile.avatarPath, !path.isEmpty else { return nil }
                    return path
                })
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.token == newToken else { return }
                self.profiles = []
                self.isLoading = false
                self.errorMessage = "Personen konnten gerade nicht geladen werden."
            }
        }
    }

    private static func fetch(query: String) async throws -> [PersonProfile] {
        let base = Firestore.firestore().collection("personProfiles")
            .whereField("isDiscoverable", isEqualTo: true)
        if query.isEmpty {
            let snapshot = try await base.order(by: "updatedAt", descending: true).limit(to: 36).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: PersonProfile.self) }
        }
        let handles = base.order(by: "handleNormalized")
            .start(at: [query]).end(at: [query + "\u{f8ff}"]).limit(to: 24)
        let names = base.order(by: "displayNameNormalized")
            .start(at: [query]).end(at: [query + "\u{f8ff}"]).limit(to: 24)
        async let handleResult = handles.getDocuments()
        async let nameResult = names.getDocuments()
        let snapshots = try await [handleResult, nameResult]
        var unique: [String: PersonProfile] = [:]
        for snapshot in snapshots {
            for document in snapshot.documents {
                if let profile = try? document.data(as: PersonProfile.self) { unique[profile.uid] = profile }
            }
        }
        return unique.values.sorted { $0.handle < $1.handle }
    }
}
