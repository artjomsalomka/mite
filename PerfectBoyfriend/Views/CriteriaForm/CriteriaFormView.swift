import SwiftUI

struct CriteriaFormView: View {
    private let couple: Couple?
    private let scope: DatePlanningScope
    let savedDateService: SavedDateService
    private let audience: PlanningAudience
    private let showsDismissButton: Bool
    private let onPlanSaved: (PlanningMode) -> Void
    @StateObject private var viewModel: CriteriaFormViewModel
    @State private var activeCriterion: PlanningCriterion?
    @State private var showsSuggestions = false
    @Environment(\.dismiss) private var dismiss

    init(
        couple: Couple,
        savedDateService: SavedDateService,
        profileCity: String = "",
        audience: PlanningAudience = .date,
        showsDismissButton: Bool = false,
        onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }
    ) {
        self.couple = couple
        self.scope = .couple(id: couple.id ?? "")
        self.savedDateService = savedDateService
        self.audience = audience
        self.showsDismissButton = showsDismissButton
        self.onPlanSaved = onPlanSaved
        var defaults = CriteriaDefaultsProvider.defaultCriteria(city: profileCity, dietaryPreferences: [])
        defaults.planningMode = audience.mode
        defaults.participantCount = audience.participantCount
        if audience.mode == .group, defaults.occasion == Occasion.erstesDate.rawValue {
            defaults.occasion = Occasion.spontan.rawValue
        }
        _viewModel = StateObject(wrappedValue: CriteriaFormViewModel(initialCriteria: defaults))
    }

    init(match: SingleMatchPreview, ownProfile: SingleProfile, savedDateService: SavedDateService) {
        var defaults = CriteriaDefaultsProvider.defaultCriteria(city: ownProfile.city, dietaryPreferences: [])
        defaults.budget = ownProfile.budgetPreference
        defaults.moods = ownProfile.moods
        defaults.occasion = Occasion.erstesDate.rawValue

        self.couple = nil
        self.scope = .singleMatch(id: match.matchId)
        self.savedDateService = savedDateService
        self.audience = .date
        self.showsDismissButton = false
        self.onPlanSaved = { _ in }
        _viewModel = StateObject(wrappedValue: CriteriaFormViewModel(initialCriteria: defaults))
    }

    init(
        personalUID: String,
        savedDateService: SavedDateService,
        profileCity: String,
        audience: PlanningAudience,
        showsDismissButton: Bool = true,
        onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }
    ) {
        self.couple = nil
        self.scope = .personal(id: personalUID)
        self.savedDateService = savedDateService
        self.audience = audience
        self.showsDismissButton = showsDismissButton
        self.onPlanSaved = onPlanSaved
        var defaults = CriteriaDefaultsProvider.defaultCriteria(city: profileCity, dietaryPreferences: [])
        defaults.planningMode = audience.mode
        defaults.participantCount = audience.participantCount
        if audience.mode == .group, defaults.occasion == Occasion.erstesDate.rawValue {
            defaults.occasion = Occasion.spontan.rawValue
        }
        _viewModel = StateObject(wrappedValue: CriteriaFormViewModel(initialCriteria: defaults))
    }

    @StateObject private var route = PlanningRoutePresentation()
    @State private var isPreparing = false
    @State private var advancesAfterDismiss = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            PlanningRouteView(
                route: route, criteria: viewModel.criteria,
                title: scope.isFirstMeeting ? "Erstes Date" : audience.routeTitle,
                isPreparing: isPreparing,
                isActive: !showsSuggestions && activeCriterion == nil,
                onSelect: { criterion in
                    route.select(criterion, reduceMotion: reduceMotion)
                    activeCriterion = criterion
                },
                onGenerate: generate,
                onClose: showsDismissButton ? { dismiss() } : nil
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsSuggestions) {
                SuggestionLoadingView(scope: scope, criteria: viewModel.criteria, audience: audience, savedDateService: savedDateService, onPlanSaved: onPlanSaved)
            }
            .sheet(item: $activeCriterion, onDismiss: {
                viewModel.commitTypedCity()
                route.update(criteria: viewModel.criteria)
                if advancesAfterDismiss {
                    route.travel(to: Float(route.selectedIndex + 1), animated: true, reduceMotion: reduceMotion)
                } else {
                    route.travel(to: route.progress, animated: true, reduceMotion: reduceMotion)
                }
                advancesAfterDismiss = false
            }) { criterion in
                PlanningCriterionSheet(
                    criterion: criterion, viewModel: viewModel,
                    dismiss: {
                        advancesAfterDismiss = true
                        activeCriterion = nil
                    }
                )
                .presentationDetents(criterion.detents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(PBTheme.Radius.hero)
                .presentationBackground(.clear)
            }
            .task {
                if let couple {
                    await viewModel.loadDefaults(memberUids: couple.memberUids)
                } else if case .personal(let uid) = scope {
                    await viewModel.loadDefaults(memberUids: [uid])
                }
            }
        }
    }

    private func generate() {
        guard !isPreparing, !showsSuggestions else { return }
        isPreparing = true
        Task { @MainActor in
            defer { isPreparing = false }
            if await viewModel.prepareForGeneration() {
                showsSuggestions = true
            } else {
                route.select(.location, reduceMotion: reduceMotion)
                activeCriterion = .location
            }
        }
    }
}

enum PlanningCriterion: String, Identifiable {
    case time
    case location
    case mood
    case budget
    case mobility
    case setting
    case details

    var id: String { rawValue }

    var title: String { title(in: .date) }

    /// Group plans have no "occasion" (a spontaneous date, an anniversary …); the last step is
    /// only about food and wishes, so it is named that way.
    func title(in mode: PlanningMode) -> String {
        if self == .details, mode == .group { return "Essen & Wünsche" }
        switch self {
        case .time: return "Zeit & Dauer"
        case .location: return "Standort"
        case .mood: return "Stimmung"
        case .budget: return "Budget"
        case .mobility: return "Mobilität"
        case .setting: return "Drinnen oder draußen"
        case .details: return "Anlass & Essen"
        }
    }

    var subtitle: String {
        switch self {
        case .time: return "Wann soll euer Date stattfinden und wie viel Zeit habt ihr?"
        case .location: return "Wählt die Stadt, in der ihr euch inspirieren lassen möchtet."
        case .mood: return "Ein bis drei Vibes reichen für einen treffenden Vorschlag."
        case .budget: return "Eine grobe Kategorie genügt – ihr müsst nichts ausrechnen."
        case .mobility: return "Wie weit und womit möchtet ihr unterwegs sein?"
        case .setting: return "Das Wetter darf gern mitentscheiden."
        case .details: return "Optional: Anlass und Essenswünsche verfeinern euren Plan."
        }
    }

    var symbol: String {
        switch self {
        case .time: return "clock"
        case .location: return "mappin"
        case .mood: return "heart"
        case .budget: return "eurosign"
        case .mobility: return "figure.walk"
        case .setting: return "sun.max"
        case .details: return "slider.horizontal.3"
        }
    }

    var detents: Set<PresentationDetent> {
        // Each setting is intentionally an immersive mini-screen rather than a small utility
        // sheet. A full detent gives every criterion room for its own visual interaction.
        [.large]
    }

    var accent: Color {
        switch self {
        case .time: return Color(red: 0.34, green: 0.52, blue: 0.88)
        case .location: return Color(red: 0.18, green: 0.59, blue: 0.67)
        case .mood: return Color(red: 0.56, green: 0.38, blue: 0.76)
        case .budget: return Color(red: 0.30, green: 0.64, blue: 0.52)
        case .mobility: return Color(red: 0.27, green: 0.47, blue: 0.76)
        case .setting: return Color(red: 0.74, green: 0.59, blue: 0.26)
        case .details: return Color(red: 0.42, green: 0.45, blue: 0.78)
        }
    }

    func heroLine(in mode: PlanningMode) -> String {
        if self == .details, mode == .group { return "Worauf hat eure Runde Lust?" }
        return heroLine
    }

    var heroLine: String {
        switch self {
        case .time: return "Gute Dates haben ihren eigenen Rhythmus."
        case .location: return "Jede gute Idee beginnt an einem echten Ort."
        case .mood: return "Die Richtung fühlt ihr meistens schon vor dem ersten Plan."
        case .budget: return "Wählt den Rahmen – nicht jeden einzelnen Euro."
        case .mobility: return "Wie ihr unterwegs seid, verändert das ganze Erlebnis."
        case .setting: return "Eure Kulisse darf mitentscheiden."
        case .details: return "Die kleinen Details machen aus einer Idee euren Plan."
        }
    }
}


/// Compact vector marks created from the app's own geometry rather than emoji or stock pictograms.
/// The same marks identify spatial planning cards and their focused setting editors.
struct PlanningCriterionGlyph: View {
    let criterion: PlanningCriterion

    var body: some View {
        ZStack {
            switch criterion {
            case .time:
                Circle()
                    .trim(from: 0.08, to: 0.84)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                    .rotationEffect(.degrees(-48))
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 9)
                    .offset(y: -3)
                Rectangle()
                    .fill(.white)
                    .frame(width: 7, height: 2)
                    .offset(x: 3, y: 3)

            case .location:
                Path { path in
                    path.move(to: CGPoint(x: 14, y: 27))
                    path.addCurve(to: CGPoint(x: 4, y: 11), control1: CGPoint(x: 7, y: 21), control2: CGPoint(x: 4, y: 16))
                    path.addCurve(to: CGPoint(x: 14, y: 2), control1: CGPoint(x: 4, y: 6), control2: CGPoint(x: 8, y: 2))
                    path.addCurve(to: CGPoint(x: 24, y: 11), control1: CGPoint(x: 20, y: 2), control2: CGPoint(x: 24, y: 6))
                    path.addCurve(to: CGPoint(x: 14, y: 27), control1: CGPoint(x: 24, y: 16), control2: CGPoint(x: 21, y: 21))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                Circle().fill(.white).frame(width: 5, height: 5).offset(y: -5)

            case .mood:
                Circle().stroke(.white, lineWidth: 2).frame(width: 14, height: 14).offset(x: -5, y: -3)
                Circle().stroke(.white, lineWidth: 2).frame(width: 14, height: 14).offset(x: 5, y: -3)
                Capsule().fill(.white).frame(width: 17, height: 2).offset(y: 8)

            case .budget:
                VStack(spacing: 3) {
                    Capsule().fill(.white).frame(width: 11, height: 3)
                    Capsule().fill(.white.opacity(0.82)).frame(width: 18, height: 3)
                    Capsule().fill(.white.opacity(0.64)).frame(width: 24, height: 3)
                }

            case .mobility:
                Path { path in
                    path.move(to: CGPoint(x: 2, y: 21))
                    path.addCurve(to: CGPoint(x: 26, y: 7), control1: CGPoint(x: 10, y: 4), control2: CGPoint(x: 19, y: 28))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: -12, y: 7)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: 12, y: -7)

            case .setting:
                Circle().stroke(.white, lineWidth: 2).frame(width: 11, height: 11)
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: 2, height: 6)
                        .offset(y: -11)
                        .rotationEffect(.degrees(Double(index) * 60))
                }

            case .details:
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle().fill(.white).frame(width: 4, height: 4)
                        Capsule().fill(.white).frame(width: 16, height: 2)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.white.opacity(0.82)).frame(width: 4, height: 4)
                        Capsule().fill(.white.opacity(0.82)).frame(width: 11, height: 2)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.white.opacity(0.64)).frame(width: 4, height: 4)
                        Capsule().fill(.white.opacity(0.64)).frame(width: 18, height: 2)
                    }
                }
            }
        }
        .foregroundStyle(criterion.accent)
    }
}

private struct PlanningCriterionSheet: View {
    let criterion: PlanningCriterion
    @ObservedObject var viewModel: CriteriaFormViewModel
    let dismiss: () -> Void
    @StateObject private var citySearch = CitySearchService()
    @FocusState private var isCityFieldFocused: Bool

    var body: some View {
        ZStack {
            sheetBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        sheetHero
                        editorContent
                        Spacer(minLength: PBTheme.Spacing.lg)
                        restingScene
                    }
                    // Compact editors no longer leave an accidental empty lower half. The
                    // signature scene is intentionally anchored near the action instead.
                    .frame(minHeight: max(0, proxy.size.height - PBTheme.Spacing.md), alignment: .top)
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.sm)
                }
                .scrollIndicators(.hidden)
            }
        }
        // Reserve a stationary header gutter so even scrolled content stays below the grabber.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 28).allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if criterion == .location { viewModel.commitTypedCity() }
                dismiss()
            } label: {
                Label("Auswahl übernehmen", systemImage: "checkmark")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(criterion.accent, in: Capsule())
                    .shadow(color: criterion.accent.opacity(0.44), radius: 16, y: 7)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.vertical, PBTheme.Spacing.sm)
            .background(PBTheme.midnight.opacity(0.94))
        }
        .tint(criterion.accent)
        .preferredColorScheme(.dark)
    }

    private var sheetBackground: some View {
        ZStack {
            PBTheme.midnight
            RadialGradient(
                colors: [criterion.accent.opacity(0.40), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 480
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var sheetHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [criterion.accent.opacity(0.76), PBTheme.midnightRaised.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 188, height: 188)
                .offset(x: 150, y: -62)
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 122, height: 122)
                .offset(x: 170, y: 74)

            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                Image(systemName: criterion.symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.16), in: Circle())

                Text(criterion.title(in: viewModel.criteria.planningMode))
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                Text(criterion.heroLine(in: viewModel.criteria.planningMode))
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .lineLimit(2)
            }
            .padding(PBTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 186)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var restingScene: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(criterion.accent.opacity(0.42), lineWidth: 1)
                    .frame(width: 52, height: 52)
                PlanningCriterionGlyph(criterion: criterion)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Euer Plan nimmt Form an")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text(restingSceneLine)
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 1 ? criterion.accent : .white.opacity(0.18))
                        .frame(width: index == 1 ? 8 : 5, height: index == 1 ? 8 : 5)
                }
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
    }

    private var restingSceneLine: String {
        switch criterion {
        case .time: return "Zeit und Dauer werden später zu einer stimmigen Route verbunden."
        case .location: return "Echte Orte werden in eurer Stadt für euch zusammengestellt."
        case .mood: return "Eure Vibes geben der Idee ihre eigene Richtung."
        case .budget: return "Der Rahmen hilft, passende Orte auszuwählen."
        case .mobility: return "Die Route bleibt in dem Radius, der zu euch passt."
        case .setting: return "Eure Kulisse wird bei den Vorschlägen berücksichtigt."
        case .details: return "Die Feinheiten werden in eurem Vorschlag mitgedacht."
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        switch criterion {
        case .location:
            locationExperience

        case .mood:
            moodExperience

        case .time:
            timeExperience

        case .budget:
            budgetExperience

        case .mobility:
            mobilityExperience

        case .setting:
            settingExperience

        case .details:
            detailsExperience
        }
    }

    private var locationExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Wo soll eure Geschichte heute beginnen?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .stroke(criterion.accent.opacity(0.22), lineWidth: 1)
                        .frame(width: CGFloat(86 + index * 54), height: CGFloat(86 + index * 54))
                }
                VStack(spacing: PBTheme.Spacing.sm) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(criterion.accent)
                    Text(viewModel.criteria.city.isEmpty ? "Eure Stadt" : viewModel.criteria.city)
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }

            VStack(spacing: PBTheme.Spacing.sm) {
                HStack(spacing: PBTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(criterion.accent)
                    TextField("Stadt oder Ort suchen", text: $viewModel.criteria.city)
                        .textFieldStyle(.plain)
                        .font(PBTheme.Typography.body.weight(.medium))
                        .foregroundStyle(PBTheme.textOnDark)
                        .focused($isCityFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            viewModel.commitTypedCity()
                            citySearch.clear()
                            isCityFieldFocused = false
                        }
                    if citySearch.isSearching {
                        ProgressView().tint(criterion.accent)
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .frame(height: 58)
                .background(PBTheme.midnightRaised.opacity(0.86), in: Capsule())
                .overlay { Capsule().stroke(criterion.accent.opacity(0.72), lineWidth: 1) }

                if !citySearch.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(citySearch.suggestions.prefix(5)) { suggestion in
                            Button {
                                Task {
                                    let city = await citySearch.selectedCity(for: suggestion)
                                    viewModel.selectCity(city)
                                    citySearch.clear()
                                    isCityFieldFocused = false
                                }
                            } label: {
                                HStack(spacing: PBTheme.Spacing.sm) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(criterion.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(PBTheme.Typography.body.weight(.semibold))
                                            .foregroundStyle(PBTheme.textOnDark)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(PBTheme.Typography.micro)
                                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, PBTheme.Spacing.md)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            if suggestion.id != citySearch.suggestions.prefix(5).last?.id {
                                Divider().overlay(.white.opacity(0.10))
                            }
                        }
                    }
                    .background(PBTheme.midnightRaised.opacity(0.94), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                }

                Button {
                    Task { await viewModel.useCurrentLocation() }
                } label: {
                    Label(
                        viewModel.isResolvingLocation ? "Standort wird bestimmt …" : "Aktuellen Standort verwenden",
                        systemImage: "location.fill"
                    )
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(criterion.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(criterion.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isResolvingLocation)
            }
            .onChange(of: viewModel.criteria.city) { _, city in
                if isCityFieldFocused { citySearch.update(query: city) }
            }

            if let locationErrorMessage = viewModel.locationErrorMessage {
                Text(locationErrorMessage)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }

    private var moodExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Welche Energie wollt ihr miteinander teilen?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PBTheme.Spacing.sm) {
                ForEach(Mood.options(for: viewModel.criteria.planningMode)) { mood in
                    moodCard(mood)
                }
            }
        }
    }

    private var timeExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            darkPanel {
                        DatePicker("", selection: $viewModel.criteria.date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .colorScheme(.dark)
            }

            Text("Wann fühlt es sich richtig an?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            HStack(spacing: PBTheme.Spacing.sm) {
                timeChoice(title: "Nachmittag", time: "15:00", symbol: "sun.max")
                timeChoice(title: "Abend", time: "18:30", symbol: "sunset")
                timeChoice(title: "Spät", time: "20:30", symbol: "moon.stars")
            }

            darkPanel {
                HStack {
                    Label("Eigene Uhrzeit", systemImage: "clock")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    Spacer()
                    TextField("HH:mm", text: $viewModel.criteria.time)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .foregroundStyle(PBTheme.textOnDark)
                        .frame(width: 72)
                }
            }

            Text("Wie viel Raum möchtet ihr euch lassen?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            HStack(spacing: PBTheme.Spacing.sm) {
                ForEach([60, 120, 180, 240], id: \.self) { minutes in
                    durationChoice(minutes)
                }
            }
        }
    }

    private var budgetExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Welchen Rahmen habt ihr im Kopf?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            HStack(spacing: PBTheme.Spacing.sm) {
                ForEach(BudgetLevel.allCases) { level in
                    budgetCard(level)
                }
            }
            Text("Richtwerte pro Person für den ganzen Plan – Essen, Trinken und Eintritt zusammen. Die Ideen bleiben in diesem Rahmen.")
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    private var mobilityExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Wie möchtet ihr losziehen?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            HStack(spacing: PBTheme.Spacing.sm) {
                ForEach(Mobility.allCases) { mobility in
                    mobilityCard(mobility)
                }
            }

            darkPanel {
                HStack(alignment: .firstTextBaseline) {
                    Text("Euer Radius")
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textOnDark)
                    Spacer()
                    Text("\(Int(viewModel.criteria.radiusKm)) km")
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(criterion.accent)
                }
                HStack(spacing: 6) {
                    ForEach([2, 5, 10, 20, 35, 50], id: \.self) { radius in
                        Button { viewModel.criteria.radiusKm = Double(radius) } label: {
                            Text("\(radius)")
                                .font(PBTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(Int(viewModel.criteria.radiusKm) == radius ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Int(viewModel.criteria.radiusKm) == radius ? criterion.accent : .white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var settingExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Welche Kulisse passt zu euch heute?")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            HStack(spacing: PBTheme.Spacing.sm) {
                settingCard(.draussen, symbol: "sun.max.fill", phrase: "Frische Luft")
                settingCard(.drinnen, symbol: "lamp.desk.fill", phrase: "Gemütlich drin")
                settingCard(.egal, symbol: "sparkles", phrase: "Lasst euch überraschen")
            }
        }
    }

    private var detailsExperience: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            if viewModel.criteria.planningMode == .group {
                Text("Worauf hat eure Runde Lust?")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PBTheme.Spacing.sm) {
                    ForEach(groupFoodDirections, id: \.self) { direction in
                        groupFoodDirectionCard(direction)
                    }
                }
            } else {
                Text("Was macht dieses Date besonders?")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)

                VStack(spacing: PBTheme.Spacing.sm) {
                    ForEach(Occasion.allCases) { occasion in
                        occasionCard(occasion)
                    }
                }
            }

            darkPanel {
                Label(viewModel.criteria.planningMode == .group ? "Essen & Wünsche" : "Ernährung & Wünsche", systemImage: "leaf")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)
                if viewModel.criteria.planningMode == .group {
                    Text("Eine Richtung oder Einschränkungen – jeweils durch Komma getrennt.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                TextField(viewModel.criteria.planningMode == .group ? "z.B. Pizza, vegetarisch, etwas Scharfes" : "z.B. vegetarisch, glutenfrei", text: dietaryPreferences)
                    .textFieldStyle(.plain)
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .frame(height: 52)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            }
        }
    }

    private var durationLabel: String {
        let hours = viewModel.criteria.durationMinutes / 60
        let minutes = viewModel.criteria.durationMinutes % 60
        return minutes == 0 ? "ca. \(hours) Std" : "ca. \(hours) Std \(minutes) Min"
    }

    private var dietaryPreferences: Binding<String> {
        Binding(
            get: { viewModel.criteria.dietaryPreferences.joined(separator: ", ") },
            set: { newValue in
                viewModel.criteria.dietaryPreferences = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func darkPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md, content: content)
            .padding(PBTheme.Spacing.lg)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private func moodCard(_ mood: Mood) -> some View {
        let isSelected = viewModel.criteria.moods.contains(mood)
        return Button { viewModel.toggleMood(mood) } label: {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                Image(systemName: moodSymbol(mood))
                    .font(.system(size: 21, weight: .medium))
                Text(mood.label)
                    .font(PBTheme.Typography.headline)
                Text(moodPrompt(mood))
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(isSelected ? PBTheme.textOnDark.opacity(0.86) : PBTheme.textOnDarkSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(PBTheme.Spacing.md)
            .background(isSelected ? criterion.accent.opacity(0.92) : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(isSelected ? .white.opacity(0.52) : .white.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func timeChoice(title: String, time: String, symbol: String) -> some View {
        Button { viewModel.criteria.time = time } label: {
            VStack(spacing: PBTheme.Spacing.xs) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(PBTheme.Typography.micro)
                Text(time).font(PBTheme.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(viewModel.criteria.time == time ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(viewModel.criteria.time == time ? criterion.accent : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(viewModel.criteria.time == time ? 0.48 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func durationChoice(_ minutes: Int) -> some View {
        Button { viewModel.criteria.durationMinutes = minutes } label: {
            Text(durationShortLabel(minutes))
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(viewModel.criteria.durationMinutes == minutes ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(viewModel.criteria.durationMinutes == minutes ? criterion.accent : .white.opacity(0.075), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func budgetCard(_ level: BudgetLevel) -> some View {
        let isSelected = viewModel.criteria.budget == level
        return Button { viewModel.criteria.budget = level } label: {
            VStack(spacing: PBTheme.Spacing.sm) {
                Text(budgetMark(level))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(level.label)
                    .font(PBTheme.Typography.headline)
                Text(level.priceRange)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.78)
                Text(budgetPrompt(level))
                    .font(PBTheme.Typography.micro)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? PBTheme.textOnDark.opacity(0.86) : PBTheme.textOnDarkSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity, minHeight: 148)
            .padding(PBTheme.Spacing.sm)
            .background(isSelected ? criterion.accent : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(isSelected ? 0.50 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func mobilityCard(_ mobility: Mobility) -> some View {
        let isSelected = viewModel.criteria.mobility == mobility
        return Button { viewModel.criteria.mobility = mobility } label: {
            VStack(spacing: PBTheme.Spacing.sm) {
                Image(systemName: mobilitySymbol(mobility))
                    .font(.system(size: 24, weight: .medium))
                Text(mobility.label)
                    .font(PBTheme.Typography.headline)
            }
            .foregroundStyle(isSelected ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
            .frame(maxWidth: .infinity, minHeight: 106)
            .background(isSelected ? criterion.accent : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(isSelected ? 0.50 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func settingCard(_ option: IndoorOutdoor, symbol: String, phrase: String) -> some View {
        let isSelected = viewModel.criteria.indoorOutdoor == option
        return Button { viewModel.criteria.indoorOutdoor = option } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(isSelected ? 0.20 : 0.09), in: Circle())
                Text(option.label)
                    .font(PBTheme.Typography.headline)
                Text(phrase)
                    .font(PBTheme.Typography.micro)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? PBTheme.textOnDark.opacity(0.86) : PBTheme.textOnDarkSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(.horizontal, PBTheme.Spacing.xs).padding(.vertical, 10)
            .background(isSelected ? criterion.accent : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(isSelected ? 0.50 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var groupFoodDirections: [String] {
        ["Café & Süßes", "Herzhaft", "Streetfood", "Vegetarisch", "Nur Aktivitäten"]
    }

    private func groupFoodDirectionCard(_ direction: String) -> some View {
        let isSelected = viewModel.criteria.dietaryPreferences.contains(direction)
        return Button {
            if isSelected {
                viewModel.criteria.dietaryPreferences.removeAll { $0 == direction }
            } else if viewModel.criteria.dietaryPreferences.count < 6 {
                viewModel.criteria.dietaryPreferences.append(direction)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: groupFoodDirectionSymbol(direction))
                    .font(.system(size: 15, weight: .semibold))
                Text(direction)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(PBTheme.textOnDark)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? criterion.accent.opacity(0.92) : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous).stroke(.white.opacity(isSelected ? 0.46 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func groupFoodDirectionSymbol(_ direction: String) -> String {
        switch direction {
        case "Café & Süßes": return "cup.and.saucer.fill"
        case "Herzhaft": return "fork.knife"
        case "Streetfood": return "takeoutbag.and.cup.and.straw.fill"
        case "Vegetarisch": return "leaf.fill"
        default: return "figure.walk"
        }
    }

    private func occasionCard(_ occasion: Occasion) -> some View {
        let isSelected = viewModel.criteria.occasion == occasion.rawValue
        return Button { viewModel.criteria.occasion = occasion.rawValue } label: {
            HStack(spacing: PBTheme.Spacing.md) {
                Image(systemName: occasionSymbol(occasion))
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(isSelected ? 0.18 : 0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(occasion.label)
                        .font(PBTheme.Typography.headline)
                    Text(occasionPrompt(occasion))
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(isSelected ? PBTheme.textOnDark.opacity(0.84) : PBTheme.textOnDarkSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .padding(PBTheme.Spacing.md)
            .background(isSelected ? criterion.accent.opacity(0.92) : .white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(isSelected ? 0.50 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func moodSymbol(_ mood: Mood) -> String {
        switch mood {
        case .aktiv: return "figure.run"
        case .entspannt: return "leaf"
        case .romantisch: return "heart"
        case .gesellig: return "person.3.fill"
        case .kulinarisch: return "fork.knife"
        case .kulturell: return "building.columns"
        case .abenteuerlich: return "mountain.2"
        }
    }

    private func moodPrompt(_ mood: Mood) -> String {
        let isGroup = viewModel.criteria.planningMode == .group
        switch mood {
        case .aktiv: return isGroup ? "gemeinsam bewegen" : "raus & bewegen"
        case .entspannt: return "ohne Eile"
        case .romantisch: return "Zeit zu zweit"
        case .gesellig: return "lachen & quatschen"
        case .kulinarisch: return isGroup ? "zusammen schlemmen" : "etwas teilen"
        case .kulturell: return isGroup ? "gemeinsam entdecken" : "Neues entdecken"
        case .abenteuerlich: return isGroup ? "etwas Neues erleben" : "kleine Geschichte"
        }
    }

    private func budgetMark(_ level: BudgetLevel) -> String {
        switch level {
        case .guenstig: return "€"
        case .mittel: return "€€"
        case .gehoben: return "€€€"
        }
    }

    private func budgetPrompt(_ level: BudgetLevel) -> String {
        switch level {
        case .guenstig: return "leicht & spontan"
        case .mittel: return "Raum zum Genießen"
        case .gehoben: return "etwas Besonderes"
        }
    }

    private func mobilitySymbol(_ mobility: Mobility) -> String {
        switch mobility {
        case .zufuss: return "figure.walk"
        case .oepnv: return "tram.fill"
        case .auto: return "car.fill"
        }
    }

    private func occasionSymbol(_ occasion: Occasion) -> String {
        switch occasion {
        case .spontan: return "bolt.fill"
        case .jahrestag: return "sparkles"
        case .erstesDate: return "heart.circle"
        }
    }

    private func occasionPrompt(_ occasion: Occasion) -> String {
        switch occasion {
        case .spontan: return "Jetzt Lust auf etwas Schönes"
        case .jahrestag: return "Ein Moment, der bleiben darf"
        case .erstesDate: return "Leicht, öffentlich und entspannt"
        }
    }

    private func durationShortLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) Std" : "\(minutes) Min"
    }
}
