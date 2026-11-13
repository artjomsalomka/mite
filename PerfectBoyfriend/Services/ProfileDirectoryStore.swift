import FirebaseFirestore
import Foundation

/// Public-profile discovery intentionally queries only `coupleProfiles`: that collection contains
/// the small, sanitized projection created by the server and never exposes private couple data.
@MainActor
final class ProfileDirectoryStore: ObservableObject {
    @Published private(set) var profiles: [CoupleProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private var queryToken = UUID()

    deinit { searchTask?.cancel() }

    func loadDirectory(excluding coupleId: String?) {
        search(query: "", excluding: coupleId, immediately: true)
    }

    func search(query: String, excluding coupleId: String?, immediately: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = UUID()
        queryToken = token
        isLoading = true
        errorMessage = nil

        searchTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(260))
            }
            guard !Task.isCancelled else { return }
            do {
                let profiles = try await Self.fetchProfiles(matching: trimmed)
                guard !Task.isCancelled, let self, self.queryToken == token else { return }
                self.profiles = profiles
                    .filter { $0.coupleId != coupleId }
                    .sorted { lhs, rhs in lhs.handle.localizedCaseInsensitiveCompare(rhs.handle) == .orderedAscending }
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.queryToken == token else { return }
                self.profiles = []
                self.isLoading = false
                self.errorMessage = "Profile konnten gerade nicht geladen werden."
            }
        }
    }

    private static func fetchProfiles(matching term: String) async throws -> [CoupleProfile] {
        let profiles = Firestore.firestore().collection("coupleProfiles")
        if term.isEmpty {
            let snapshot = try await profiles.order(by: "updatedAt", descending: true).limit(to: 36).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: CoupleProfile.self) }
        }

        // Handles are normalized to lowercase server-side. Firestore has no native full-text
        // search; prefix search keeps this fast and predictable until a dedicated search index
        // becomes worthwhile at scale.
        let handleQuery = profiles.order(by: "handle")
            .start(at: [term])
            .end(at: [term + "\u{f8ff}"])
            .limit(to: 24)
        let displayNameQuery = profiles.order(by: "displayNameNormalized")
            .start(at: [term])
            .end(at: [term + "\u{f8ff}"])
            .limit(to: 24)
        async let handleSnapshot = handleQuery.getDocuments()
        async let displayNameSnapshot = displayNameQuery.getDocuments()
        let snapshots = try await [handleSnapshot, displayNameSnapshot]
        var unique: [String: CoupleProfile] = [:]
        for snapshot in snapshots {
            for document in snapshot.documents {
                if let profile = try? document.data(as: CoupleProfile.self) {
                    unique[profile.coupleId] = profile
                }
            }
        }
        return Array(unique.values)
    }
}
