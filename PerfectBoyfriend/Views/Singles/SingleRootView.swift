import SwiftUI

struct SingleRootView: View {
    @ObservedObject var authManager: AuthManager
    @StateObject private var profileService = SingleProfileService()

    var body: some View {
        PBScreenContainer {
            Group {
                if profileService.isLoading {
                    ProgressView().tint(PBTheme.textOnDark)
                } else if let profile = profileService.profile {
                    SingleMainTabView(authManager: authManager, profile: profile, profileService: profileService)
                } else if let errorMessage = profileService.loadErrorMessage {
                    PBEmptyState(
                        symbol: "wifi.exclamationmark",
                        title: "Profil gerade nicht erreichbar",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        if let uid = authManager.firebaseUser?.uid {
                            profileService.startListening(uid: uid)
                        }
                    }
                } else if let appUser = authManager.appUser {
                    SingleProfileEditorView(profile: nil, profileService: profileService, suggestedName: appUser.displayName)
                } else {
                    ProgressView().tint(PBTheme.textOnDark)
                }
            }
        }
        .task(id: authManager.firebaseUser?.uid) {
            if let uid = authManager.firebaseUser?.uid {
                profileService.startListening(uid: uid)
            } else {
                profileService.stopListening()
            }
        }
    }
}

private enum SingleDestination: Hashable {
    case discover
    case matches
    case profile
}

struct SingleMainTabView: View {
    @ObservedObject var authManager: AuthManager
    let profile: SingleProfile
    @ObservedObject var profileService: SingleProfileService
    @StateObject private var matchingService = SingleMatchingService()
    @ObservedObject private var deepLinkRouter = MiteDeepLinkRouter.shared
    @State private var destination: SingleDestination = .discover
    @State private var pendingMatchRoute: MiteDeepLinkRouter.SingleMatchRoute?

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
        .task {
            await matchingService.refresh()
        }
        .onChange(of: deepLinkRouter.singleMatchRoute, initial: true) { _, route in
            guard let route else { return }
            destination = .matches
            pendingMatchRoute = route
            deepLinkRouter.consumeSingleMatch(route)
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        TabView(selection: $destination) {
            SingleDiscoverView(profile: profile, matchingService: matchingService)
                .tag(SingleDestination.discover)

            SingleMatchesView(
                ownProfile: profile,
                matchingService: matchingService,
                pendingRoute: $pendingMatchRoute
            )
                .tag(SingleDestination.matches)

            SingleProfileView(profile: profile, profileService: profileService, authManager: authManager)
                .tag(SingleDestination.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: destination)
    }

    private var dockItems: [PBGlassDock<SingleDestination>.Item] {
        [
            .init(id: "discover", selection: .discover, title: "Entdecken", symbol: "sparkles"),
            .init(id: "matches", selection: .matches, title: "Matches", symbol: "person.2"),
            .init(id: "profile", selection: .profile, title: "Profil", symbol: "person"),
        ]
    }
}
