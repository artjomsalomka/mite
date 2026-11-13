import CoreLocation
import MapKit

extension StationCategory {
    /// Partial by design — only categories with a clean 1:1 MapKit equivalent get a filter; the
    /// rest rely purely on the natural-language search query text.
    var mkPointOfInterestCategory: MKPointOfInterestCategory? {
        switch self {
        case .restaurant: return .restaurant
        case .cafe: return .cafe
        case .museum: return .museum
        case .park: return .park
        case .cinema: return .movieTheater
        case .theater: return .theater
        case .bar, .nightlife: return .nightlife
        case .sight, .activity, .shopping, .nature, .other: return nil
        }
    }
}

extension ResolvedPlace {
    init(from mapItem: MKMapItem) {
        self.init(
            name: mapItem.name ?? "Unbekannter Ort",
            address: Self.formattedAddress(from: mapItem.placemark),
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude,
            phoneNumber: mapItem.phoneNumber,
            url: mapItem.url?.absoluteString
        )
    }

    private static func formattedAddress(from placemark: MKPlacemark) -> String {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let locality = placemark.locality ?? placemark.administrativeArea ?? ""
        let address = [street, locality]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return address.isEmpty ? "Adresse in Apple Maps prüfen" : address
    }
}

/// Resolves each DateStation's Claude-authored search-query hint into a real nearby place via
/// MKLocalSearch — deliberately client-side (see the plan's rationale: Apple's Maps Server API
/// would need a paid Developer Program JWT setup, not worth it for Phase 1). It may run once
/// while suggestions load and again for still-unresolved stations in the detail screen.
enum PlaceResolver {
    enum ResolutionResult {
        case resolved(ResolvedPlace)
        case unresolved
    }

    static func resolve(
        station: DateStation,
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 15_000,
        city: String = ""
    ) async -> ResolutionResult {
        // A single strict lookup (exact hint + category filter) failed far too often: MapKit
        // categorises many real venues differently from the language model's wording, and a
        // descriptive hint such as "Tapas Restaurant mit Terrasse" matches nothing at all. Try a
        // few progressively looser queries, each still bound to the requested radius, and only
        // then give up. Loosening never substitutes a generic venue for a specific one: every
        // attempt searches for this station's own name or hint.
        var attempts: [(query: String, useCategory: Bool)] = []
        let hint = station.searchQueryHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCategory = station.category.mkPointOfInterestCategory != nil
        if !hint.isEmpty {
            attempts.append((hint, hasCategory))
            if hasCategory { attempts.append((hint, false)) }
        }
        let title = station.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityName = city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let query = cityName.isEmpty || title.localizedCaseInsensitiveContains(cityName) ? title : "\(title) \(cityName)"
            attempts.append((query, false))
        }
        var seen = Set<String>()
        attempts = attempts.filter { seen.insert("\($0.query.lowercased())|\($0.useCategory)").inserted }
        // The timeout operation is @Sendable. Capture an immutable value so this remains valid
        // when the target moves to Swift 6's strict concurrency checking.
        let lookupAttempts = attempts

        let found: MKMapItem? = try? await withTimeout(seconds: 16) {
            for attempt in lookupAttempts {
                if let item = await search(query: attempt.query, category: attempt.useCategory ? station.category : nil,
                                           near: coordinate, radiusMeters: radiusMeters) {
                    return item
                }
            }
            return nil
        }
        guard let found else { return .unresolved }
        return .resolved(ResolvedPlace(from: found))
    }

    private static func search(
        query: String,
        category: StationCategory?,
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radiusMeters, longitudinalMeters: radiusMeters)
        if let filterCategory = category?.mkPointOfInterestCategory {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [filterCategory])
        }

        // MapKit throttles bursts of lookups (every station of every suggestion starts at once).
        // A throttled or briefly failing request is retried once instead of being read as "this
        // place does not exist".
        var response: MKLocalSearch.Response?
        for attempt in 0..<2 {
            response = try? await withTimeout(seconds: 6, operation: {
                try await MKLocalSearch(request: request).start()
            })
            if response != nil { break }
            if attempt == 0 { try? await Task.sleep(for: .milliseconds(700)) }
        }
        guard let response else { return nil }

        // MKLocalSearch's `region` is only a bias, not a hard filter — a strong text match for a
        // same-named venue can come back from far outside it (seen live: a "Tapas Restaurant ...
        // in Marburg" query resolved to a same-named place ~80km away in Kronberg im Taunus).
        // `mapItems` is ordered by MapKit's text relevance, which we keep (for "La Siesta
        // Marburg" a closer, unrelated tapas place must not replace the intended venue), while
        // the radius stays a hard boundary so a same-named result in another city is skipped.
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let maxDistance = radiusMeters * 1.5
        return response.mapItems.first {
            center.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)) <= maxDistance
        }
    }

    /// Resolves every station of a suggestion concurrently, each independently — one slow or
    /// failed lookup never blocks the rest. Returns stations in their original order with
    /// `resolvedPlace` filled in where a match was found.
    static func resolveAll(stations: [DateStation], near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance = 15_000, city: String = "") async -> [DateStation] {
        await withTaskGroup(of: (Int, ResolvedPlace?).self) { group in
            for station in stations {
                group.addTask {
                    switch await resolve(station: station, near: coordinate, radiusMeters: radiusMeters, city: city) {
                    case .resolved(let place): return (station.order, place)
                    case .unresolved: return (station.order, nil)
                    }
                }
            }
            var resolvedByOrder: [Int: ResolvedPlace] = [:]
            for await (order, place) in group {
                if let place { resolvedByOrder[order] = place }
            }
            return stations.map { station in
                var updated = station
                updated.resolvedPlace = resolvedByOrder[station.order]
                return updated
            }
        }
    }
}
