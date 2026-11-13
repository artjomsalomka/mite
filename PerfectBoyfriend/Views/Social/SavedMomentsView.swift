import SwiftUI

struct SavedMomentsView: View {
    @StateObject private var store = SavedMomentsStore()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gespeicherte Momente")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Inspirationen, zu denen du später zurückkommen möchtest.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    content
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.sm)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.load() }
        }
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.posts.isEmpty {
            HStack { Spacer(); ProgressView().tint(PBTheme.textOnDark); Spacer() }
                .padding(.vertical, PBTheme.Spacing.xxl)
        } else if let error = store.errorMessage, store.posts.isEmpty {
            PBEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Momente nicht erreichbar",
                message: error,
                actionTitle: "Erneut versuchen"
            ) { Task { await store.load() } }
            .frame(maxWidth: .infinity, minHeight: 360)
        } else if store.posts.isEmpty {
            PBEmptyState(
                symbol: "bookmark",
                title: "Noch nichts gespeichert",
                message: "Tippe bei einem Moment auf das Lesezeichen, um ihn hier wiederzufinden."
            )
            .frame(maxWidth: .infinity, minHeight: 360)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.posts) { post in
                    if let postID = post.id {
                        NavigationLink { SocialPostDetailView(postID: postID) } label: {
                            SavedMomentCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SavedMomentCard: View {
    let post: SocialPost

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 5) {
                Text(post.caption.isEmpty ? post.categories.first ?? "Gemeinsamer Moment" : post.caption)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(3)
                if !post.city.isEmpty {
                    Text(post.city)
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1) }
        .accessibilityLabel(post.caption.isEmpty ? "Gespeicherter Moment" : post.caption)
    }
}
