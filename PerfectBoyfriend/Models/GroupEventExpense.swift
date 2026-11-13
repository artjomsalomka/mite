import FirebaseFirestore
import Foundation

enum GroupEventExpenseStatus: String, Codable {
    case active
    case voided
}

struct GroupEventExpense: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var title: String
    var amountMinor: Int
    var currency: String
    var paidByUid: String
    var participantUids: [String]
    var sharesByUid: [String: Int]
    var createdByUid: String
    var status: GroupEventExpenseStatus
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

enum GroupEventSettlementStatus: String, Codable {
    case markedPaid
    case confirmed
}

struct GroupEventSettlementRecord: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var fromUid: String
    var toUid: String
    var amountMinor: Int
    var currency: String
    var status: GroupEventSettlementStatus
    var createdAt: Timestamp
    var confirmedAt: Timestamp?
}

struct GroupEventSettlementSuggestion: Identifiable, Equatable {
    let fromUid: String
    let toUid: String
    let amountMinor: Int
    let currency: String

    var id: String { "\(fromUid)-\(toUid)-\(amountMinor)-\(currency)" }
}

enum GroupEventExpenseCalculator {
    static func equalShares(amountMinor: Int, participantUIDs: [String]) -> [String: Int] {
        let unique = Array(Set(participantUIDs)).sorted()
        guard amountMinor > 0, !unique.isEmpty else { return [:] }
        let base = amountMinor / unique.count
        let remainder = amountMinor % unique.count
        return Dictionary(uniqueKeysWithValues: unique.enumerated().map { index, uid in
            (uid, base + (index < remainder ? 1 : 0))
        })
    }

    static func settlements(
        expenses: [GroupEventExpense],
        payments: [GroupEventSettlementRecord],
        currency: String = "EUR"
    ) -> [GroupEventSettlementSuggestion] {
        var balances: [String: Int] = [:]

        for expense in expenses where expense.status == .active && expense.currency == currency {
            balances[expense.paidByUid, default: 0] += expense.amountMinor
            for (uid, share) in expense.sharesByUid {
                balances[uid, default: 0] -= share
            }
        }

        for payment in payments where payment.currency == currency {
            balances[payment.fromUid, default: 0] += payment.amountMinor
            balances[payment.toUid, default: 0] -= payment.amountMinor
        }

        var debtors = balances.filter { $0.value < 0 }.map { (uid: $0.key, amount: -$0.value) }.sorted { $0.uid < $1.uid }
        var creditors = balances.filter { $0.value > 0 }.map { (uid: $0.key, amount: $0.value) }.sorted { $0.uid < $1.uid }
        var result: [GroupEventSettlementSuggestion] = []
        var debtorIndex = 0
        var creditorIndex = 0

        while debtorIndex < debtors.count && creditorIndex < creditors.count {
            let amount = min(debtors[debtorIndex].amount, creditors[creditorIndex].amount)
            if amount > 0 {
                result.append(.init(
                    fromUid: debtors[debtorIndex].uid,
                    toUid: creditors[creditorIndex].uid,
                    amountMinor: amount,
                    currency: currency
                ))
            }
            debtors[debtorIndex].amount -= amount
            creditors[creditorIndex].amount -= amount
            if debtors[debtorIndex].amount == 0 { debtorIndex += 1 }
            if creditors[creditorIndex].amount == 0 { creditorIndex += 1 }
        }

        return result
    }
}

extension Int {
    func miteCurrency(code: String = "EUR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: NSNumber(value: Double(self) / 100.0)) ?? "\(self) ct"
    }
}
