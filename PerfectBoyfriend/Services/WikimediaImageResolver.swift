import Foundation

/// Finds a reusable *photograph* for a verified MapKit place. We first require the Commons file
/// title to match that venue exactly. Small businesses often have no Commons photo, so we then
/// look for a real, openly licensed photo matching the activity in that city. Attribution stays
/// attached either way; no generated imagery or uncredited image search results are used.
enum WikimediaImageResolver {
    private static let endpoint = URL(string: "https://commons.wikimedia.org/w/api.php")!

    static func resolve(for station: DateStation, city: String) async -> LicensedImage? {
        // Photo lookup is cosmetic and must never hold the whole suggestions screen hostage.
        // This per-stop budget also guarantees that `enrichPhotos` returns its partial successes
        // instead of the caller falling back to an all-empty pre-enrichment result.
        return try? await withTimeout(seconds: 11) {
            await resolveWithinBudget(for: station, city: city)
        }
    }

    private static func resolveWithinBudget(for station: DateStation, city: String) async -> LicensedImage? {
        // MapKit is the source of truth before a date can be saved, but visuals should not be
        // withheld merely because a preliminary map lookup was slow. A concrete AI station title
        // and its city are still enough to find an attributed contextual photograph.
        let venueCandidates = [
            station.resolvedPlace?.name,
            station.searchQueryHint,
            station.title,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        // A previous version tried every wording serially. One slow, unknown venue could then
        // consume the full screen's photo deadline and discard all images. The strongest venue
        // name is enough for the exact attempt; broad activity and city fallbacks run in parallel.
        if let venue = venueCandidates.first {
            let query = "\(venue) \(city)".trimmingCharacters(in: .whitespacesAndNewlines)
            if let image = await search(query: query, expectedVenue: query) {
                return image
            }
        }

        async let activityPhoto = searchActivityPhoto(query: "\(station.category.photoSearchTerm) \(city)")
        async let cityPhoto = searchActivityPhoto(query: city)

        if let image = await activityPhoto {
            var contextual = image
            contextual.contextLabel = "Umgebungsfoto · \(city), nicht der konkrete Betrieb"
            return contextual
        }
        // A city photograph is the final, always-relevant visual fallback. It is deliberately
        // labelled as atmosphere rather than pretending to show a venue that has no photo.
        if let image = await cityPhoto {
            var contextual = image
            contextual.contextLabel = "Stimmungsfoto aus \(city), nicht der konkrete Betrieb"
            return contextual
        }
        return nil
    }

    private static func search(query: String, expectedVenue: String) async -> LicensedImage? {
        let pages = await pages(for: query)
        return pages
            .filter { pageTitleMatchesVenue($0.title, venue: expectedVenue) }
            .compactMap { licensedImage(from: $0, requiresPhotograph: true) }
            .first
    }

    private static func searchActivityPhoto(query: String) async -> LicensedImage? {
        let candidates = await pages(for: query)
        return candidates
            .compactMap { licensedImage(from: $0, requiresPhotograph: true) }
            .first
    }

    private static func pages(for query: String) async -> [CommonsPage] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "6"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata|mime"),
            URLQueryItem(name: "iiurlwidth", value: "1200"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]
        guard let url = components.url,
              !Task.isCancelled,
              let (data, response) = try? await withTimeout(seconds: 5, operation: { try await URLSession.shared.data(from: url) }),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let result = try? JSONDecoder().decode(CommonsSearchResponse.self, from: data) else {
            return []
        }

        return result.query?.pages?.values
            .sorted { $0.index ?? .max < $1.index ?? .max }
            ?? []
    }

    private static func pageTitleMatchesVenue(_ pageTitle: String?, venue: String) -> Bool {
        guard let pageTitle else { return false }
        let venueTokens = significantTokens(in: venue)
        let titleTokens = Set(significantTokens(in: pageTitle))
        guard !venueTokens.isEmpty else { return false }

        let matchingTokenCount = venueTokens.filter(titleTokens.contains).count
        // A one-word venue (e.g. "Con:Text") needs that word, while a longer unique place name
        // needs at least half of its meaningful terms in the file title before we show the image.
        return matchingTokenCount >= max(1, (venueTokens.count + 1) / 2)
    }

    private static func significantTokens(in value: String) -> [String] {
        let ignored = Set(["der", "die", "das", "am", "an", "im", "in", "bei", "zum", "zur", "cafe", "restaurant", "bar"])
        return value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !ignored.contains($0) }
    }

    private static func licensedImage(from page: CommonsPage, requiresPhotograph: Bool) -> LicensedImage? {
        guard let info = page.imageInfo?.first,
              let url = info.thumbURL ?? info.url,
              let sourcePageURL = info.descriptionURL,
              let metadata = info.extMetadata else {
            return nil
        }

        let license = metadata["LicenseShortName"]?.value.strippingHTML ?? ""
        guard isAcceptedLicence(license), (!requiresPhotograph || isPhotograph(info)) else { return nil }
        // File type alone cannot distinguish a photograph from a map or a drawing.
        let description = [page.title ?? "", metadata["Categories"]?.value ?? "", metadata["ImageDescription"]?.value ?? ""].joined(separator: " ").lowercased()
        guard !["illustration", "drawing", "painting", "lithograph", "floor plan", "logo", "ai-generated", "ai generated", "map of"].contains(where: description.contains) else { return nil }

        let creator = (metadata["Artist"]?.value.strippingHTML ?? "Wikimedia Commons")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let licenseURL = metadata["LicenseUrl"]?.value
        return LicensedImage(
            url: url,
            sourcePageURL: sourcePageURL,
            creator: creator.isEmpty ? "Wikimedia Commons" : creator,
            license: license,
            licenseURL: licenseURL
        )
    }

    private static func isAcceptedLicence(_ license: String) -> Bool {
        let normalized = license.uppercased()
        guard !normalized.contains("NC"), !normalized.contains("ND") else { return false }
        return normalized.contains("CC0")
            || normalized.contains("PUBLIC DOMAIN")
            || normalized.contains("CC BY")
    }

    private static func isPhotograph(_ info: CommonsImageInfo) -> Bool {
        // JPEG and WebP are the reliable photographic media types returned by Commons. SVG,
        // maps, icons and illustrations are intentionally left out of this visual system.
        let mime = info.mimeType?.lowercased() ?? ""
        return mime == "image/jpeg" || mime == "image/webp"
    }
}

private struct CommonsSearchResponse: Decodable {
    var query: CommonsQuery?
}

private struct CommonsQuery: Decodable {
    var pages: [String: CommonsPage]?
}

private struct CommonsPage: Decodable {
    var title: String?
    var index: Int?
    var imageInfo: [CommonsImageInfo]?

    private enum CodingKeys: String, CodingKey {
        case index, title
        case imageInfo = "imageinfo"
    }
}

private struct CommonsImageInfo: Decodable {
    var url: String?
    var thumbURL: String?
    var descriptionURL: String?
    var mimeType: String?
    var extMetadata: [String: CommonsMetadataValue]?

    private enum CodingKeys: String, CodingKey {
        case url
        case thumbURL = "thumburl"
        case descriptionURL = "descriptionurl"
        case mimeType = "mime"
        case extMetadata = "extmetadata"
    }
}

private struct CommonsMetadataValue: Decodable {
    var value: String
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
