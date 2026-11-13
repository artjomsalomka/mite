import EventKit
import EventKitUI
import SwiftUI

/// Uses Apple's editor instead of direct EventKit writes. The person using the app chooses the
/// target calendar and can edit every detail; the app never reads existing calendar data.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let savedDate: SavedDate
    @Binding var isPresented: Bool
    let onCompletion: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let eventStore = context.coordinator.eventStore
        let event = EKEvent(eventStore: eventStore)
        let startDate = savedDate.scheduledAt.dateValue()

        event.title = savedDate.title
        event.startDate = startDate
        event.endDate = savedDate.endsAt
        event.isAllDay = false
        event.location = primaryLocation
        event.notes = eventNotes

        let editor = EKEventEditViewController()
        editor.eventStore = eventStore
        editor.event = event
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let eventStore = EKEventStore()
        private let parent: CalendarEventEditor

        init(parent: CalendarEventEditor) {
            self.parent = parent
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            parent.isPresented = false
            parent.onCompletion(action == .saved)
        }
    }

    private var primaryLocation: String? {
        guard let station = savedDate.stations.first else { return nil }
        if let place = station.resolvedPlace {
            return "\(place.name), \(place.address)"
        }
        return station.title
    }

    private var eventNotes: String {
        DateSchedule.shareText(title: savedDate.title, stations: savedDate.stations, startingAt: savedDate.scheduledAt.dateValue())
    }
}
