import FirebaseFunctions
import Foundation

/// Calls the generateDateSuggestions callable Function. Mirrors the Atlas OpenAIClient
/// discipline: never assume a successful call implies well-shaped data — always decode into a
/// Codable struct and treat a decode failure as its own explicit error state, and branch on the
/// FunctionsErrorCode explicitly rather than showing a generic message for everything.
enum DateSuggestionService {
    enum ServiceError: LocalizedError {
        case functionsError(FunctionsErrorCode, String)
        case decodingFailed
        case missingResult

        var errorDescription: String? {
            switch self {
            case .functionsError(let code, let message):
                switch code {
                case .unauthenticated:
                    return "Bitte melde dich erneut an."
                case .permissionDenied:
                    return "Du bist keinem Paar zugeordnet."
                case .invalidArgument:
                    return "Die Kriterien konnten nicht verarbeitet werden."
                case .resourceExhausted:
                    return "Bitte warte kurz, bevor du erneut Vorschläge generierst."
                case .unavailable, .deadlineExceeded:
                    return "Der Dienst ist gerade nicht erreichbar. Bitte versuch es erneut."
                default:
                    return "Die KI-Anfrage ist fehlgeschlagen: \(message)"
                }
            case .decodingFailed:
                return "Antwort konnte nicht gelesen werden."
            case .missingResult:
                return "Keine Antwort erhalten."
            }
        }
    }

    static func generateSuggestions(scope: DatePlanningScope, criteria: DateCriteria) async throws -> GenerateDateSuggestionsResponse {
        let payload: [String: Any]
        do {
            let criteriaData = try JSONEncoder().encode(criteria)
            let criteriaDict = try JSONSerialization.jsonObject(with: criteriaData) as? [String: Any] ?? [:]
            switch scope {
            case .couple(let coupleId):
                payload = ["coupleId": coupleId, "criteria": criteriaDict]
            case .singleMatch(let matchId):
                payload = ["matchId": matchId, "criteria": criteriaDict]
            case .personal(let uid):
                payload = ["ownerUid": uid, "criteria": criteriaDict]
            }
        } catch {
            throw ServiceError.decodingFailed
        }

        do {
            let callable = Functions.functions().httpsCallable("generateDateSuggestions")
            // The OpenAI generation call is the longest-running network request in the app.
            // Firebase's own callable timeout defaults to 70s, but a stalled connection should
            // still surface the same clear, German-language timeout error the rest of the app
            // uses (see Services/AsyncTimeout.swift) rather than whatever generic message Firebase
            // produces on its own deadline.
            let result = try await withTimeout(seconds: 45) {
                try await callable.call(payload)
            }
            guard let dict = result.data as? [String: Any] else {
                throw ServiceError.missingResult
            }
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(GenerateDateSuggestionsResponse.self, from: jsonData)
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code) ?? .internal
            throw ServiceError.functionsError(code, error.localizedDescription)
        } catch is DecodingError {
            throw ServiceError.decodingFailed
        }
    }

    /// The initial response contains five alternatives per route segment. Only the confirmed
    /// combination is persisted and subsequently allowed to trigger paid image generation.
    static func composeSuggestion(
        scope: DatePlanningScope,
        requestId: String,
        candidateIds: [String]
    ) async throws -> DateSuggestion {
        var payload: [String: Any] = ["requestId": requestId, "candidateIds": candidateIds]
        switch scope {
        case .couple(let coupleId): payload["coupleId"] = coupleId
        case .singleMatch(let matchId): payload["matchId"] = matchId
        case .personal(let uid): payload["ownerUid"] = uid
        }
        let requestPayload = payload
        do {
            let result = try await withTimeout(seconds: 20) {
                try await Functions.functions().httpsCallable("composeDateSuggestion").call(requestPayload)
            }
            guard let dictionary = result.data as? [String: Any], let suggestion = dictionary["suggestion"] else {
                throw ServiceError.missingResult
            }
            return try JSONDecoder().decode(DateSuggestion.self, from: JSONSerialization.data(withJSONObject: suggestion))
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code) ?? .internal
            throw ServiceError.functionsError(code, error.localizedDescription)
        } catch is DecodingError {
            throw ServiceError.decodingFailed
        }
    }
}
