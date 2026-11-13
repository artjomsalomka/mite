import Foundation

/// Turns an LLM-authored route into a concrete, visual plan before it reaches the list. The LLM
/// proposes the sequence and intent; MapKit supplies the real, currently indexed venue. That
/// division means a made-up or stale venue name cannot silently become a saved date.
enum DateSuggestionEnrichmentService {
    static func enrich(_ suggestions: [DateSuggestion], city: String, radiusKilometers: Double) async -> [DateSuggestion] {
        guard let coordinate = try? await withTimeout(seconds: 8, operation: { try await LocationService.geocodeCity(city) }) else {
            return suggestions
        }

        let radiusMeters = max(1_500, radiusKilometers * 1_000)
        return await withTaskGroup(of: (Int, DateSuggestion).self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                group.addTask {
                    var enriched = suggestion
                    enriched.stations = await PlaceResolver.resolveAll(
                        stations: suggestion.stations,
                        near: coordinate,
                        radiusMeters: radiusMeters,
                        city: city
                    )

                    return (index, enriched)
                }
            }

            var enrichedByIndex: [Int: DateSuggestion] = [:]
            for await (index, suggestion) in group {
                enrichedByIndex[index] = suggestion
            }
            return suggestions.indices.compactMap { enrichedByIndex[$0] }
        }
    }

    /// Photo enrichment is separate so a slow photo provider cannot discard verified places.
    static func enrichPhotos(_ suggestions: [DateSuggestion], city: String) async -> [DateSuggestion] {
        await withTaskGroup(of: (Int, DateSuggestion).self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                group.addTask {
                    var result = suggestion
                    result.stations = await enrichStationVisuals(suggestion.stations, city: city)
                    return (index, result)
                }
            }
            var result = suggestions
            for await (index, suggestion) in group { result[index] = suggestion }
            return result
        }
    }

    /// Look up every stop. A real, attributed city/activity photo can be shown even while a
    /// specific MapKit confirmation is still pending; saving remains gated by MapKit elsewhere.
    static func enrichStationVisuals(_ stations: [DateStation], city: String) async -> [DateStation] {
        let candidates = stations.enumerated().filter { _, station in
            station.licensedImage == nil
        }
        guard !candidates.isEmpty else { return stations }

        return await withTaskGroup(of: (Int, LicensedImage?).self, returning: [DateStation].self) { group in
            for (index, station) in candidates {
                group.addTask {
                    (index, await WikimediaImageResolver.resolve(for: station, city: city))
                }
            }

            var imagesByIndex: [Int: LicensedImage] = [:]
            for await (index, image) in group {
                if let image {
                    imagesByIndex[index] = image
                }
            }

            return stations.enumerated().map { index, station in
                guard let image = imagesByIndex[index] else { return station }
                var enriched = station
                enriched.licensedImage = image
                return enriched
            }
        }
    }
}
