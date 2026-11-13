import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class GroupEventService: ObservableObject {
    @Published private(set) var events: [GroupEvent] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private var listener: ListenerRegistration?
    private var initialLoadTask: Task<Void, Never>?
    private var listeningUID: String?
    private var listeningSession: UUID?

    deinit {
        listener?.remove()
        initialLoadTask?.cancel()
    }

    func startListening(uid: String) {
        listener?.remove()
        initialLoadTask?.cancel()
        let session = UUID()
        listeningUID = uid
        listeningSession = session
        isLoading = true
        errorMessage = nil
        listener = Firestore.firestore().collection("groupEvents")
            .whereField("participantUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listeningSession == session else { return }
                    self.initialLoadTask?.cancel()
                    self.isLoading = false
                    if let error {
                        print("⚠️ group event listener error: \(error)")
                        self.errorMessage = "Pläne mit Freund:innen konnten nicht geladen werden."
                        return
                    }
                    self.events = (snapshot?.documents.compactMap { try? $0.data(as: GroupEvent.self) } ?? [])
                        .sorted { $0.scheduledAt.dateValue() < $1.scheduledAt.dateValue() }
                }
            }

        initialLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  let self,
                  self.listeningSession == session,
                  self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Die Verbindung zu deinen Plänen dauert zu lange. Bitte versuche es erneut."
        }
    }

    func retryLoading() {
        guard let listeningUID else { return }
        startListening(uid: listeningUID)
    }

    func create(title: String, city: String, note: String, scheduledAt: Date, invitees: [PersonProfile], planSteps: [String] = [], coverLicensedImage: LicensedImage? = nil) async throws {
        let callable = Functions.functions().httpsCallable("createGroupEvent")
        var payload: [String: Any] = [
            "title": title,
            "city": city,
            "note": note,
            "scheduledAt": ISO8601DateFormatter().string(from: scheduledAt),
            "inviteeUids": invitees.map(\.uid),
            "planSteps": planSteps,
        ]
        if let coverLicensedImage {
            var imagePayload: [String: Any] = [
                "url": coverLicensedImage.url,
                "sourcePageURL": coverLicensedImage.sourcePageURL,
                "creator": coverLicensedImage.creator,
                "license": coverLicensedImage.license,
            ]
            if let licenseURL = coverLicensedImage.licenseURL { imagePayload["licenseURL"] = licenseURL }
            payload["coverLicensedImage"] = imagePayload
        }
        let requestPayload = payload
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(requestPayload)
        }
    }

    func updateCover(eventId: String, coverImagePath: String) async throws {
        let callable = Functions.functions().httpsCallable("updateGroupEventCover")
        _ = try await withTimeout(seconds: 20) {
            try await callable.call(["eventId": eventId, "coverImagePath": coverImagePath])
        }
    }

    func respond(to event: GroupEvent, status: GroupEventAttendance) async throws {
        guard let eventId = event.id else { return }
        let callable = Functions.functions().httpsCallable("respondToGroupEvent")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(["eventId": eventId, "status": status.rawValue])
        }
    }

    func cancel(_ event: GroupEvent) async throws {
        guard let eventId = event.id else { return }
        let callable = Functions.functions().httpsCallable("cancelGroupEvent")
        _ = try await withTimeout(seconds: 15) { try await callable.call(["eventId": eventId]) }
    }

    func markRead(eventId: String) async {
        guard !eventId.isEmpty else { return }
        let callable = Functions.functions().httpsCallable("markGroupEventRead")
        do {
            _ = try await withTimeout(seconds: 10) {
                try await callable.call(["eventId": eventId])
            }
        } catch {
            print("⚠️ group event read cursor failed: \(error)")
        }
    }

    func invite(eventId: String, profiles: [PersonProfile]) async throws {
        guard !profiles.isEmpty else { return }
        let callable = Functions.functions().httpsCallable("inviteToGroupEvent")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(["eventId": eventId, "inviteeUids": profiles.map(\.uid)])
        }
    }

    func leave(eventId: String) async throws {
        let callable = Functions.functions().httpsCallable("leaveGroupEvent")
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(["eventId": eventId])
        }
    }
}
