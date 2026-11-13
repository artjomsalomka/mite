import SwiftUI

/// Instagram-like discovery for intentionally public couple identities. Search is by handle or
/// display-name prefix; an empty query is a small, recent profile directory rather than a list
/// of private accounts.
struct ProfileDirectoryView: View {
    let viewerCoupleId: String
    @ObservedObject var feedService: FeedService

    @StateObject private var store = ProfileDirectoryStore()
    @State private var query = ""

    var body: some View {
        PBScreenContainer {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(query.isEmpty ? "Profile entdecken" : "Treffer")
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text(query.isEmpty ? "Paare, die ihre Ideen öffentlich teilen." : "Suche nach Name oder @Handle")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(.horizontal, PBTheme.Spacing.md)

                content
            }
            .padding(.top, PBTheme.Spacing.sm)
        }
        .navigationTitle("Suchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $query, prompt: "Name oder @Handle")
        .onChange(of: query) { _, value in
            store.search(query: value, excluding: viewerCoupleId)
        }
        .task {
            store.loadDirectory(excluding: viewerCoupleId)
            await feedService.refreshFollowingState()
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.profiles.isEmpty {
            ProgressView("Profile laden …")
                .tint(PBTheme.textOnDark)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.errorMessage {
            PBEmptyState(symbol: "wifi.exclamationmark", title: "Suche nicht erreichbar", message: error,
                         actionTitle: "Erneut versuchen") {
                store.search(query: query, excluding: viewerCoupleId, immediately: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.profiles.isEmpty {
            PBEmptyState(
                symbol: query.isEmpty ? "person.2" : "magnifyingglass",
                title: query.isEmpty ? "Noch keine Profile" : "Keine passenden Profile",
                message: query.isEmpty ? "Sobald Paare ihr Profil einrichten, tauchen sie hier auf." : "Probier einen Namen oder @Handle ohne Sonderzeichen."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.profiles) { profile in
                        ProfileDirectoryRow(profile: profile, feedService: feedService,
                                            isFollowing: feedService.followedCoupleIds.contains(profile.coupleId)) {
                            Task { await feedService.toggleFollow(targetCoupleId: profile.coupleId) }
                        }
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ProfileDirectoryRow: View {
    let profile: CoupleProfile
    @ObservedObject var feedService: FeedService
    let isFollowing: Bool
    let onFollow: () -> Void

    var body: some View {
        NavigationLink {
            PublicCoupleProfileView(profile: profile, feedService: feedService)
        } label: {
            HStack(spacing: PBTheme.Spacing.md) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("@\(profile.handle)")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    if !profile.city.isEmpty {
                        Text(profile.city)
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onFollow) {
                    Text(isFollowing ? "Folgt" : "Folgen")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFollowing ? PBTheme.textOnDark : PBTheme.midnight)
                        .frame(minWidth: 70, minHeight: 34)
                        .background(isFollowing ? .white.opacity(0.11) : PBTheme.surface, in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(isFollowing ? 0.16 : 0), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, PBTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let path = profile.avatarPath {
                StorageImageView(path: path)
            } else {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .frame(width: 54, height: 54)
        .background(.white.opacity(0.10), in: Circle())
        .clipShape(Circle())
    }
}
