import SwiftUI

private enum CoupleDestination: Hashable {
    case home
    case discover
    case moments
    case profile
}

/// Social-first couple shell. It intentionally does not use a standard TabView: the approved
/// Midnight design needs a floating dock and makes planning/sharing intentional actions instead
/// of two more permanent destinations.
struct MainTabView: View {
    @ObservedObject var authManager: AuthManager
    let couple: Couple
    let viewer: AppUser
    @StateObject private var savedDateService = SavedDateService()
    @StateObject private var profileService = CoupleProfileService()
    @StateObject private var personProfileService = PersonProfileService()
    @StateObject private var postService = PostService()
    @StateObject private var personalPostService = PostService()
    @StateObject private var feedService = FeedService()
    @StateObject private var collaborationInboxService = CollaborationInboxService()
    @StateObject private var groupEventService = GroupEventService()
    @ObservedObject private var deepLinkRouter = MiteDeepLinkRouter.shared

    @State private var destination: CoupleDestination = .home
    @State private var isPlannerPresented = false
    @State private var planningInitialMode: PlanningMode = .date
    @State private var isPostsPresented = false
    @State private var isActivityPresented = false
    @State private var activityEventID: String?
    @State private var savedPlanToast: SavedPlanToast?
    @State private var pendingSavedDateID: String?
    @State private var deepLinkedSavedDate: SavedDate?

    var body: some View {
        PBScreenContainer {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    destinationContent
                        .safeAreaPadding(.bottom, 88)

                    PBGlassDock(items: dockItems, selection: $destination)
                        .padding(.bottom, PBTheme.Spacing.sm)
                }
                // A tab is allowed to scroll vertically, but it must never influence the width
                // of the persistent app shell. This is especially important for AsyncImage:
                // some remote image sizes otherwise make the whole tab canvas wider than the
                // device, shifting every sibling view out of frame.
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            }
        }
        .sheet(isPresented: $isPlannerPresented) {
            PlanningStartView(
                couple: couple,
                viewerUID: viewer.id ?? "",
                profileCity: profileService.profile?.city ?? "",
                savedDateService: savedDateService,
                initialMode: planningInitialMode,
                onPlanSaved: { mode in
                    isPlannerPresented = false
                    destination = .home
                    presentSavedPlanToast(for: mode)
                }
            )
        }
        .sheet(isPresented: $isPostsPresented) {
            MyPostsView(
                couple: couple,
                creatorUid: viewer.id ?? "",
                savedDates: savedDateService.savedDates,
                defaultCity: profileService.profile?.city ?? "",
                postService: postService
            )
        }
        .sheet(isPresented: $isActivityPresented) {
            NavigationStack {
                ActivityInboxView(
                    uid: viewer.id ?? "",
                    defaultCity: profileService.profile?.city ?? "",
                    collaborationService: collaborationInboxService,
                    groupEventService: groupEventService,
                    initialEventID: activityEventID
                )
            }
        }
        .sheet(item: $deepLinkedSavedDate) { savedDate in
            NavigationStack {
                SavedDateDetailView(
                    scope: .couple(id: couple.id ?? ""),
                    savedDate: savedDate,
                    savedDateService: savedDateService,
                    postService: postService
                )
            }
        }
        .onChange(of: deepLinkRouter.groupEventID, initial: true) { _, eventID in
            guard let eventID else { return }
            activityEventID = eventID
            isActivityPresented = true
            deepLinkRouter.consumeGroupEvent(eventID)
        }
        .onChange(of: deepLinkRouter.coupleDateRoute, initial: true) { _, route in
            guard let route, route.coupleID == couple.id else { return }
            destination = .moments
            pendingSavedDateID = route.savedDateID
            resolvePendingSavedDate()
            deepLinkRouter.consumeCoupleDate(route)
        }
        .onChange(of: savedDateService.savedDates) { _, _ in
            resolvePendingSavedDate()
        }
        .task(id: couple.id) {
            if let coupleId = couple.id {
                savedDateService.startListening(scope: .couple(id: coupleId))
                profileService.startListening(coupleId: coupleId)
                if let uid = viewer.id { personProfileService.startListening(uid: uid) }
                postService.startListening(coupleId: coupleId)
                if let uid = viewer.id { personalPostService.startListening(ownerUid: uid) }
                feedService.startListening(viewerUid: viewer.id ?? "", coupleId: coupleId)
                if let uid = viewer.id {
                    collaborationInboxService.startListening(uid: uid)
                    groupEventService.startListening(uid: uid)
                }
            }
        }
        .task(id: preloadedImageURLs) {
            PBImageCache.preload(urlStrings: preloadedImageURLs)
        }
        .task(id: preloadedStoragePaths) {
            PBStorageImagePrefetcher.preload(paths: preloadedStoragePaths)
        }
        .overlay(alignment: .top) {
            if let savedPlanToast {
                SavedPlanToastView(toast: savedPlanToast)
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        TabView(selection: $destination) {
            CoupleHomeView(
                couple: couple,
                viewer: viewer,
                savedDateService: savedDateService,
                feedService: feedService,
                postService: postService,
                onPlan: { planningInitialMode = .date; isPlannerPresented = true },
                onShare: { isPostsPresented = true },
                onDiscover: { destination = .discover },
                onNotifications: { isActivityPresented = true },
                unreadActivityCount: unreadActivityCount
            )
            .tag(CoupleDestination.home)

            DiscoverFeedView(
                viewerUid: viewer.id ?? "",
                defaultCity: profileService.profile?.city ?? "",
                feedService: feedService
            )
                .tag(CoupleDestination.discover)

            SavedDateHistoryView(
                scope: .couple(id: couple.id ?? ""),
                savedDateService: savedDateService,
                postService: postService,
                groupEventService: groupEventService,
                viewerUID: viewer.id ?? "",
                defaultCity: profileService.profile?.city ?? ""
            )
                .tag(CoupleDestination.moments)

            CoupleProfileView(
                couple: couple,
                profileService: profileService,
                personProfileService: personProfileService,
                authManager: authManager,
                savedDates: savedDateService.savedDates,
                postService: postService,
                personalPostService: personalPostService
            )
            .tag(CoupleDestination.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: destination)
    }

    private var dockItems: [PBGlassDock<CoupleDestination>.Item] {
        [
            .init(id: "home", selection: .home, title: "Für euch", symbol: "house"),
            .init(id: "discover", selection: .discover, title: "Entdecken", symbol: "magnifyingglass"),
            .init(id: "moments", selection: .moments, title: "Momente", symbol: "bookmark"),
            .init(id: "profile", selection: .profile, title: "Profil", symbol: "person"),
        ]
    }

    private var unreadActivityCount: Int {
        let groupInvitations = groupEventService.events.filter {
            $0.status == .planned && $0.attendance(for: viewer.id ?? "") == .invited
        }.count
        return collaborationInboxService.invitations.count + groupInvitations
    }

    /// Feed/date data is already live in memory while another tab is active. Warming the remote
    /// image cache here prevents the same visible image from flickering through a loader when a
    /// person pages back to a previously opened tab.
    private var preloadedImageURLs: [String] {
        let dateURLs = savedDateService.savedDates
            .flatMap(\.stations)
            .compactMap(\.licensedImage?.url)
        let feedURLs = feedService.posts.compactMap { $0.coverLicensedImage?.url }
        return Array(Set(dateURLs + feedURLs)).sorted()
    }

    private var preloadedStoragePaths: [String] {
        couple.members.compactMap(\.avatarPath)
    }

    private func presentSavedPlanToast(for mode: PlanningMode) {
        let toast = SavedPlanToast(mode: mode)
        withAnimation(.snappy(duration: 0.28)) { savedPlanToast = toast }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard savedPlanToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { savedPlanToast = nil }
        }
    }

    private func resolvePendingSavedDate() {
        guard let pendingSavedDateID,
              let savedDate = savedDateService.savedDates.first(where: { $0.id == pendingSavedDateID }) else { return }
        deepLinkedSavedDate = savedDate
        self.pendingSavedDateID = nil
    }
}

private struct SavedPlanToast: Identifiable, Equatable {
    let id = UUID()
    let mode: PlanningMode

    var title: String { mode == .group ? "Treffen geplant" : "Date geplant" }
    var detail: String { mode == .group ? "Der Planraum ist für eure Runde bereit." : "Euer nächstes Date wartet auf euch." }
}

private struct SavedPlanToastView: View {
    let toast: SavedPlanToast

    var body: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PBTheme.midnight)
                .frame(width: 32, height: 32)
                .background(PBTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(PBTheme.Typography.caption.weight(.bold)).foregroundStyle(PBTheme.textOnDark)
                Text(toast.detail).font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(PBTheme.routeSurfaceRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 9)
        .accessibilityElement(children: .combine)
    }
}
