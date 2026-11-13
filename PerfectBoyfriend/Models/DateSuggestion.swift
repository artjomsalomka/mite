import Foundation

/// Mirrors DateStation/DateSuggestion in functions/src/dateSuggestions/types.ts — this is the
/// JSON contract returned by the generateDateSuggestions callable Function.
enum StationCategory: String, Codable, Sendable {
    case restaurant, cafe, bar, park, museum, cinema, theater, sight, activity, shopping, nature, nightlife, other
}

struct DateStation: Codable, Identifiable, Equatable, Sendable {
    var order: Int
    var title: String
    var category: StationCategory
    var searchQueryHint: String
    var description: String
    var estimatedDurationMinutes: Int

    var id: Int { order }

    /// Filled in client-side by PlaceResolver once this suggestion is selected. The
    /// generateDateSuggestions response never includes this key, which decodes fine as nil —
    /// but it MUST stay in the Codable contract so SavedDateService can persist it to Firestore
    /// once resolved (a prior version excluded it entirely, which silently dropped resolved
    /// places on save).
    var resolvedPlace: ResolvedPlace?

    /// A freely reusable illustration found from the verified place name. It is never an
    /// uncredited scraped image: the source page, creator and license travel with it.
    var licensedImage: LicensedImage?

    /// Travel from the previous stop. Missing on older plans; their timeline explicitly states
    /// that travel has not been calculated instead of inventing a zero-minute connection.
    var arrivalTransfer: DateTransfer? = nil
}

struct DateSuggestion: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var summary: String
    var moodTags: [String]
    var estimatedBudgetLevel: BudgetLevel
    var estimatedTotalDurationMinutes: Int
    var stations: [DateStation]

    /// A route is only ready to become a shared plan once every stop has been verified by
    /// MapKit. The language model proposes the intent, but it must never be the source of
    /// truth for a place a couple can actually visit.
    var resolvedStationCount: Int {
        stations.reduce(into: 0) { count, station in
            if station.resolvedPlace != nil { count += 1 }
        }
    }

    var hasConfirmedPlaces: Bool {
        !stations.isEmpty && resolvedStationCount == stations.count
    }
}

struct GenerateDateSuggestionsResponse: Codable, Sendable {
    var requestId: String
    var suggestions: [DateSuggestion]
}

/// Populated client-side via MKLocalSearch — see Services/PlaceResolver.swift (Milestone 6).
struct ResolvedPlace: Codable, Equatable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var phoneNumber: String?
    var url: String?
}

/// Metadata that makes a remotely displayed Creative Commons / public-domain image usable in a
/// product UI. `sourcePageURL` points to the original file page; `licenseURL` exposes the full
/// licence terms instead of relying on an ambiguous text-only credit.
struct LicensedImage: Codable, Equatable, Sendable {
    var url: String
    var sourcePageURL: String
    var creator: String
    var license: String
    var licenseURL: String?
    var contextLabel: String? = nil

    var creditLine: String {
        "\(license == "KI-Stimmungsbild" ? "Bild" : "Foto"): \(creator) · \(license)"
    }
}

struct DateTransfer: Codable, Equatable, Sendable {
    var minutes: Int
    var distanceMeters: Double
    var transport: String
    var isEstimate: Bool
}

struct DateRouteStop: Identifiable {
    let station: DateStation
    let startsAt: Date
    let endsAt: Date
    var id: Int { station.id }
}

enum DateSchedule {
    static func stops(_ stations: [DateStation], startingAt: Date) -> [DateRouteStop] {
        var cursor = startingAt
        return stations.sorted { $0.order < $1.order }.enumerated().map { index, station in
            if index > 0 {
                cursor = cursor.addingTimeInterval(Double(max(0, station.arrivalTransfer?.minutes ?? 0)) * 60)
            }
            let end = cursor.addingTimeInterval(Double(max(0, station.estimatedDurationMinutes)) * 60)
            defer { cursor = end }
            return DateRouteStop(station: station, startsAt: cursor, endsAt: end)
        }
    }

    static func totalMinutes(_ stations: [DateStation]) -> Int {
        let start = Date(timeIntervalSince1970: 0)
        return Int((stops(stations, startingAt: start).last?.endsAt.timeIntervalSince(start) ?? 0) / 60)
    }

    static func shareText(title: String, stations: [DateStation], startingAt: Date) -> String {
        let steps = stops(stations, startingAt: startingAt).map { stop in
            let place = stop.station.resolvedPlace
            let location = place.map { "\($0.name), \($0.address)" } ?? stop.station.title
            let time = stop.startsAt.miteTimeText
            let transfer = stop.station.arrivalTransfer.map { "\nAnreise: ca. \($0.minutes) Min (\($0.transport))." } ?? ""
            return "\(time) · \(stop.station.title)\n\(location)\n\(stop.station.description)\(transfer)"
        }
        return ([title, startingAt.miteCompleteDateText] + steps
            + ["Zeitplan als Orientierung. Öffnungszeiten und Reservierungen vorab prüfen."]).joined(separator: "\n\n")
    }
}
