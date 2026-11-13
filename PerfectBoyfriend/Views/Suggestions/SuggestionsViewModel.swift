import Foundation

@MainActor
final class SuggestionsViewModel: ObservableObject {
    struct Failure {
        let symbol: String
        let title: String
        let message: String
        let retryIsAvailable: Bool
    }

    enum State {
        case loading
        case loaded(requestId: String, suggestions: [DateSuggestion])
        case failed(Failure)
    }

    @Published private(set) var state: State = .loading
    private var hasStarted = false
    private var isRequestRunning = false

    func loadIfNeeded(scope: DatePlanningScope, criteria: DateCriteria) async {
        guard !hasStarted else { return }
        hasStarted = true
        await load(scope: scope, criteria: criteria)
    }

    func load(scope: DatePlanningScope, criteria: DateCriteria) async {
        guard !isRequestRunning else { return }
        isRequestRunning = true
        defer { isRequestRunning = false }
        state = .loading
        do {
            let response = try await DateSuggestionService.generateSuggestions(scope: scope, criteria: criteria)
            guard !Task.isCancelled else { return }

            // This first step deliberately stays text-only. It is a fast, no-image selection
            // board with five options per stop. MapKit resolution and paid visual generation
            // run only once the couple has confirmed its exact combination.
            guard !Task.isCancelled else { return }
            state = .loaded(requestId: response.requestId, suggestions: response.suggestions)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(failure(for: error))
        }
    }

    private func failure(for error: Error) -> Failure {
        if let serviceError = error as? DateSuggestionService.ServiceError,
           case let .functionsError(code, _) = serviceError {
            switch code {
            case .resourceExhausted:
                return Failure(
                    symbol: "hourglass",
                    title: "Kurz pausieren",
                    message: "Damit aus Versehen keine mehrfachen KI-Anfragen entstehen, kannst du in wenigen Minuten wieder neue Ideen generieren.",
                    retryIsAvailable: false
                )
            case .invalidArgument:
                return Failure(
                    symbol: "slider.horizontal.3",
                    title: "Angaben kurz prüfen",
                    message: "Bitte gehe zurück zur Planung und prüfe Stadt, Uhrzeit und eure Auswahl.",
                    retryIsAvailable: false
                )
            case .permissionDenied:
                return Failure(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Planung nicht verfügbar",
                    message: "Dein persönlicher, Paar- oder Match-Bereich konnte gerade nicht bestätigt werden.",
                    retryIsAvailable: true
                )
            default:
                break
            }
        }

        return Failure(
            symbol: "wifi.exclamationmark",
            title: "Vorschläge gerade nicht erreichbar",
            message: error.localizedDescription,
            retryIsAvailable: true
        )
    }
}
