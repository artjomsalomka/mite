import FirebaseFunctions
import Foundation

@MainActor
final class SingleMatchingService: ObservableObject {
    private struct SuggestionsResponse: Codable, Sendable { let suggestions: [SingleSuggestion] }
    private struct MatchesResponse: Codable, Sendable { let matches: [SingleMatchPreview] }
    private struct InterestResponse: Codable, Sendable { let status: String; let matchId: String? }

    @Published private(set) var suggestions: [SingleSuggestion] = []
    @Published private(set) var matches: [SingleMatchPreview] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pendingUids: Set<String> = []
    @Published var actionError: String?
    @Published var newMatch: SingleSuggestion?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let suggestions = request("getSingleSuggestions", data: [:], response: SuggestionsResponse.self)
            async let matches = request("getSingleMatches", data: [:], response: MatchesResponse.self)
            let (suggestionResponse, matchResponse) = try await (suggestions, matches)
            self.suggestions = suggestionResponse.suggestions
            self.matches = matchResponse.matches
        } catch {
            actionError = error.localizedDescription
        }
    }

    func expressInterest(in suggestion: SingleSuggestion) async {
        guard !pendingUids.contains(suggestion.uid) else { return }
        pendingUids.insert(suggestion.uid)
        defer { pendingUids.remove(suggestion.uid) }
        do {
            let result = try await request(
                "expressSingleInterest",
                data: ["targetUid": suggestion.uid],
                response: InterestResponse.self
            )
            suggestions.removeAll { $0.uid == suggestion.uid }
            if result.status == "matched" {
                newMatch = suggestion
                await loadMatches()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @discardableResult
    func block(_ suggestion: SingleSuggestion) async -> Bool {
        do {
            try await requestVoid("blockSingle", data: ["targetUid": suggestion.uid])
            suggestions.removeAll { $0.uid == suggestion.uid }
            matches.removeAll { $0.profile.uid == suggestion.uid }
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func report(_ suggestion: SingleSuggestion, reason: String) async -> Bool {
        do {
            try await requestVoid("reportSingle", data: ["targetUid": suggestion.uid, "reason": reason])
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func loadMatches() async {
        do {
            matches = try await request("getSingleMatches", data: [:], response: MatchesResponse.self).matches
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func request<T: Decodable & Sendable>(_ name: String, data: [String: Any], response: T.Type) async throws -> T {
        let callable = Functions.functions().httpsCallable(name)
        return try await withTimeout(seconds: 15) {
            let result = try await callable.call(data)
            guard let dictionary = result.data as? [String: Any] else {
                throw MatchingError.invalidResponse
            }
            let json = try JSONSerialization.data(withJSONObject: dictionary)
            return try JSONDecoder().decode(T.self, from: json)
        }
    }

    private func requestVoid(_ name: String, data: [String: Any]) async throws {
        let callable = Functions.functions().httpsCallable(name)
        _ = try await withTimeout(seconds: 15) {
            try await callable.call(data)
        }
    }

    private enum MatchingError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "Die Antwort konnte nicht verarbeitet werden." }
    }
}
