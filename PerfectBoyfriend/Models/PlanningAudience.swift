import Foundation

/// The planner always starts with the people, because that decision changes both the language
/// and the feasibility of a useful recommendation. A group contains the current person plus the
/// public profiles they invite.
enum PlanningMode: String, Codable, Equatable {
    case date
    case group
}

struct PlanningAudience: Equatable {
    let mode: PlanningMode
    let invitees: [PersonProfile]

    static let date = PlanningAudience(mode: .date, invitees: [])

    var participantCount: Int {
        mode == .date ? 2 : max(2, invitees.count + 1)
    }

    var routeTitle: String {
        mode == .date ? "Gemeinsam planen" : "Gemeinsam unterwegs"
    }

    var suggestionHeadline: String {
        mode == .date ? "Für euch entdeckt" : "Für eure Runde entdeckt"
    }
}
