import Foundation

/// A small local collection of real, freely licensed atmosphere photos. These are used only when
/// a concrete venue has no usable Commons photograph, avoiding blank cards or map screenshots
/// while never implying that the generic photo depicts that exact business.
enum DateVisualFallbackLibrary {
    static func image(for category: StationCategory) -> LicensedImage {
        switch category {
        case .restaurant:
            dining
        case .cafe:
            cafe
        case .bar, .nightlife:
            evening
        case .park, .nature, .activity:
            outdoors
        case .museum, .cinema, .theater, .sight:
            culture
        case .shopping, .other:
            evening
        }
    }

    private static let dining = bundled(
        asset: "date-fallback-dining",
        creator: "Wikimedia Commons",
        license: "CC BY-SA 4.0",
        source: "https://commons.wikimedia.org/wiki/File:Childs%27_Restaurant_building_interior_(84200).jpg",
        label: "Stimmungsfoto · Restaurant, nicht der konkrete Betrieb"
    )

    private static let cafe = bundled(
        asset: "date-fallback-cafe",
        creator: "Bob Harvey",
        license: "CC BY-SA 2.0",
        source: "https://commons.wikimedia.org/wiki/File:Cafe_Interior_-_geograph.org.uk_-_4801988.jpg",
        label: "Stimmungsfoto · Café, nicht der konkrete Betrieb"
    )

    private static let outdoors = bundled(
        asset: "date-fallback-outdoors",
        creator: "Rohit Sharma",
        license: "CC BY-SA 4.0",
        source: "https://commons.wikimedia.org/wiki/File:Bamboo-Lined_Forest_Trail_in_Tadoba_Andhari_National_Park.jpg",
        label: "Stimmungsfoto · Spaziergang in der Natur"
    )

    private static let culture = bundled(
        asset: "date-fallback-culture",
        creator: "Wikimedia Commons",
        license: "CC BY 4.0",
        source: "https://commons.wikimedia.org/wiki/File:Interior_and_museum_gallery_of_the_Victoria_Memorial,_in_Kolkata_04.jpg",
        label: "Stimmungsfoto · Kulturort, nicht der konkrete Betrieb"
    )

    private static let evening = bundled(
        asset: "date-fallback-evening",
        creator: "Chensiyuan",
        license: "CC BY-SA 3.0",
        source: "https://commons.wikimedia.org/wiki/File:1_rocinha_night_2014_panorama.jpg",
        label: "Stimmungsfoto · Abend in der Stadt"
    )

    private static func bundled(
        asset: String,
        creator: String,
        license: String,
        source: String,
        label: String
    ) -> LicensedImage {
        LicensedImage(
            url: "bundle://\(asset)",
            sourcePageURL: source,
            creator: creator,
            license: license,
            licenseURL: nil,
            contextLabel: label
        )
    }
}

extension DateStation {
    /// The UI always has a photo-shaped visual: an exact or contextual venue image when found,
    /// otherwise a clearly labelled, bundled activity photo with its original licence retained.
    var displayImage: LicensedImage {
        licensedImage ?? DateVisualFallbackLibrary.image(for: category)
    }
}
