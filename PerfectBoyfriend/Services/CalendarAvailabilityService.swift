import EventKit
import Foundation

enum CalendarAvailabilityError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Kalenderzugriff wurde nicht erlaubt. Du kannst deine Zeiten weiterhin manuell markieren."
        }
    }
}

/// Calendar contents never leave this process. Only the resulting availability status for the
/// event's finite candidate slots is returned to the collaboration service.
final class CalendarAvailabilityService {
    /// One long-lived store: EventKit stores are expensive to create and iOS remembers the
    /// permission per app, so the person is asked at most once.
    static let shared = CalendarAvailabilityService()

    private let eventStore = EKEventStore()

    /// True once the person granted full calendar access. Checking this never shows a prompt,
    /// which is what allows the Zeitfinder to sync silently on every later visit.
    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// The system dialog can still be shown (first time, or an upgrade from write-only access).
    static var canRequestAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined, .writeOnly: return true
        default: return false
        }
    }

    func requestAccess() async throws -> Bool {
        if Self.hasFullAccess { return true }
        guard Self.canRequestAccess else { return false }
        return try await eventStore.requestFullAccessToEvents()
    }

    struct Evaluation {
        var statuses: [String: GroupEventAvailabilityStatus]
        var calendarCount: Int
        var consideredEvents: Int
        var ignoredEvents: Int
    }

    /// Never prompts. Call `requestAccess()` first for the one-time permission.
    func evaluate(_ slots: [GroupEventTimeSlot]) async throws -> Evaluation {
        guard !slots.isEmpty else { return Evaluation(statuses: [:], calendarCount: 0, consideredEvents: 0, ignoredEvents: 0) }
        guard Self.hasFullAccess else { throw CalendarAvailabilityError.accessDenied }

        let store = eventStore
        // EventKit's event query is synchronous and can take a noticeable moment for a busy
        // calendar; keep it off the main actor so taps and scrolling stay smooth.
        return await Task.detached(priority: .userInitiated) {
            Self.evaluateSlots(slots, in: store)
        }.value
    }

    private enum Weight { case busy, maybe }

    private static let travelBuffer: TimeInterval = 15 * 60

    static func queryRange(for slots: [GroupEventTimeSlot]) -> DateInterval? {
        guard let first = slots.map(\.start).min(), let last = slots.map(\.end).max() else { return nil }
        return DateInterval(start: first.addingTimeInterval(-travelBuffer), end: last.addingTimeInterval(travelBuffer))
    }

    private static func evaluateSlots(_ slots: [GroupEventTimeSlot], in store: EKEventStore) -> Evaluation {
        // A store that lived through calendar edits (e.g. changes synced from another device)
        // must re-read its sources or it can answer from a stale snapshot.
        store.refreshSourcesIfNecessary()

        guard let range = queryRange(for: slots) else {
            return Evaluation(statuses: [:], calendarCount: 0, consideredEvents: 0, ignoredEvents: 0)
        }
        let lowerBound = range.start
        let upperBound = range.end
        let predicate = store.predicateForEvents(withStart: lowerBound, end: upperBound, calendars: nil)

        var intervals: [(start: Date, end: Date, weight: Weight)] = []
        var ignored = 0
        for event in store.events(matching: predicate) {
            let (weight, _) = classify(event)
            guard let weight else { ignored += 1; continue }
            intervals.append((event.startDate ?? lowerBound, event.endDate ?? lowerBound, weight))
        }

        let buffer = travelBuffer
        var statuses: [String: GroupEventAvailabilityStatus] = [:]
        statuses.reserveCapacity(slots.count)
        for slot in slots {
            let bufferedStart = slot.start.addingTimeInterval(-buffer)
            let bufferedEnd = slot.end.addingTimeInterval(buffer)
            var status = GroupEventAvailabilityStatus.available
            for interval in intervals where interval.start < bufferedEnd && interval.end > bufferedStart {
                if interval.weight == .busy { status = .unavailable; break }
                status = .maybe
            }
            statuses[slot.storageKey] = status
        }
        return Evaluation(
            statuses: statuses,
            calendarCount: store.calendars(for: .event).count,
            consideredEvents: intervals.count,
            ignoredEvents: ignored
        )
    }

    /// One rule set for both the sync and the "what does Mite see" screen, so what the person
    /// reads there is exactly what decided their answers.
    private static func classify(_ event: EKEvent) -> (weight: Weight?, verdict: String) {
        if event.status == .canceled { return (nil, "Übersprungen: abgesagt") }
        if event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) == true {
            return (nil, "Übersprungen: von dir abgelehnt")
        }
        if event.isAllDay {
            let days = (event.endDate ?? Date()).timeIntervalSince(event.startDate ?? Date()) / 86_400
            // Semester, school-holiday or subscription entries span weeks and say nothing about
            // whether a specific evening is free; one of them used to mark every slot as busy.
            if days > 21 { return (nil, "Übersprungen: mehrwöchiger Ganztagstermin (\(Int(days.rounded())) Tage)") }
            if event.availability == .notSupported { return (nil, "Übersprungen: Ganztagstermin aus abonniertem Kalender") }
        }
        switch event.availability {
        case .free:
            // Birthdays and other all-day "free" entries never block a plan. A *timed* entry
            // marked free (a common way work-location or focus blocks are exported) is not a
            // clear "yes" either, so it becomes "vielleicht" instead of vanishing.
            return event.isAllDay ? (nil, "Übersprungen: ganztägig, „Frei“") : (.maybe, "Vielleicht: als „Frei“ markiert")
        case .tentative:
            return (.maybe, "Vielleicht: vorläufig")
        default:
            return (.busy, "Belegt")
        }
    }

    struct DiagnosticEvent: Identifiable {
        let id = UUID()
        let title: String
        let calendarName: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let verdict: String
    }

    struct Diagnostics {
        var events: [DiagnosticEvent]
        var calendars: [String]
    }

    /// Shown only on this device. Event titles are never uploaded.
    func diagnostics(from start: Date, to end: Date) async throws -> Diagnostics {
        guard Self.hasFullAccess else { throw CalendarAvailabilityError.accessDenied }
        let store = eventStore
        return await Task.detached(priority: .userInitiated) {
            store.refreshSourcesIfNecessary()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate)
                .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
                .map { event in
                    DiagnosticEvent(
                        title: event.title ?? "Ohne Titel",
                        calendarName: "\(event.calendar.source.title) · \(event.calendar.title)",
                        start: event.startDate ?? start,
                        end: event.endDate ?? start,
                        isAllDay: event.isAllDay,
                        verdict: Self.classify(event).verdict
                    )
                }
            let calendars = store.calendars(for: .event)
                .map { "\($0.source.title) · \($0.title)" }
                .sorted()
            return Diagnostics(events: events, calendars: calendars)
        }.value
    }
}
