import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Wraps the createCouple/joinCoupleWithCode callable Functions and a live listener on the
/// resulting couple doc. Couple lifecycle writes never happen directly against Firestore from
/// the client — see firestore.rules, which denies them outright — so this is the only path.
@MainActor
final class CoupleService: ObservableObject {
    enum ServiceError: LocalizedError {
        case functionsError(FunctionsErrorCode, String)
        case decodingFailed
        case missingResult

        var errorDescription: String? {
            switch self {
            case .functionsError(let code, let message):
                switch code {
                case .alreadyExists: return "Du bist bereits einem Paar zugeordnet."
                case .notFound: return "Dieser Code ist ungültig."
                case .failedPrecondition: return message
                case .invalidArgument: return "Bitte einen gültigen 6-stelligen Code eingeben."
                case .unauthenticated: return "Bitte melde dich erneut an."
                default: return "Etwas ist schiefgelaufen: \(message)"
                }
            case .decodingFailed: return "Antwort konnte nicht gelesen werden."
            case .missingResult: return "Keine Antwort erhalten."
            }
        }
    }

    @Published private(set) var couple: Couple?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    private var coupleListener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningCoupleId: String?
    private var listeningSession: UUID?

    func createCouple() async throws -> String {
        let result = try await callFunction("createCouple", data: [:])
        guard let inviteCode = result["inviteCode"] as? String else {
            throw ServiceError.decodingFailed
        }
        return inviteCode
    }

    func joinCouple(code: String) async throws {
        _ = try await callFunction("joinCoupleWithCode", data: ["code": code])
    }

    func startListening(coupleId: String) {
        coupleListener?.remove()
        initialLoadTask?.cancel()
        let session = UUID()
        listeningCoupleId = coupleId
        listeningSession = session
        couple = nil
        isLoading = true
        loadError = nil

        coupleListener = Firestore.firestore().collection("couples").document(coupleId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ couples/\(coupleId) listener error: \(error)")
                        self.loadError = "Euer Paarbereich konnte gerade nicht geladen werden. Prüft die Verbindung und versucht es erneut."
                        return
                    }

                    self.couple = try? snapshot?.data(as: Couple.self)
                    self.loadError = self.couple == nil
                        ? "Euer Paarbereich wurde nicht gefunden. Bitte versucht das Laden erneut."
                        : nil
                }
            }

        // A Firestore listener can remain silent after a temporary emulator/network break. A
        // bounded fallback turns that otherwise endless ProgressView into a recoverable state.
        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard
                !Task.isCancelled,
                let self,
                self.listeningSession == session,
                self.isLoading
            else { return }
            print("⚠️ couples/\(coupleId) listener never fired within 10s — showing retry state")
            self.isLoading = false
            self.loadError = "Die Verbindung zu eurem Paarbereich dauert zu lange. Bitte versucht es erneut."
        }
    }

    func stopListening() {
        coupleListener?.remove()
        initialLoadTask?.cancel()
        coupleListener = nil
        initialLoadTask = nil
        listeningCoupleId = nil
        listeningSession = nil
        couple = nil
        isLoading = false
        loadError = nil
    }

    func retryLoadingCouple() {
        guard let listeningCoupleId else { return }
        startListening(coupleId: listeningCoupleId)
    }

    private func callFunction(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        do {
            let callable = Functions.functions().httpsCallable(name)
            // Couple creation/joining drives a full-screen loading state. Bound the callable the
            // same way as every other network mutation so an interrupted emulator connection
            // cannot leave that screen spinning forever. `createCouple` is server-idempotent,
            // therefore a retry after this timeout returns the original pending invite code.
            let result = try await withTimeout(seconds: 15) {
                try await callable.call(data)
            }
            guard let dict = result.data as? [String: Any] else {
                throw ServiceError.missingResult
            }
            return dict
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code) ?? .internal
            throw ServiceError.functionsError(code, error.localizedDescription)
        }
    }

    deinit {
        coupleListener?.remove()
        initialLoadTask?.cancel()
    }
}
