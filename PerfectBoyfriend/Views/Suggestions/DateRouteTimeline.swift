import SwiftUI

/// A spatial itinerary. Suggested dates use the immersive layout; saved dates offer the same
/// scene embedded in their existing details with an explicit full-screen expansion.
struct DateRouteTimeline: View {
    let stations: [DateStation]
    let startingAt: Date
    var isResolving = false
    var isGeneratingVisuals = false
    var immersive = false
    var city = ""
    var routeTitle = "Euer Abend"
    var onPlan: (() -> Void)?
    @StateObject private var presentation: DateRoutePresentation
    @State private var isExpanded = false
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(stations: [DateStation], startingAt: Date, isResolving: Bool = false, isGeneratingVisuals: Bool = false,
         immersive: Bool = false, city: String = "", routeTitle: String = "Euer Abend", onPlan: (() -> Void)? = nil) {
        self.stations = stations
        self.startingAt = startingAt
        self.isResolving = isResolving
        self.isGeneratingVisuals = isGeneratingVisuals
        self.immersive = immersive
        self.city = city
        self.routeTitle = routeTitle
        self.onPlan = onPlan
        _presentation = StateObject(wrappedValue: DateRoutePresentation(
            stations: stations,
            startingAt: startingAt,
            isShowingVisualPlaceholder: isGeneratingVisuals
        ))
    }

    var body: some View {
        Group {
            if immersive { experience }
            else {
                experience
                    .frame(height: 580)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay(alignment: .topTrailing) {
                        Button { isExpanded = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44)
                                .background(PBTheme.midnight.opacity(0.85), in: Circle())
                        }
                        .accessibilityLabel("Route im Vollbild erkunden")
                        .padding(12)
                    }
            }
        }
        .foregroundStyle(PBTheme.textOnDark)
        .onAppear { isVisible = true; presentation.resumeLoading() }
        .onDisappear { isVisible = false; presentation.stopLoading() }
        .onChange(of: stations) { _, value in presentation.update(stations: value, startingAt: startingAt) }
        .onChange(of: startingAt) { _, value in presentation.update(stations: stations, startingAt: value) }
        .onChange(of: isGeneratingVisuals) { _, value in presentation.setVisualLoading(value) }
        .fullScreenCover(isPresented: $isExpanded) {
            NavigationStack {
                DateRouteTimeline(stations: stations, startingAt: startingAt, isResolving: isResolving,
                                  isGeneratingVisuals: isGeneratingVisuals,
                                  immersive: true, city: city, routeTitle: routeTitle)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { isExpanded = false } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Route schließen")
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
    }

    private var experience: some View {
        GeometryReader { proxy in
            ZStack {
                Color(cgColor: DateRouteScene.navy).ignoresSafeArea()
                DateRouteSceneView(presentation: presentation, reduceMotion: reduceMotion,
                                   isActive: scenePhase == .active && isVisible && !isExpanded,
                                   allowsVerticalNavigation: immersive)
                    .ignoresSafeArea(edges: immersive ? [.bottom] : [])
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color(cgColor: DateRouteScene.navy), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: immersive ? 180 : 95)
                    Spacer()
                    LinearGradient(colors: [.clear, Color(cgColor: DateRouteScene.navy)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: immersive ? 180 : 140)
                }
                .ignoresSafeArea(edges: immersive ? [.bottom] : [])
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    if presentation.detailIndex == nil { header }
                    Spacer(minLength: 0)
                    if let stop = presentation.detailStop, let index = presentation.detailIndex {
                        detailPanel(stop, image: presentation.displayedPhotos[index] ?? stop.station.licensedImage,
                                    isVisualLoading: isGeneratingVisuals)
                            .frame(maxHeight: proxy.size.height * 0.46)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        navigationControls
                            .padding(.horizontal, 22)
                            .padding(.bottom, immersive ? 14 : 20)
                    }
                }
                .ignoresSafeArea(edges: immersive ? [.bottom] : [])
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: presentation.detailIndex)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if !city.isEmpty {
                Text(city.uppercased())
                    .font(.system(size: 11, weight: .medium)).tracking(4)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Text(immersive ? "Euer Abend" : "Eure Route")
                .font(.system(size: immersive ? 38 : 27, weight: .ultraLight))
            Text(immersive ? routeTitle : "\(stations.count) Orte. Zeit für euch.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if isGeneratingVisuals {
                HStack(spacing: 7) {
                    RouteVisualLoadingIndicator()
                    Text("Eure Motive entstehen gerade")
                }
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, immersive ? 18 : 22)
        .allowsHitTesting(false)
    }

    private var navigationControls: some View {
        VStack(spacing: 13) {
            if stations.isEmpty {
                Text("Für dieses Date sind noch keine Stationen vorhanden.")
                    .font(.system(size: 15, weight: .light))
                    .multilineTextAlignment(.center)
            }
            if let stop = presentation.selectedStop {
                HStack(spacing: 10) {
                    navigationArrow("chevron.left", disabled: presentation.selectedIndex == 0) {
                        presentation.travel(to: Float(presentation.selectedIndex - 1), animated: true, reduceMotion: reduceMotion)
                    }
                    Button { presentation.open(presentation.selectedIndex, reduceMotion: reduceMotion) } label: {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d / %02d", presentation.selectedIndex + 1, stations.count))
                                .monospacedDigit()
                            Text("·")
                            Text(stop.station.resolvedPlace?.name ?? stop.station.title).lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .light))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(Color(cgColor: DateRouteScene.navy).opacity(0.94), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Station \(presentation.selectedIndex + 1): \(stop.station.title). Details öffnen")
                    navigationArrow("chevron.right", disabled: presentation.selectedIndex >= stations.count - 1) {
                        presentation.travel(to: Float(presentation.selectedIndex + 1), animated: true, reduceMotion: reduceMotion)
                    }
                }
                Text("Wischen, um die Route zu erkunden")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            if let onPlan {
                Button(action: onPlan) {
                    HStack {
                        Text("Dieses Date planen")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(PBTheme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func navigationArrow(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .frame(width: 44, height: 48)
                .background(Color(cgColor: DateRouteScene.navy).opacity(0.8), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(symbol == "chevron.left" ? "Vorherige Station" : "Nächste Station")
    }

    private func detailPanel(_ stop: DateRouteStop, image: LicensedImage?, isVisualLoading: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Capsule().fill(.white.opacity(0.27)).frame(width: 30, height: 3)
                Spacer()
                Button { presentation.close(reduceMotion: reduceMotion) } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                }.accessibilityLabel("Zurück zur Route")
            }
            .padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(stop.station.resolvedPlace?.name ?? stop.station.title)
                        .font(.system(size: 28, weight: .light))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(stop.startsAt.miteTimeText)–\(stop.endsAt.miteTimeText) · \(stop.station.estimatedDurationMinutes) Min")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    Text(stop.station.description)
                        .font(.system(size: 15, weight: .light))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let transfer = stop.station.arrivalTransfer {
                        Text("Anreise: ca. \(transfer.minutes) Min · \(transfer.transport)")
                            .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    if let place = stop.station.resolvedPlace {
                        Label(place.address, systemImage: "mappin")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    if let url = mapsURL(for: stop.station) {
                        Link(destination: url) {
                            HStack { Text("Ort ansehen"); Spacer(); Image(systemName: "arrow.up.right") }
                                .font(.system(size: 14, weight: .medium))
                                .padding(16)
                                .background(PBTheme.accent.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if isResolving {
                        Text("Orte werden bestätigt …").font(PBTheme.Typography.caption)
                    }
                    if isVisualLoading {
                        Text("Das Motiv für diese Station entsteht gerade.")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    } else if let image {
                        LicensedImageCredit(image: image, foregroundColor: PBTheme.textOnDarkSecondary)
                    }
                    Text("Öffnungszeiten und Reservierung bitte beim Ort prüfen.")
                        .font(.system(size: 11)).foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color(cgColor: DateRouteScene.navy).opacity(0.98))
                .ignoresSafeArea(edges: immersive ? [.bottom] : [])
        }
        .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.18)).frame(height: 0.6).padding(.horizontal, 26) }
    }

    private func mapsURL(for station: DateStation) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        if let place = station.resolvedPlace {
            components.queryItems = [.init(name: "ll", value: "\(place.latitude),\(place.longitude)"),
                                    .init(name: "q", value: place.name)]
        } else {
            components.queryItems = [.init(name: "q", value: station.searchQueryHint)]
        }
        return components.url
    }
}

/// A short flowing route replaces the platform spinner while images are composed. It echoes the
/// 3D road beneath it without adding another circular, attention-seeking control.
private struct RouteVisualLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                bars(phase: 0.55)
            } else {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                    bars(phase: phase)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bars(phase: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                let shifted = (phase + Double(index) * 0.22).truncatingRemainder(dividingBy: 1)
                Capsule()
                    .fill(PBTheme.textOnDark)
                    .frame(width: 3, height: 6 + CGFloat(shifted) * 8)
                    .opacity(0.35 + shifted * 0.65)
            }
        }
        .frame(width: 19, height: 15)
    }
}
