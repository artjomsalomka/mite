import SwiftUI

struct SingleMatchesView: View {
    let ownProfile: SingleProfile
    @ObservedObject var matchingService: SingleMatchingService
    @Binding var pendingRoute: MiteDeepLinkRouter.SingleMatchRoute?
    @State private var navigationPath: [String] = []
    @State private var routeDestinations: [String: MiteDeepLinkRouter.SingleMatchRoute.Destination] = [:]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text("Matches")
                                .font(PBTheme.Typography.display)
                                .foregroundStyle(PBTheme.textOnDark)
                            Text("Gegenseitiges Interesse ist der Anfang einer gemeinsamen Date-Idee.")
                                .font(PBTheme.Typography.body)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        matchesContent
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
                .refreshable { await matchingService.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { matchID in
                if let match = matchingService.matches.first(where: { $0.matchId == matchID }) {
                    SingleMatchDetailView(
                        match: match,
                        ownProfile: ownProfile,
                        matchingService: matchingService,
                        opensChatInitially: routeDestinations[matchID] == .chat
                    )
                } else {
                    PBScreenContainer {
                        PBEmptyState(
                            symbol: "person.crop.circle.badge.questionmark",
                            title: "Match nicht verfügbar",
                            message: "Dieses Match wurde entfernt oder ist für dein Profil nicht mehr erreichbar."
                        )
                        .padding(PBTheme.Spacing.lg)
                    }
                }
            }
        }
        .onChange(of: pendingRoute, initial: true) { _, route in
            guard let route else { return }
            routeDestinations[route.matchID] = route.destination
            navigationPath = [route.matchID]
            pendingRoute = nil
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            guard !oldPath.isEmpty, newPath.isEmpty else { return }
            Task { await matchingService.refresh() }
        }
    }

    @ViewBuilder
    private var matchesContent: some View {
        if matchingService.matches.isEmpty {
            PBEmptyState(
                symbol: "person.2",
                title: "Noch keine Matches",
                message: "Wenn Interesse auf Gegenseitigkeit trifft, erscheint das Match hier."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xxl)
        } else {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                PBSectionTitle(title: "Eure Matches")
                ForEach(matchingService.matches) { match in
                    NavigationLink(value: match.matchId) {
                        SingleMatchCard(match: match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SingleMatchCard: View {
    let match: SingleMatchPreview

    var body: some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.md) {
            Group {
                if let avatarPath = match.profile.avatarPath, !avatarPath.isEmpty {
                    StorageImageView(path: avatarPath)
                } else {
                    Text(String(match.profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PBTheme.accent)
                }
            }
            .frame(width: 58, height: 58)
            .background(PBTheme.accentMuted, in: Circle())
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                Text("\(match.profile.displayName), \(match.profile.age)")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textPrimary)
                if match.profile.isVerified {
                    Label("Identität bestätigt", systemImage: "checkmark.seal.fill")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.success)
                }
                Label(match.profile.city, systemImage: "mappin.and.ellipse")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textSecondary)
                Text("Öffentliches erstes Date gemeinsam planen")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.accent)
            }

            Spacer(minLength: 0)
            if match.hasUnreadMessage {
                Circle()
                    .fill(PBTheme.accent)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Neue Nachricht")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .shadow(color: PBTheme.Shadow.card, radius: 10, y: 5)
    }
}
