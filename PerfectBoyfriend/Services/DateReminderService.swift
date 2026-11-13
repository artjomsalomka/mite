import Foundation
import UserNotifications

enum DateReminderLeadTime: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case oneHour = 60
    case oneDay = 1_440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fifteenMinutes: return "15 Minuten vorher"
        case .oneHour: return "1 Stunde vorher"
        case .oneDay: return "1 Tag vorher"
        }
    }

    func fireDate(for scheduledAt: Date) -> Date {
        scheduledAt.addingTimeInterval(TimeInterval(-rawValue * 60))
    }
}

enum DateReminderError: LocalizedError {
    case notificationsDenied
    case reminderWouldBeInPast
    case missingDateIdentifier

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            return "Benachrichtigungen sind deaktiviert. Du kannst sie in den iPhone-Einstellungen für Mite erlauben."
        case .reminderWouldBeInPast:
            return "Für diesen Zeitpunkt liegt die Erinnerung bereits in der Vergangenheit."
        case .missingDateIdentifier:
            return "Dieses Date konnte noch nicht eindeutig zugeordnet werden."
        }
    }
}

/// Device-local reminders. Nothing about a reminder is written to Firestore or sent to another
/// member of a couple or match, so every person decides independently whether to receive one.
@MainActor
final class DateReminderService: ObservableObject {
    private let notificationCenter = UNUserNotificationCenter.current()

    func scheduledReminderDate(for scope: DatePlanningScope, savedDate: SavedDate) async -> Date? {
        guard let identifier = identifier(for: scope, savedDate: savedDate) else { return nil }
        let requests = await notificationCenter.pendingNotificationRequests()
        guard let request = requests.first(where: { $0.identifier == identifier }),
              let timestamp = request.content.userInfo["fireDate"] as? NSNumber else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp.doubleValue)
    }

    func schedule(
        for scope: DatePlanningScope,
        savedDate: SavedDate,
        leadTime: DateReminderLeadTime
    ) async throws -> Date {
        guard let identifier = identifier(for: scope, savedDate: savedDate) else {
            throw DateReminderError.missingDateIdentifier
        }

        let scheduledAt = savedDate.scheduledAt.dateValue()
        let fireDate = leadTime.fireDate(for: scheduledAt)
        guard fireDate > Date() else { throw DateReminderError.reminderWouldBeInPast }

        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { throw DateReminderError.notificationsDenied }
        case .denied:
            throw DateReminderError.notificationsDenied
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Date-Erinnerung"
        content.body = "\(savedDate.title) beginnt um \(scheduledAt.miteTimeText)."
        content.sound = .default
        content.userInfo = ["fireDate": NSNumber(value: fireDate.timeIntervalSince1970)]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await notificationCenter.add(request)
        return fireDate
    }

    func removeReminder(for scope: DatePlanningScope, savedDate: SavedDate) {
        guard let identifier = identifier(for: scope, savedDate: savedDate) else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func identifier(for scope: DatePlanningScope, savedDate: SavedDate) -> String? {
        guard let savedDateId = savedDate.id else { return nil }
        let owner = switch scope {
        case .couple: "couple"
        case .singleMatch: "match"
        case .personal: "personal"
        }
        return "date-reminder-\(owner)-\(scope.id)-\(savedDateId)"
    }
}
