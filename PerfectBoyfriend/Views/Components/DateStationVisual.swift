import SwiftUI

/// A date stop only displays its own generated or attributed visual. Older bundled stock
/// fallbacks are deliberately not used in the planning preview: until the route's image exists,
/// the app shows a composed neutral surface rather than suggesting the wrong venue or activity.
struct DateStationVisual: View {
    let station: DateStation

    var body: some View {
        ZStack {
            if let image = station.licensedImage {
                LicensedImageView(image: image)
                    .id(image.url)
            } else {
                DateStationVisualPlaceholder(category: station.category)
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.25)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct DateStationVisualPlaceholder: View {
    let category: StationCategory

    var body: some View {
        ZStack {
            LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 170, height: 170).offset(x: 74, y: -44)
            Image(systemName: category.routeSymbolName)
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .frame(width: 66, height: 66)
                .background(.white.opacity(0.08), in: Circle())
        }
    }
}

extension StationCategory {
    var routeSymbolName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar, .nightlife: return "wineglass"
        case .park, .nature: return "leaf"
        case .museum: return "building.columns"
        case .cinema: return "film"
        case .theater: return "theatermasks"
        case .sight: return "binoculars"
        case .activity: return "figure.walk"
        case .shopping: return "bag"
        case .other: return "sparkles"
        }
    }

    var photoSearchTerm: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .bar, .nightlife: return "Abend"
        case .park, .nature: return "Natur"
        case .museum, .sight: return "Sehenswürdigkeit"
        case .cinema, .theater: return "Kultur"
        case .activity: return "Freizeit"
        case .shopping: return "Innenstadt"
        case .other: return "Stadt"
        }
    }
}
