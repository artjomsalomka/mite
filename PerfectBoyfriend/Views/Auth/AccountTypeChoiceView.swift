import SwiftUI

private enum PersonalDestination: Hashable {
    case home
    case discover
    case plans
    case profile
}

/// The default shell for every authenticated person who is not currently linked to a couple.
/// Pairing and dating remain opt-in spaces; planning with friends works immediately.
struct PersonalRootView: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var coupleService: CoupleService
    let viewer: AppUser

    @StateObject private var personProfileService = PersonProfileService()
    @StateObject private var groupEventService = GroupEventService()
    @StateObject private var savedDateService = SavedDateService()
    @StateObject private var collaborationService = CollaborationInboxService()
    @StateObject private var postService = PostService()
    @StateObject private var feedService = FeedService()
    @ObservedObject private var deepLinkRouter = MiteDeepLinkRouter.shared

    @State private var destination: PersonalDestination = .home
    @State private var isPairingPresented = false
    @State private var isDatingPresented = false
    @State private var isComposerPresented = false
    @State private var isMomentComposerPresented = false
    @State private var isInboxPresented = false
    @State private var activityEventID: String?
    @State private var isEnablingDating = false
    @State private var actionError: String?

    private var uid: String { viewer.id ?? authManager.firebaseUser?.uid ?? "" }
    private var city: String { personProfileService.profile?.city ?? "" }

    var body: some View {
        PBScreenContainer {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    destinationContent
                        .safeAreaPadding(.bottom, 88)

                    PBGlassDock(items: dockItems, selection: $destination)
                        .padding(.bottom, PBTheme.Spacing.sm)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            }
        }
        .sheet(isPresented: $isPairingPresented) {
            CoupleChoiceView(authManager: authManager, coupleService: coupleService)
        }
        .sheet(isPresented: $isDatingPresented) {
            SingleRootView(authManager: authManager)
        }
        .sheet(isPresented: $isComposerPresented) {
            PlanningStartView(
                personalUID: uid,
                profileCity: city,
                savedDateService: savedDateService,
                onPlanSaved: { _ in isComposerPresented = false }
            )
        }
        .sheet(isPresented: $isMomentComposerPresented) {
            NavigationStack {
                PostComposerView(
                    ownerID: uid,
                    creatorUid: uid,
                    savedDates: [],
                    groupEvents: groupEventService.events,
                    defaultCity: city,
                    visibilityOptions: [.private, .public],
                    postService: postService
                )
            }
        }
        .sheet(isPresented: $isInboxPresented) {
            NavigationStack {
                ActivityInboxView(
                    uid: uid,
                    defaultCity: city,
                    collaborationService: collaborationService,
                    groupEventService: groupEventService,
                    initialEventID: activityEventID
                )
            }
        }
        .onChange(of: deepLinkRouter.groupEventID, initial: true) { _, eventID in
            guard let eventID else { return }
            activityEventID = eventID
            isInboxPresented = true
            deepLinkRouter.consumeGroupEvent(eventID)
        }
        .onChange(of: deepLinkRouter.singleMatchRoute, initial: true) { _, route in
            guard route != nil else { return }
            // Keep the route pending until SingleMainTabView has loaded the matching profile
            // and can resolve the referenced match. This also survives a cold app launch.
            isDatingPresented = true
        }
        .task(id: uid) {
            guard !uid.isEmpty else { return }
            personProfileService.startListening(uid: uid)
            groupEventService.startListening(uid: uid)
            collaborationService.startListening(uid: uid)
            postService.startListening(ownerUid: uid)
            feedService.startListening(viewerUid: uid)
        }
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        TabView(selection: $destination) {
            NavigationStack {
                PersonalHomeView(
                    viewer: viewer,
                    profile: personProfileService.profile,
                    events: groupEventService.events,
                    eventService: groupEventService,
                    onPlan: { isComposerPresented = true },
                    onShare: { isMomentComposerPresented = true },
                    onInbox: { isInboxPresented = true }
                )
            }
            .tag(PersonalDestination.home)

            NavigationStack {
                DiscoverFeedView(
                    viewerUid: uid,
                    defaultCity: city,
                    feedService: feedService
                )
            }
            .tag(PersonalDestination.discover)

            NavigationStack {
                GroupEventsView(uid: uid, defaultCity: city)
            }
            .tag(PersonalDestination.plans)

            NavigationStack {
                PersonalProfileHomeView(
                    authManager: authManager,
                    personProfileService: personProfileService,
                    posts: postService.posts,
                    isDatingEnabled: viewer.isDatingEnabled,
                    onShare: { isMomentComposerPresented = true },
                    onPair: { isPairingPresented = true },
                    onDating: openDating
                )
            }
            .tag(PersonalDestination.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: destination)
    }

    private var dockItems: [PBGlassDock<PersonalDestination>.Item] {
        [
            .init(id: "home", selection: .home, title: "Start", symbol: "house"),
            .init(id: "discover", selection: .discover, title: "Entdecken", symbol: "magnifyingglass"),
            .init(id: "plans", selection: .plans, title: "Pläne", symbol: "calendar"),
            .init(id: "profile", selection: .profile, title: "Profil", symbol: "person"),
        ]
    }

    private func openDating() {
        guard !isEnablingDating else { return }
        if viewer.isDatingEnabled {
            isDatingPresented = true
            return
        }
        isEnablingDating = true
        Task {
            defer { isEnablingDating = false }
            do {
                try await authManager.chooseAccountMode(.single)
                isDatingPresented = true
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

private struct PersonalHomeView: View {
    let viewer: AppUser
    let profile: PersonProfile?
    let events: [GroupEvent]
    @ObservedObject var eventService: GroupEventService
    let onPlan: () -> Void
    let onShare: () -> Void
    let onInbox: () -> Void

    private var upcoming: [GroupEvent] {
        events.filter { $0.status == .planned && $0.scheduledAt.dateValue() >= Calendar.current.startOfDay(for: Date()) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    header
                    actionRail

                    PBSectionTitle(title: "Deine nächsten Pläne")
                    if upcoming.isEmpty {
                        emptyPlans
                    } else {
                        ForEach(upcoming) { event in
                            NavigationLink {
                                GroupEventDetailView(event: event, uid: viewer.id ?? "", service: eventService)
                            } label: {
                                PersonalUpcomingEventCard(event: event, viewerUID: viewer.id ?? "")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text("Mite wächst mit dir")
                            .font(PBTheme.Typography.headline)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Plane zuerst mit Freund:innen. Eine Paarverbindung oder die Date-Suche kannst du jederzeit ergänzen – dein persönliches Profil bleibt dabei erhalten.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    .padding(PBTheme.Spacing.md)
                    .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi, \(firstName)")
                    .font(PBTheme.Typography.greeting)
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Was wollt ihr gemeinsam erleben?")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onInbox) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 42, height: 42)
                    .background(PBTheme.controlSurface, in: Circle())
                    .overlay { Circle().stroke(PBTheme.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nachrichten und Einladungen")
        }
    }

    private var actionRail: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            personalAction(title: "Event planen", symbol: "plus", emphasized: true, action: onPlan)
            personalAction(title: "Moment teilen", symbol: "camera", action: onShare)
        }
    }

    private func personalAction(title: String, symbol: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(title).font(PBTheme.Typography.micro.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.78)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(emphasized ? PBTheme.controlSelected : PBTheme.controlSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(PBTheme.controlBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var emptyPlans: some View {
        Button(action: onPlan) {
            HStack(spacing: PBTheme.Spacing.md) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 48, height: 48)
                    .background(PBTheme.controlSelected, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Noch nichts geplant")
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Starte einen Plan und lade deine Leute ein.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .padding(PBTheme.Spacing.md)
            .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var firstName: String {
        (profile?.displayName ?? viewer.displayName).split(separator: " ").first.map(String.init) ?? viewer.displayName
    }
}

private struct PersonalUpcomingEventCard: View {
    let event: GroupEvent
    let viewerUID: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GroupEventCover(event: event)
            LinearGradient(colors: [.clear, .black.opacity(0.84)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                Text(event.scheduledAt.dateValue(), format: .dateTime.weekday(.wide).day().month())
                    .font(PBTheme.Typography.micro.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                Text(event.title)
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    GroupEventAvatarStack(participants: event.participants, avatarSize: 26)
                    Text(event.scheduledAt.dateValue(), format: .dateTime.hour().minute())
                    if !event.city.isEmpty { Text("· \(event.city)") }
                }
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .lineLimit(1)
            }
            .padding(PBTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}

private struct PersonalProfileHomeView: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var personProfileService: PersonProfileService
    let posts: [SocialPost]
    let isDatingEnabled: Bool
    let onShare: () -> Void
    let onPair: () -> Void
    let onDating: () -> Void

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    HStack {
                        Text("Profil")
                            .font(.system(size: 31, weight: .light))
                            .foregroundStyle(PBTheme.textOnDark)
                        Spacer()
                        NavigationLink { ProfileSettingsView(authManager: authManager) } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(PBTheme.textOnDark)
                                .frame(width: 42, height: 42)
                                .background(PBTheme.controlSurface, in: Circle())
                        }
                    }

                    HStack(spacing: PBTheme.Spacing.md) {
                        profileAvatar
                        VStack(alignment: .leading, spacing: 4) {
                            Text(personProfileService.profile?.displayName ?? authManager.appUser?.displayName ?? "Dein Profil")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(PBTheme.textOnDark)
                                .lineLimit(1)
                            if let handle = personProfileService.profile?.handle, !handle.isEmpty {
                                Text("@\(handle)").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                            }
                            if let city = personProfileService.profile?.city, !city.isEmpty {
                                Text(city).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    NavigationLink {
                        PublicIdentityEditorView(authManager: authManager, personProfileService: personProfileService)
                    } label: {
                        ProfileActionRow(symbol: "person.crop.circle", title: personProfileService.profile == nil ? "Profil einrichten" : "Profil bearbeiten", subtitle: "Foto, Handle, Stadt und Sichtbarkeit")
                    }
                    .buttonStyle(.plain)

                    personalMoments

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text("Deine Verbindungen")
                            .font(PBTheme.Typography.headline)
                            .foregroundStyle(PBTheme.textOnDark)
                        Button(action: onPair) {
                            ProfileActionRow(symbol: "heart", title: "Als Paar verbinden", subtitle: "Erstellt einen gemeinsamen Bereich, ohne eure Profile zusammenzulegen")
                        }
                        .buttonStyle(.plain)
                        Button(action: onDating) {
                            ProfileActionRow(symbol: "sparkles", title: isDatingEnabled ? "Date-Suche öffnen" : "Date-Suche aktivieren", subtitle: "Optional passende Menschen und erste Dates entdecken")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var personalMoments: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Text("Deine Momente")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Button(action: onShare) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .frame(width: 36, height: 36)
                        .background(PBTheme.controlSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Moment teilen")
            }

            if posts.isEmpty {
                Button(action: onShare) {
                    HStack(spacing: PBTheme.Spacing.sm) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .light))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dein erster Moment")
                                .font(PBTheme.Typography.body.weight(.semibold))
                            Text("Teile Fotos oder Videos von eurem Erlebnis.")
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(PBTheme.Spacing.md)
                    .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                    spacing: 4
                ) {
                    ForEach(posts.filter { $0.status == .published }) { post in
                        if let postID = post.id {
                            NavigationLink { SocialPostDetailView(postID: postID) } label: {
                                PersonalMomentGridTile(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        Group {
            if let path = personProfileService.profile?.avatarPath ?? authManager.appUser?.avatarPath, !path.isEmpty {
                StorageImageView(path: path)
            } else {
                Text(String((authManager.appUser?.displayName ?? "M").prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
            }
        }
        .frame(width: 86, height: 86)
        .background(PBTheme.controlSurface, in: Circle())
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.controlBorder, lineWidth: 1) }
    }
}

private struct PersonalMomentGridTile: View {
    let post: SocialPost

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = post.licensedImages?.first {
                    LicensedImageView(image: image)
                } else if let path = post.primaryPreviewPath {
                    StorageImageView(path: path)
                } else {
                    LinearGradient(
                        colors: [PBTheme.midnightSoft, PBTheme.routeSurfaceRaised],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if post.visibility == .private {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(7)
                    .background(PBTheme.midnight.opacity(0.72), in: Circle())
                    .padding(7)
            } else if post.orderedMedia.count > 1 {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 0.5) }
        .accessibilityLabel(post.caption.isEmpty ? "Moment" : post.caption)
    }
}

struct AccountTypeChoiceView: View {
    @ObservedObject var authManager: AuthManager
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        PBScreenContainer {
            VStack(spacing: PBTheme.Spacing.lg) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)

                VStack(spacing: PBTheme.Spacing.sm) {
                    Text("Worauf hast du Lust?")
                        .font(PBTheme.Typography.display)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Dein Profil gehört immer dir. Du kannst es mit einer anderen Person zu einem Paar verbinden oder neue Menschen kennenlernen.")
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: PBTheme.Spacing.md) {
                    modeButton(
                        title: "Mit jemandem planen",
                        subtitle: "Verbinde dein Profil und gestaltet eure gemeinsame Date-Welt.",
                        icon: "person.2.fill",
                        mode: .couple
                    )
                    modeButton(
                        title: "Jemanden kennenlernen",
                        subtitle: "Aktiviere die Date-Suche mit passenden Singles.",
                        icon: "person.crop.circle.badge.plus",
                        mode: .single
                    )
                }

                if isSaving {
                    ProgressView("Richte deinen Bereich ein …")
                        .tint(PBTheme.textOnDark)
                        .foregroundStyle(PBTheme.textOnDark)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(PBTheme.Spacing.sm)
                        .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                }

                Spacer()
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.vertical, PBTheme.Spacing.lg)
        }
    }

    private func modeButton(title: String, subtitle: String, icon: String, mode: AccountMode) -> some View {
        Button {
            Task { await select(mode) }
        } label: {
            PBOptionCard(symbol: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func select(_ mode: AccountMode) async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await authManager.chooseAccountMode(mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
