import FirebaseFirestore
import Foundation
import CryptoKit
import FirebaseFunctions

/// The only service that writes to `savedDates` directly (per firestore.rules: create requires
/// status "upcoming" + rating == nil; update is restricted to `status`/`rating`).
@MainActor
final class SavedDateService: ObservableObject {
    enum SaveError: LocalizedError {
        case invalidTime

        var errorDescription: String? {
            switch self {
            case .invalidTime: return "Wählt bitte einen Startzeitpunkt in der Zukunft."
            }
        }
    }

    static let ratingTags = [
        "würden wir wiederholen",
        "nichts für Regentage",
        "guter Preis",
        "zu teuer",
        "romantisch",
        "eher für Freunde",
        "perfekt für besonderen Anlass",
        "zu anstrengend",
        "entspannend",
    ]
    static let maximumRatingTags = 5
    static let maximumRatingCommentLength = 280

    func setStationCompleted(scope: DatePlanningScope, dateId: String, stationOrder: Int, completed: Bool) async throws {
        let scopeType: String
        switch scope {
        case .couple: scopeType = "couple"
        case .singleMatch: scopeType = "match"
        case .personal: scopeType = "personal"
        }
        let callable = Functions.functions().httpsCallable("setDateStationCompleted")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(["scopeType": scopeType, "scopeId": scope.id, "dateId": dateId,
                                     "stationOrder": stationOrder, "completed": completed])
        }
    }

    enum RatingError: LocalizedError {
        case invalidStars
        case invalidTags
        case commentTooLong

        var errorDescription: String? {
            switch self {
            case .invalidStars: return "Bitte vergib zwischen einem und fünf Sternen."
            case .invalidTags: return "Wähle höchstens fünf passende Tags aus."
            case .commentTooLong: return "Der Kommentar darf höchstens 280 Zeichen lang sein."
            }
        }
    }

    @Published private(set) var savedDates: [SavedDate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?

    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningScope: DatePlanningScope?
    private var listeningSession: UUID?

    func save(scope: DatePlanningScope, requestId: String, suggestion: DateSuggestion, scheduledAt: Date, createdByUid: String) async throws {
        guard scheduledAt > Date() else { throw SaveError.invalidTime }

        // Built as a raw dictionary rather than via setData(from:) on a Codable SavedDate:
        // Swift's auto-synthesized Codable uses encodeIfPresent for Optional properties, which
        // OMITS the key entirely when nil rather than writing an explicit null. firestore.rules'
        // create rule checks `request.resource.data.rating == null`, which fails when the field
        // is simply absent — so the Codable path was getting silently denied server-side. An
        // explicit NSNull() here guarantees the field the rule expects is actually present.
        let stationsData = try suggestion.stations.map { try Firestore.Encoder().encode($0) }
        let data: [String: Any] = [
            "sourceRequestId": requestId,
            "sourceSuggestionId": suggestion.id,
            "title": suggestion.title,
            "scheduledAt": Timestamp(date: scheduledAt),
            "createdByUid": createdByUid,
            "createdAt": Timestamp(date: Date()),
            "status": SavedDateStatus.upcoming.rawValue,
            "stations": stationsData,
            "rating": NSNull(),
        ]
        // MUST be awaited: setData(_:) also has a non-async, completion-less overload that only
        // guarantees the local-cache write and silently drops any server-side rejection (e.g. a
        // security-rules denial). Omitting `await` here previously compiled cleanly by resolving
        // to that overload — the "Gespeichert!" alert fired immediately with the document never
        // actually reaching Firestore, no error surfaced anywhere.
        //
        // Wrapped in a timeout: the local-cache write applies (and listeners fire) instantly
        // regardless, but the await here only completes once the server acks — if the
        // connection stalls, this call has no built-in timeout of its own and would otherwise
        // hang the save button's spinner forever.
        let identity = Data("\(requestId):\(suggestion.id)".utf8)
        let documentId = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let ref = scope.savedDatesCollection().document(documentId)
        try await withTimeout(seconds: 15) {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
                do {
                    // Retrying an uncertain acknowledgement must not create a second date or
                    // overwrite a plan that the other partner has already rescheduled.
                    if try !transaction.getDocument(ref).exists { transaction.setData(data, forDocument: ref) }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        }
    }

    /// Matches the firestore.rules constrained completion update: a valid rating turns a past
    /// upcoming date into `completed` in the same atomic write.
    func submitRating(scope: DatePlanningScope, savedDateId: String, stars: Int, comment: String?, tags: [String], ratedByUid: String) async throws {
        guard (1...5).contains(stars) else { throw RatingError.invalidStars }
        let normalizedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (normalizedComment?.count ?? 0) <= Self.maximumRatingCommentLength else {
            throw RatingError.commentTooLong
        }
        let uniqueTagSet = Set(tags)
        guard tags.count == uniqueTagSet.count,
              tags.count <= Self.maximumRatingTags,
              tags.allSatisfy(Self.ratingTags.contains) else {
            throw RatingError.invalidTags
        }

        let rating = DateRating(stars: stars, comment: normalizedComment?.isEmpty == true ? nil : normalizedComment, tags: tags, ratedByUid: ratedByUid, ratedAt: Timestamp(date: Date()))
        // Firestore's updateData(_:) needs an explicit NSNull() for nil — an Optional wrapped
        // as `Any` does not reliably serialize the way a raw nil literal would.
        let ratingData: [String: Any] = [
            "stars": rating.stars,
            "comment": rating.comment ?? NSNull(),
            "tags": rating.tags,
            "ratedByUid": rating.ratedByUid,
            "ratedAt": rating.ratedAt,
        ]
        try await withTimeout(seconds: 15) {
            try await scope.savedDatesCollection()
                .document(savedDateId)
                .updateData([
                    "rating": ratingData,
                    "status": SavedDateStatus.completed.rawValue,
                ])
        }
    }

    /// A cancellation is deliberately preserved in the shared history rather than deleting the
    /// plan. That keeps both people on the same page while allowing a new idea to be planned.
    func cancel(scope: DatePlanningScope, savedDateId: String) async throws {
        try await withTimeout(seconds: 15) {
            try await scope.savedDatesCollection()
                .document(savedDateId)
                .updateData(["status": SavedDateStatus.cancelled.rawValue])
        }
    }

    /// Keeps the plan and its stations intact while moving only its shared start time. A local
    /// device reminder is intentionally handled by the view that requested this change.
    func reschedule(scope: DatePlanningScope, savedDateId: String, scheduledAt: Date) async throws {
        try await withTimeout(seconds: 15) {
            try await scope.savedDatesCollection()
                .document(savedDateId)
                .updateData(["scheduledAt": Timestamp(date: scheduledAt)])
        }
    }

    func startListening(scope: DatePlanningScope) {
        listener?.remove()
        initialLoadTask?.cancel()
        if listeningScope != scope { savedDates = [] }

        let session = UUID()
        listeningSession = session
        listeningScope = scope
        isLoading = true
        loadErrorMessage = nil
        listener = scope.savedDatesCollection()
            .order(by: "scheduledAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    if let error {
                        print("⚠️ savedDates listener error: \(error)")
                        self.loadErrorMessage = "Der Date-Verlauf konnte gerade nicht geladen werden."
                        self.isLoading = false
                        return
                    }
                    self.savedDates = snapshot?.documents.compactMap { try? $0.data(as: SavedDate.self) } ?? []
                    self.loadErrorMessage = nil
                    self.isLoading = false
                }
            }

        initialLoadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  let self,
                  self.listeningSession == session,
                  self.isLoading else { return }
            self.loadErrorMessage = "Der Date-Verlauf antwortet gerade nicht."
            self.isLoading = false
        }
    }

    func retryLoading() {
        guard let listeningScope else { return }
        startListening(scope: listeningScope)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        initialLoadTask?.cancel()
        initialLoadTask = nil
        listeningScope = nil
        listeningSession = nil
        savedDates = []
        loadErrorMessage = nil
        isLoading = false
    }

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }
}
