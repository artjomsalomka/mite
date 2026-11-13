import FirebaseFunctions
import Foundation

/// Paid visual enrichment is intentionally separate from textual date generation. It runs only
/// after a person opens one concrete route and returns cached Storage paths on later opens.
enum DateSuggestionImageService {
    private struct Response: Codable {
        let stationImages: [StationImage]
    }

    private struct StationImage: Codable {
        let order: Int
        let licensedImage: LicensedImage
    }

    static func generateImages(
        scope: DatePlanningScope,
        requestId: String,
        suggestionId: String
    ) async throws -> [Int: LicensedImage] {
        var data: [String: Any] = [
            "requestId": requestId,
            "suggestionId": suggestionId,
        ]
        switch scope {
        case .couple(let coupleId): data["coupleId"] = coupleId
        case .singleMatch(let matchId): data["matchId"] = matchId
        case .personal(let uid): data["ownerUid"] = uid
        }
        let requestData = data
        // The callable has a 60-second server limit. Leave a small client-side margin for the
        // response to travel back after the last image has been written to Storage; otherwise a
        // successful slow generation can look like a missing image on a physical device.
        let result = try await withTimeout(seconds: 70) {
            try await Functions.functions().httpsCallable("generateDateStationImages").call(requestData)
        }
        guard let payload = result.data as? [String: Any] else {
            throw DateSuggestionService.ServiceError.missingResult
        }
        let decoded = try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: payload))
        return Dictionary(uniqueKeysWithValues: decoded.stationImages.map { ($0.order, $0.licensedImage) })
    }
}
