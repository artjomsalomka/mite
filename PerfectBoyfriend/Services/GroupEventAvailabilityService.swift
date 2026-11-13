import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class GroupEventAvailabilityService: ObservableObject {
    @Published private(set) var responses: [GroupEventAvailability] = []
    @Published private(set) var isSaving = false
    /// False until the first snapshot (or error) arrives, so callers can tell "no answer yet"
    /// apart from "answers not loaded yet" before deciding to auto-fill anything.
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var listenerGeneration = UUID()
    typealias Writer = (String, [String: GroupEventAvailabilityStatus], Int, GroupEventAvailabilitySource) async throws -> Void
    private let writer: Writer
    private var writeTail: Task<Bool, Never>?
    private var writeSequence = 0

    init(writer: Writer? = nil) {
        self.writer = writer ?? { eventId, statuses, durationMinutes, source in
            let slots = statuses.map { key, status -> [String: Any] in
                ["startEpochSeconds": Int64(key) ?? 0, "status": status.rawValue]
            }
            let callable = Functions.functions().httpsCallable("setGroupEventAvailability")
            _ = try await withTimeout(seconds: 20) {
                try await callable.call(["eventId": eventId, "slots": slots,
                    "durationMinutes": durationMinutes, "source": source.rawValue])
            }
        }
    }

    deinit { listener?.remove() }

    func startListening(eventId: String) {
        listener?.remove()
        listenerGeneration = UUID()
        let generation = listenerGeneration
        responses = []
        hasLoaded = false
        errorMessage = nil
        guard !eventId.isEmpty else { return }
        listener = Firestore.firestore().collection("groupEvents").document(eventId)
            .collection("availability")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == generation else { return }
                    self.hasLoaded = true
                    if let error {
                        self.errorMessage = "Verfügbarkeiten konnten nicht geladen werden: \(error.localizedDescription)"
                        return
                    }
                    self.errorMessage = nil
                    self.responses = snapshot?.documents.compactMap { try? $0.data(as: GroupEventAvailability.self) } ?? []
                }
            }
    }

    func stopListening() {
        listenerGeneration = UUID()
        listener?.remove()
        listener = nil
        responses = []
        hasLoaded = false
    }

    @discardableResult
    func save(
        eventId: String,
        statuses: [String: GroupEventAvailabilityStatus],
        durationMinutes: Int,
        source: GroupEventAvailabilitySource
    ) async -> Bool {
        guard !eventId.isEmpty, !statuses.isEmpty else {
            errorMessage = "Markiere mindestens ein Zeitfenster."
            return false
        }
        isSaving = true
        errorMessage = nil
        writeSequence += 1
        let sequence = writeSequence
        let preceding = writeTail
        // The endpoint replaces the snapshot. Serializing prevents a slower older request
        // from overwriting the last tap, including calendar sync racing with manual edits.
        let pending = Task { @MainActor in
            _ = await preceding?.value
            do {
                try await self.writer(eventId, statuses, durationMinutes, source)
                if sequence == self.writeSequence { self.errorMessage = nil }
                return true
            } catch {
                if sequence == self.writeSequence { self.errorMessage = error.localizedDescription }
                return false
            }
        }
        writeTail = pending
        let result = await pending.value
        if sequence == writeSequence {
            isSaving = false
            writeTail = nil
        }
        return result
    }
}
