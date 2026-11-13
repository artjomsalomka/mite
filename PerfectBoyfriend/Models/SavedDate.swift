import FirebaseFirestore
import Foundation

enum SavedDateStatus: String, Codable {
    case upcoming
    case completed
    case cancelled
}

struct DateRating: Codable, Equatable {
    var stars: Int
    var comment: String?
    var tags: [String]
    var ratedByUid: String
    var ratedAt: Timestamp
}

/// Mirrors `couples/{coupleId}/savedDates/{savedDateId}` — the only collection the iOS client
/// writes to directly (see firestore.rules: create requires status "upcoming" + rating == nil;
/// update is limited to the `status`/`rating` fields).
struct SavedDate: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var sourceRequestId: String
    var sourceSuggestionId: String
    var title: String
    var scheduledAt: Timestamp
    var createdByUid: String
    var createdAt: Timestamp
    var status: SavedDateStatus
    var stations: [DateStation]
    var rating: DateRating?
    var completedStationOrders: [Int]? = nil

    var endsAt: Date {
        DateSchedule.stops(stations, startingAt: scheduledAt.dateValue()).last?.endsAt ?? scheduledAt.dateValue()
    }

    var allStationsCompleted: Bool {
        !stations.isEmpty && stations.allSatisfy { (completedStationOrders ?? []).contains($0.order) }
    }

    var canRate: Bool {
        status == .upcoming && (isInPast || (allStationsCompleted && scheduledAt.dateValue() <= Date()))
    }

    /// A saved date counts as "past" once its scheduled time has elapsed — used to split the
    /// history view into upcoming/past and to gate the rating CTA, independent of `status`
    /// (which the couple could also mark `cancelled`).
    var isInPast: Bool {
        endsAt < Date()
    }
}
