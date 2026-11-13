import SwiftUI

struct PublicPersonProfileView: View {
    let uid: String
    let viewerUid: String
    @StateObject private var store: PublicPersonProfileStore
    @StateObject private var followService = PersonFollowService()
    @State private var confirmsBlock = false

    init(uid: String, viewerUid: String) {
        self.uid = uid
        self.viewerUid = viewerUid
        _store = StateObject(wrappedValue: PublicPersonProfileStore(uid: uid))
    }

    var body: some View {
        PBScreenContainer {
            if store.isLoading {
                ProgressView().tint(PBTheme.textOnDark)
            } else if let error = store.errorMessage {
                PBEmptyState(symbol: "wifi.exclamationmark", title: "Profil nicht erreichbar", message: error, actionTitle: "Erneut versuchen", action: store.retryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if followService.blockedUIDs.contains(uid) {
                if followService.blockedByMeUIDs.contains(uid) {
                    PBEmptyState(symbol: "hand.raised.fill", title: "Profil blockiert", message: "Beiträge und Profil dieses Kontos werden dir nicht mehr angezeigt.", actionTitle: "Blockierung aufheben") {
                        Task { await followService.unblock(targetUID: uid) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PBEmptyState(symbol: "hand.raised.fill", title: "Profil nicht verfügbar", message: "Zwischen diesen Profilen besteht eine Blockierung.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let profile = store.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        header(profile)
                        moments
                    }
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if uid != viewerUid {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Profil melden", systemImage: "exclamationmark.bubble") { Task { await followService.report(targetUID: uid) } }
                        Button("Profil blockieren", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(PBTheme.textOnDark)
                    }
                }
            }
        }
        .task { await followService.refresh() }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { followService.actionError != nil }, set: { if !$0 { followService.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(followService.actionError ?? "Unbekannter Fehler") }
        .alert("Profil blockieren?", isPresented: $confirmsBlock) {
            Button("Blockieren", role: .destructive) { Task { await followService.block(targetUID: uid) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieses Profil und seine öffentlichen Momente werden dir nicht mehr angezeigt. Du kannst die Blockierung später wieder aufheben.")
        }
    }

    private func header(_ profile: PersonProfile) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            HStack(spacing: PBTheme.Spacing.md) {
                Group {
                    if let avatarPath = profile.avatarPath { StorageImageView(path: avatarPath) }
                    else { Text(String(profile.displayName.prefix(1)).uppercased()).font(.system(size: 34, weight: .light)).foregroundStyle(PBTheme.textOnDark) }
                }
                .frame(width: 82, height: 82)
                .background(.white.opacity(0.10), in: Circle())
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName).font(.system(size: 27, weight: .light)).foregroundStyle(PBTheme.textOnDark)
                    Text("@\(profile.handle)").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    if !profile.city.isEmpty { Label(profile.city, systemImage: "mappin.and.ellipse").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary) }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(store.posts.count)").font(.system(size: 20, weight: .light)).foregroundStyle(PBTheme.textOnDark)
                    Text("Momente").font(.system(size: 10, weight: .medium)).foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                VStack(spacing: 2) {
                    Text("\(profile.followerCount ?? 0)").font(.system(size: 20, weight: .light)).foregroundStyle(PBTheme.textOnDark)
                    Text("Follower").font(.system(size: 10, weight: .medium)).foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            }
            if let coupleId = profile.linkedCoupleId {
                NavigationLink {
                    PublicCoupleProfileView(coupleId: coupleId,
                                            fallbackAuthor: SocialPostAuthor(coupleId: coupleId, displayName: "Verbundenes Paar", handle: "paar", avatarPath: nil),
                                            feedService: FeedService())
                } label: {
                    Label("Als Paar verbunden", systemImage: "heart.link")
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if !profile.bio.isEmpty { Text(profile.bio).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary) }
            if uid != viewerUid {
                Button {
                    Task { await followService.toggle(targetUID: uid) }
                } label: {
                    Text(followService.followingUIDs.contains(uid) ? "Folgt" : "Folgen")
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(followService.followingUIDs.contains(uid) ? PBTheme.textOnDark : PBTheme.midnight)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(followService.followingUIDs.contains(uid) ? .white.opacity(0.12) : PBTheme.surface, in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(followService.followingUIDs.contains(uid) ? 0.18 : 0), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PBTheme.Spacing.md)
    }

    private var moments: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text("Öffentliche Momente").font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                .padding(.horizontal, PBTheme.Spacing.md)
            if store.isLoadingPosts {
                ProgressView().tint(PBTheme.textOnDark).frame(maxWidth: .infinity, minHeight: 130)
            } else if let error = store.postsErrorMessage {
                VStack(spacing: PBTheme.Spacing.sm) {
                    Text(error).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    Button("Erneut versuchen") { store.retryLoading() }
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else if store.posts.isEmpty {
                Text("Noch keine öffentlichen Momente.").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(store.posts) { post in
                        if let postID = post.id {
                            NavigationLink { SocialPostDetailView(postID: postID) } label: {
                                PublicPersonPostTile(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct PublicPersonPostTile: View {
    let post: SocialPost
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = post.licensedImages?.first { LicensedImageView(image: image) }
                else if let media = post.orderedMedia.first {
                    ZStack {
                        StorageImageView(path: media.previewPath)
                        if media.kind == .video {
                            Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 3)
                        }
                    }
                }
                else { PBTheme.midnightRaised }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
