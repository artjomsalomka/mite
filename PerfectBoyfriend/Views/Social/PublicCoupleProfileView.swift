import SwiftUI

struct PublicCoupleProfileView: View {
    let coupleId: String
    let fallbackAuthor: SocialPostAuthor
    @ObservedObject var feedService: FeedService
    let allowsFollowing: Bool
    let editableCouple: Couple?
    let profileService: CoupleProfileService?
    let viewerUID: String?

    @StateObject private var store: PublicCoupleProfileStore

    init(coupleId: String, fallbackAuthor: SocialPostAuthor, feedService: FeedService, allowsFollowing: Bool = true, editableCouple: Couple? = nil, profileService: CoupleProfileService? = nil, viewerUID: String? = nil) {
        self.coupleId = coupleId
        self.fallbackAuthor = fallbackAuthor
        self.feedService = feedService
        self.allowsFollowing = allowsFollowing
        self.editableCouple = editableCouple
        self.profileService = profileService
        self.viewerUID = viewerUID
        _store = StateObject(wrappedValue: PublicCoupleProfileStore(coupleId: coupleId))
    }

    init(profile: CoupleProfile, feedService: FeedService, allowsFollowing: Bool = true, editableCouple: Couple? = nil, profileService: CoupleProfileService? = nil, viewerUID: String? = nil) {
        coupleId = profile.coupleId
        fallbackAuthor = profile.socialAuthor
        self.feedService = feedService
        self.allowsFollowing = allowsFollowing
        self.editableCouple = editableCouple
        self.profileService = profileService
        self.viewerUID = viewerUID
        _store = StateObject(wrappedValue: PublicCoupleProfileStore(coupleId: profile.coupleId))
    }

    var body: some View {
        PBScreenContainer {
            if store.isLoading {
                ProgressView()
                    .tint(PBTheme.textOnDark)
            } else if let loadErrorMessage = store.loadErrorMessage {
                PBEmptyState(
                    symbol: "wifi.exclamationmark",
                    title: "Profil nicht erreichbar",
                    message: loadErrorMessage,
                    actionTitle: "Erneut versuchen",
                    action: store.retryLoading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let profile = store.profile
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        profileHeader(profile: profile)
                        publicMoments
                    }
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func profileHeader(profile: CoupleProfile?) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            Text("Paarprofil")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
            HStack(alignment: .center, spacing: PBTheme.Spacing.md) {
                profileAvatar(profile: profile)
                HStack(spacing: 0) {
                    CoupleProfileStat(value: "\(store.publicPosts.count)", label: "Momente")
                    CoupleProfileStat(value: "\(editableCouple?.members.count ?? 2)", label: "Mitglieder")
                    CoupleProfileStat(value: profile?.city.isEmpty == false ? "✓" : "–", label: "Stadt")
                }
                .frame(maxWidth: .infinity)
            }

            Text(profile?.displayName ?? fallbackAuthor.displayName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
                .lineLimit(1)
            Text("@\(profile?.handle ?? fallbackAuthor.handle)")
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            if let city = profile?.city, !city.isEmpty {
                Text(city)
                    .font(PBTheme.Typography.caption.weight(.medium))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            memberProfiles

            if allowsFollowing {
                Button {
                    Task { await feedService.toggleFollow(targetCoupleId: coupleId) }
                } label: {
                    Text(feedService.followedCoupleIds.contains(coupleId) ? "Folgt" : "Folgen")
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(feedService.followedCoupleIds.contains(coupleId) ? PBTheme.textOnDark : PBTheme.midnight)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(feedService.followedCoupleIds.contains(coupleId) ? .white.opacity(0.12) : PBTheme.surface, in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(feedService.followedCoupleIds.contains(coupleId) ? 0.18 : 0), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            if let editableCouple, let profileService, let profile {
                NavigationLink {
                    CoupleProfileEditorView(couple: editableCouple, profile: profile, profileService: profileService)
                } label: {
                    Text("Paarprofil bearbeiten")
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.11), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.16), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PBTheme.Spacing.md)
    }

    private var publicMoments: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Text("Öffentliche Momente")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .padding(.horizontal, PBTheme.Spacing.md)

            if store.isLoadingPosts {
                ProgressView("Momente laden …")
                    .tint(PBTheme.textOnDark)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let error = store.postsErrorMessage {
                Text(error)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else if store.publicPosts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.grid.3x2")
                        .font(.system(size: 28, weight: .light))
                    Text("Noch keine öffentlichen Momente")
                        .font(PBTheme.Typography.caption)
                }
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(store.publicPosts) { post in
                        NavigationLink {
                            PublicPostDetailView(post: post, feedService: feedService)
                        } label: {
                            PublicPostGridTile(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func avatar(path: String?) -> some View {
        Group {
            if let path {
                StorageImageView(path: path)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(PBTheme.accent)
            }
        }
        .frame(width: 92, height: 92)
        .background(PBTheme.accentMuted, in: Circle())
        .clipShape(Circle())
    }

    @ViewBuilder
    private func profileAvatar(profile: CoupleProfile?) -> some View {
        if let path = profile?.avatarPath ?? fallbackAuthor.avatarPath, !path.isEmpty {
            avatar(path: path)
        } else if let members = editableCouple?.members, !members.isEmpty {
            PBMemberAvatarStack(members: members, avatarSize: 62)
                .frame(width: 92, height: 92)
                .background(.white.opacity(0.10), in: Circle())
        } else {
            avatar(path: nil)
        }
    }

    @ViewBuilder
    private var memberProfiles: some View {
        if let members = editableCouple?.members, !members.isEmpty {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                Text("Mitglieder")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                HStack(spacing: PBTheme.Spacing.sm) {
                    ForEach(members, id: \.uid) { member in
                        NavigationLink {
                            PublicPersonProfileView(uid: member.uid, viewerUid: viewerUID ?? "")
                        } label: {
                            HStack(spacing: 7) {
                                PBMemberAvatar(member: member, index: members.firstIndex(where: { $0.uid == member.uid }) ?? 0, size: 28)
                                Text(member.displayName)
                                    .font(PBTheme.Typography.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay { Capsule().stroke(.white.opacity(0.13), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CoupleProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PublicPostGridTile: View {
    let post: SocialPost

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                visual
                LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)
                if post.orderedMedia.count + (post.licensedImages?.count ?? 0) > 1 {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(8)
                }
                if post.orderedMedia.first?.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .shadow(radius: 3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if !post.city.isEmpty { Text(post.city).font(.system(size: 11, weight: .semibold)) }
                    Text(post.caption.isEmpty ? "Gemeinsamer Moment" : post.caption)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(0.69, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityLabel("Moment von \(post.author.displayName)")
    }

    @ViewBuilder
    private var visual: some View {
        if let image = post.licensedImages?.first {
            LicensedImageView(image: image)
        } else if let media = post.orderedMedia.first {
            StorageImageView(path: media.previewPath)
        } else {
            LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct PublicPostDetailView: View {
    let post: SocialPost
    @ObservedObject var feedService: FeedService

    private var item: DiscoverablePost { DiscoverablePost(post: post) }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                    PublicPostGridTile(post: post)
                        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        HStack {
                            Text("@\(post.author.handle)")
                                .font(PBTheme.Typography.caption.weight(.semibold))
                            Spacer()
                            Label("\(post.likesCount)", systemImage: feedService.likedPostIds.contains(item.id) ? "heart.fill" : "heart")
                        }
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        Text(post.caption)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDark)
                        if !post.city.isEmpty {
                            Label(post.city, systemImage: "mappin.and.ellipse")
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                }
                .padding(PBTheme.Spacing.md)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
