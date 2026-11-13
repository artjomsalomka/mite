import FirebaseFirestore

/// The owner of a date plan. Couples and matched singles deliberately use the same suggestion,
/// save and rating UI, but live in separate Firestore subtrees with separate authorization.
enum DatePlanningScope: Equatable, Hashable {
    case couple(id: String)
    case singleMatch(id: String)
    case personal(id: String)

    var id: String {
        switch self {
        case .couple(let id), .singleMatch(let id), .personal(let id): return id
        }
    }

    var isFirstMeeting: Bool {
        if case .singleMatch = self { return true }
        return false
    }

    var dateHistoryTitle: String {
        switch self {
        case .couple: return "Verlauf"
        case .singleMatch: return "Eure Date-Ideen"
        case .personal: return "Deine Pläne"
        }
    }

    var emptyHistoryDescription: String {
        switch self {
        case .couple: return "Erstellt euer erstes Date im Tab \"Neues Date\"."
        case .singleMatch: return "Plant euer erstes gemeinsames Date, wenn ihr beide bereit seid."
        case .personal: return "Plane dein erstes gemeinsames Erlebnis mit Freund:innen."
        }
    }

    func savedDatesCollection() -> CollectionReference {
        switch self {
        case .couple(let id):
            return Firestore.firestore().collection("couples").document(id).collection("savedDates")
        case .singleMatch(let id):
            return Firestore.firestore().collection("singleMatches").document(id).collection("savedDates")
        case .personal(let id):
            return Firestore.firestore().collection("users").document(id).collection("savedDates")
        }
    }
}
