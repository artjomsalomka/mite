import FirebaseFirestore
import Foundation

enum GroupEventAvailabilityStatus: String, Codable, CaseIterable {
    case available
    case maybe
    case unavailable

    var title: String {
        switch self {
        case .available: return "Verfügbar"
        case .maybe: return "Vielleicht"
        case .unavailable: return "Belegt"
        }
    }
}

enum GroupEventAvailabilitySource: String, Codable {
    case calendar
    case manual
}

struct GroupEventAvailability: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var uid: String
    var slotStatuses: [String: String]
    var durationMinutes: Int
    var source: GroupEventAvailabilitySource
    var updatedAt: Timestamp

    func status(for slot: GroupEventTimeSlot) -> GroupEventAvailabilityStatus? {
        guard durationMinutes == slot.durationMinutes else { return nil }
        guard let rawValue = slotStatuses[slot.storageKey] else { return nil }
        return GroupEventAvailabilityStatus(rawValue: rawValue)
    }
}

struct GroupEventTimeSlot: Identifiable, Hashable {
    let start: Date
    let durationMinutes: Int

    var id: String { storageKey }
    var storageKey: String { String(Int64(start.timeIntervalSince1970.rounded())) }
    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

struct GroupEventTimeSuggestion: Identifiable, Equatable {
    let slot: GroupEventTimeSlot
    let availableCount: Int
    let maybeCount: Int
    let unavailableCount: Int
    let responseCount: Int
    let participantCount: Int

    var id: String { slot.id }
    var everyoneCanAttend: Bool {
        participantCount > 0 && availableCount == participantCount
    }

    var summary: String {
        if everyoneCanAttend { return "Alle \(participantCount) können" }
        if responseCount == 0 { return "Noch keine Antworten" }
        if unavailableCount == 0 && availableCount + maybeCount == participantCount {
            return "Alle könnten"
        }
        return "\(availableCount) von \(participantCount)"
    }
}

enum GroupEventTimeFinder {
    static let hours = [10, 12, 14, 16, 18, 20]

    static func slots(startingAt rangeStart: Date, dayCount: Int = 14, durationMinutes: Int = 120, calendar: Calendar = .current) -> [GroupEventTimeSlot] {
        let firstDay = calendar.startOfDay(for: rangeStart)
        return (0..<dayCount).flatMap { dayOffset -> [GroupEventTimeSlot] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else { return [] }
            return hours.compactMap { hour in
                guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), start > Date() else { return nil }
                return GroupEventTimeSlot(start: start, durationMinutes: durationMinutes)
            }
        }
    }

    static func suggestions(
        slots: [GroupEventTimeSlot],
        responses: [GroupEventAvailability],
        eligibleUIDs: [String],
        limit: Int = 3
    ) -> [GroupEventTimeSuggestion] {
        guard limit > 0 else { return [] }
        let eligibleUIDs = Array(Set(eligibleUIDs))
        let responsesByUID = responses.reduce(into: [String: GroupEventAvailability]()) { result, response in
            if let previous = result[response.uid], previous.updatedAt.dateValue() > response.updatedAt.dateValue() { return }
            result[response.uid] = response
        }
        return slots.map { slot in
            let statuses = eligibleUIDs.compactMap { responsesByUID[$0]?.status(for: slot) }
            return GroupEventTimeSuggestion(
                slot: slot,
                availableCount: statuses.filter { $0 == .available }.count,
                maybeCount: statuses.filter { $0 == .maybe }.count,
                unavailableCount: statuses.filter { $0 == .unavailable }.count,
                responseCount: statuses.count,
                participantCount: eligibleUIDs.count
            )
        }
        // A window is only worth suggesting when nobody has told us they are busy. Ranking
        // conflicting windows merely "lower" made an all-busy calendar fall back to the earliest
        // slot of the range, i.e. a suggestion the person had just marked as blocked.
        .filter { $0.responseCount > 0 && $0.unavailableCount == 0 }
        .sorted { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            return lhsScore == rhsScore ? lhs.slot.start < rhs.slot.start : lhsScore > rhsScore
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func score(_ suggestion: GroupEventTimeSuggestion) -> Int {
        suggestion.availableCount * 100
            + suggestion.maybeCount * 35
            - suggestion.unavailableCount * 150
            + suggestion.responseCount * 4
    }
}

/// The endpoint accepts 120 slots. Always retain the visible edits first, then the nearest
/// saved dates; Dictionary.prefix is random and could silently drop the field just edited.
enum GroupEventAvailabilityPayload {
    static func make(local: [String: GroupEventAvailabilityStatus], saved: [String: String],
                     preferredKeys: Set<String>, now: Date = Date(), limit: Int = 120) -> [String: GroupEventAvailabilityStatus] {
        var merged = saved.compactMapValues(GroupEventAvailabilityStatus.init(rawValue:))
        merged.merge(local) { _, new in new }
        let seconds = Int64(now.timeIntervalSince1970)
        let ordered = merged.keys.filter {
            guard let start = Int64($0) else { return false }
            return start > seconds + 120 && start < seconds + 89 * 86_400
        }.sorted {
            let leftPreferred = preferredKeys.contains($0), rightPreferred = preferredKeys.contains($1)
            if leftPreferred != rightPreferred { return leftPreferred }
            return Int64($0)! < Int64($1)!
        }.prefix(max(0, limit))
        return Dictionary(uniqueKeysWithValues: ordered.map { ($0, merged[$0]!) })
    }
}
