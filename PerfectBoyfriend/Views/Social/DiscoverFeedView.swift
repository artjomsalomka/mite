import SwiftUI

private enum DiscoverAudience: String, CaseIterable, Identifiable {
    case all, city, friends

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Alle"
        case .city: return "Deine Stadt"
        case .friends: return "Deine Freunde"
        }
    }
}

private enum DiscoverLayout { case cards, grid }

struct DiscoverFeedView: View {
    let viewerUid: String
    let defaultCity: String
    @ObservedObject var feedService: FeedService
    @StateObject private var personFollowService = PersonFollowService()

    @State private var audience: DiscoverAudience = .all
    @State private var layout: DiscoverLayout = .cards
    @State private var postPath: [String] = []

    private var filteredPosts: [DiscoverablePost] {
        feedService.posts.filter { post in
            let matchesAudience: Bool
            switch audience {
            case .all: matchesAudience = true
            case .city:
                matchesAudience = !defaultCity.isEmpty && post.city.compare(defaultCity, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            case .friends:
                matchesAudience = feedService.followedCoupleIds.contains(post.ownerCoupleId)
                    || personFollowService.followingUIDs.contains(post.creator?.uid ?? "")
            }
            let isBlocked = post.creator.map { personFollowService.blockedUIDs.contains($0.uid) } ?? false
            return matchesAudience && !isBlocked
        }
    }

    var body: some View {
        NavigationStack(path: $postPath) {
            PBScreenContainer {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Entdecken")
                                    .font(PBTheme.Typography.display)
                                    .foregroundStyle(PBTheme.textOnDark)
                                Spacer()
                                NavigationLink {
                                    PersonDirectoryView(viewerUid: viewerUid)
                                } label: {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(PBTheme.textOnDark)
                                        .frame(width: 40, height: 40)
                                        .background(.white.opacity(0.12), in: Circle())
                                }
                                .accessibilityLabel("Profile suchen")
                                layoutButton
                            }

                            if !feedService.posts.isEmpty { audienceFilters }

                            if feedService.isLoading && feedService.posts.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView("Lade Date-Momente …")
                                        .tint(PBTheme.textOnDark)
                                        .foregroundStyle(PBTheme.textOnDark)
                                    Spacer()
                                }
                                .padding(.top, PBTheme.Spacing.xxl)
                            } else if let loadErrorMessage = feedService.loadErrorMessage, feedService.posts.isEmpty {
                                PBEmptyState(
                                    symbol: "wifi.exclamationmark",
                                    title: "Entdecken nicht erreichbar",
                                    message: loadErrorMessage,
                                    actionTitle: "Erneut versuchen",
                                    action: feedService.retryLoading
                                )
                                .frame(maxWidth: .infinity, minHeight: 360)
                            } else if filteredPosts.isEmpty {
                                PBEmptyState(
                                    symbol: feedService.posts.isEmpty ? "sparkles" : "line.3.horizontal.decrease.circle",
                                    title: feedService.posts.isEmpty ? "Noch nichts zu entdecken" : "Keine passenden Beiträge",
                                    message: emptyMessage
                                )
                                .frame(maxWidth: .infinity, minHeight: 360)
                            } else {
                                feedContent
                            }
                        }
                        // Keep the content width equal to the device viewport. Without this
                        // guard a wide remote image can make the vertical feed wider than its
                        // ScrollView and clip all text at the left edge.
                        .frame(width: max(0, proxy.size.width - (PBTheme.Spacing.md * 2)), alignment: .leading)
                        .padding(.horizontal, PBTheme.Spacing.md)
                        .padding(.top, PBTheme.Spacing.md)
                        .padding(.bottom, PBTheme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { postID in
                SocialPostDetailView(postID: postID)
            }
            .alert("Aktion nicht möglich", isPresented: Binding(
                get: { feedService.actionError != nil },
                set: { if !$0 { feedService.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(feedService.actionError ?? "Unbekannter Fehler")
            }
        }
        .task { await personFollowService.refresh() }
    }
}

private extension DiscoverFeedView {
    var layoutButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.03)) {
                layout = layout == .cards ? .grid : .cards
            }
        } label: {
            Image(systemName: layout == .cards ? "square.grid.2x2" : "rectangle.stack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .cards ? "Rasteransicht anzeigen" : "Kartenansicht anzeigen")
    }

    var audienceFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: PBTheme.Spacing.sm) {
                PBFilterChip(title: "Alle", symbol: "sparkles", isSelected: audience == .all) { audience = .all }
                PBFilterChip(title: "Deine Stadt", symbol: "mappin.and.ellipse", isSelected: audience == .city) { audience = .city }
                    .disabled(defaultCity.isEmpty)
                    .opacity(defaultCity.isEmpty ? 0.45 : 1)
                PBFilterChip(title: "Deine Freunde", symbol: "person.2.fill", isSelected: audience == .friends) { audience = .friends }
            }
            .padding(.horizontal, PBTheme.Spacing.xxs)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    var feedContent: some View {
        if layout == .cards {
            LazyVStack(spacing: PBTheme.Spacing.md) {
                ForEach(filteredPosts) { post in card(post) }
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filteredPosts) { post in
                    Button { postPath.append(post.id) } label: { DiscoverPostGridCard(post: post) }
                        .buttonStyle(.plain)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    func card(_ post: DiscoverablePost) -> some View {
        DiscoverPostCard(
            post: post,
            viewerUid: viewerUid,
            feedService: feedService,
            personFollowService: personFollowService,
            isFollowing: feedService.followedCoupleIds.contains(post.ownerCoupleId),
            isLiked: feedService.likedPostIds.contains(post.id),
            isSaved: feedService.savedPostIds.contains(post.id),
            onFollow: { Task { await feedService.toggleFollow(targetCoupleId: post.ownerCoupleId) } },
            onReaction: { kind in Task { await feedService.toggleReaction(post: post, kind: kind) } },
            onOpen: { postPath.append(post.id) }
        )
    }

    var emptyMessage: String {
        if feedService.posts.isEmpty { return "Sobald andere Menschen öffentliche Momente teilen, erscheinen sie hier." }
        switch audience {
        case .all: return "Probiert ein anderes Thema aus."
        case .city: return defaultCity.isEmpty ? "Hinterlege in deinem Profil eine Stadt, um lokale Momente zu sehen." : "In \(defaultCity) gibt es gerade noch keine passenden Momente."
        case .friends: return "Folge anderen Profilen, damit ihre Momente hier erscheinen."
        }
    }
}

private struct DiscoverPostGridCard: View {
    let post: DiscoverablePost

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            LinearGradient(colors: [.clear, Color.black.opacity(0.80)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 5) {
                if !post.city.isEmpty {
                    Text(post.city)
                        .font(PBTheme.Typography.micro.weight(.semibold))
                }
                Text(post.caption.isEmpty ? post.categories.first ?? "Gemeinsamer Moment" : post.caption)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .lineLimit(3)
                HStack {
                    if post.visiblePeople.count > 1 { Image(systemName: "person.2.fill") }
                    Spacer()
                    if post.imageCount > 1 { Image(systemName: "rectangle.on.rectangle") }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .padding(11)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: PBTheme.Shadow.card, radius: 10, y: 5)
    }

    @ViewBuilder
    private var background: some View {
        if let image = post.coverLicensedImage {
            LicensedImageView(image: image)
        } else if let path = post.coverImagePath {
            StorageImageView(path: path)
        } else {
            LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.routeSurfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct DiscoverPostCard: View {
    let post: DiscoverablePost
    let viewerUid: String
    @ObservedObject var feedService: FeedService
    @ObservedObject var personFollowService: PersonFollowService
    let isFollowing: Bool
    let isLiked: Bool
    let isSaved: Bool
    let onFollow: () -> Void
    let onReaction: (FeedService.ReactionKind) -> Void
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            postBackground

            LinearGradient(
                colors: [Color.black.opacity(0.38), .clear, Color.black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                postHeader
                Spacer(minLength: PBTheme.Spacing.xl)
                postFooter
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: PBTheme.Shadow.card, radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Moment öffnen", onOpen)
    }

    private var postHeader: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            SocialPeoplePresentation(people: post.visiblePeople, style: .compact)
            Spacer(minLength: 0)
            Image(systemName: post.visiblePeople.count > 1 ? "person.3.fill" : "person.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .padding(PBTheme.Spacing.md)
    }

    private var postFooter: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            if !post.city.isEmpty {
                Text(post.city)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textPrimary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(PBTheme.Typography.body.weight(.medium))
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(3)
            }

            if !post.categories.isEmpty {
                Text(post.categories.joined(separator: " · "))
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            HStack(spacing: PBTheme.Spacing.lg) {
                Button {
                    onReaction(.like)
                } label: {
                    Label("\(post.likesCount)", systemImage: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? PBTheme.accent : PBTheme.textOnDark)
                }

                Button {
                    onReaction(.save)
                } label: {
                    Label("\(post.savesCount)", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? PBTheme.accent : PBTheme.textOnDark)
                }

                Label("\(post.commentsCount ?? 0)", systemImage: "bubble.right")
                    .foregroundStyle(PBTheme.textOnDarkSecondary)

                Spacer(minLength: 0)

                Text(post.publishedAt.dateValue(), format: .dateTime.day().month().year())
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .font(PBTheme.Typography.body)
            .buttonStyle(.plain)

            if let image = post.coverLicensedImage {
                LicensedImageCredit(image: image, foregroundColor: PBTheme.textOnDarkSecondary.opacity(0.82))
            }
        }
        .padding(PBTheme.Spacing.lg)
    }

    @ViewBuilder
    private var postBackground: some View {
        Group {
            Group {
                if let coverLicensedImage = post.coverLicensedImage {
                    LicensedImageView(image: coverLicensedImage)
                } else if let coverImagePath = post.coverImagePath {
                    StorageImageView(path: coverImagePath)
                } else {
                    LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .clipped()
        }
    }

}
