import MapKit
import Foundation

/// MapKit-powered place completion for the planner. The user sees familiar Maps-style results,
/// while the planner persists only the chosen city name — never a precise coordinate.
@MainActor
final class CitySearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]
    private var lastQuery = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            clear()
            return
        }
        guard cleaned != lastQuery else { return }

        lastQuery = cleaned
        isSearching = true
        completer.queryFragment = cleaned
    }

    func clear() {
        lastQuery = ""
        suggestions = []
        completionsByID = [:]
        isSearching = false
        completer.queryFragment = ""
    }

    /// Resolves a completion once, then keeps only its city/locality in the planning criteria.
    func selectedCity(for suggestion: Suggestion) async -> String {
        guard let completion = completionsByID[suggestion.id] else { return suggestion.title }
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return suggestion.title
        }

        let locality = response.mapItems
            .compactMap { $0.placemark.locality ?? $0.placemark.subAdministrativeArea }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return locality ?? suggestion.title
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map { completion -> (Suggestion, MKLocalSearchCompletion) in
            let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = "\(title.lowercased())|\(subtitle.lowercased())"
            return (Suggestion(id: id, title: title, subtitle: subtitle), completion)
        }
        Task { @MainActor in
            guard completer.queryFragment == lastQuery else { return }
            suggestions = mapped.map(\.0)
            completionsByID = Dictionary(uniqueKeysWithValues: mapped.map { ($0.0.id, $0.1) })
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            guard completer.queryFragment == lastQuery else { return }
            suggestions = []
            completionsByID = [:]
            isSearching = false
        }
    }
}

enum PlannerLocationDefaults {
    private static let cityKey = "planner.lastSelectedCity"

    static var lastSelectedCity: String? {
        guard let value = UserDefaults.standard.string(forKey: cityKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func store(city: String) {
        let cleaned = LocationService.normalizedCityName(city)
        guard cleaned.count >= 2 else { return }
        UserDefaults.standard.set(cleaned, forKey: cityKey)
    }
}
