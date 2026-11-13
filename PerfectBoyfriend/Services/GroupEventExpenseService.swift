import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class GroupEventExpenseService: ObservableObject {
    @Published private(set) var expenses: [GroupEventExpense] = []
    @Published private(set) var payments: [GroupEventSettlementRecord] = []
    @Published private(set) var paymentLinksByUID: [String: String] = [:]
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var expenseListener: ListenerRegistration?
    private var paymentListener: ListenerRegistration?
    private var expenseLoadError: String?
    private var paymentLoadError: String?
    private var listenerGeneration = UUID()

    deinit {
        expenseListener?.remove()
        paymentListener?.remove()
    }

    func startListening(eventId: String) {
        stopListening()
        let generation = listenerGeneration
        expenseLoadError = nil
        paymentLoadError = nil
        updateLoadError()
        guard !eventId.isEmpty else { return }
        let eventRef = Firestore.firestore().collection("groupEvents").document(eventId)
        expenseListener = eventRef.collection("expenses")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == generation else { return }
                    if let error {
                        self.expenseLoadError = "Ausgaben konnten nicht geladen werden: \(error.localizedDescription)"
                        self.updateLoadError()
                        return
                    }
                    self.expenseLoadError = nil
                    self.updateLoadError()
                    self.expenses = snapshot?.documents.compactMap { try? $0.data(as: GroupEventExpense.self) } ?? []
                }
            }
        paymentListener = eventRef.collection("settlements")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == generation else { return }
                    if let error {
                        self.paymentLoadError = "Zahlungen konnten nicht geladen werden: \(error.localizedDescription)"
                        self.updateLoadError()
                        return
                    }
                    self.paymentLoadError = nil
                    self.updateLoadError()
                    self.payments = snapshot?.documents.compactMap { try? $0.data(as: GroupEventSettlementRecord.self) } ?? []
                }
            }
        Task { await loadPaymentLinks(eventId: eventId) }
    }

    func stopListening() {
        listenerGeneration = UUID()
        expenseListener?.remove()
        paymentListener?.remove()
        expenseListener = nil
        paymentListener = nil
        expenses = []
        payments = []
        paymentLinksByUID = [:]
        expenseLoadError = nil
        paymentLoadError = nil
        errorMessage = nil
    }

    private func updateLoadError() {
        errorMessage = expenseLoadError ?? paymentLoadError
    }

    func addExpense(
        eventId: String,
        title: String,
        amountMinor: Int,
        paidByUid: String,
        participantUIDs: [String],
        sharesByUID: [String: Int]
    ) async -> Bool {
        await call("addGroupEventExpense", data: [
            "eventId": eventId,
            "title": title,
            "amountMinor": amountMinor,
            "currency": "EUR",
            "paidByUid": paidByUid,
            "participantUids": participantUIDs,
            "sharesByUid": sharesByUID,
        ])
    }

    func voidExpense(eventId: String, expenseId: String) async -> Bool {
        await call("voidGroupEventExpense", data: ["eventId": eventId, "expenseId": expenseId])
    }

    func markPaid(eventId: String, suggestion: GroupEventSettlementSuggestion) async -> Bool {
        await call("markGroupEventSettlementPaid", data: [
            "eventId": eventId,
            "toUid": suggestion.toUid,
            "amountMinor": suggestion.amountMinor,
            "currency": suggestion.currency,
        ])
    }

    func confirm(eventId: String, settlementId: String) async -> Bool {
        await call("confirmGroupEventSettlement", data: ["eventId": eventId, "settlementId": settlementId])
    }

    func savePayPalMe(eventId: String, url: String) async -> Bool {
        let success = await call("setGroupEventPaymentLink", data: ["url": url])
        if success { await loadPaymentLinks(eventId: eventId) }
        return success
    }

    private func loadPaymentLinks(eventId: String) async {
        let generation = listenerGeneration
        do {
            let callable = Functions.functions().httpsCallable("getGroupEventPaymentLinks")
            let result = try await withTimeout(seconds: 15) { try await callable.call(["eventId": eventId]) }
            guard generation == listenerGeneration else { return }
            paymentLinksByUID = (result.data as? [String: Any])?["links"] as? [String: String] ?? [:]
        } catch {
            guard generation == listenerGeneration else { return }
            // Payment links are optional; the ledger remains fully usable without them.
            paymentLinksByUID = [:]
        }
    }

    private func call(_ name: String, data: [String: Any]) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let callable = Functions.functions().httpsCallable(name)
            _ = try await withTimeout(seconds: 20) { try await callable.call(data) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
