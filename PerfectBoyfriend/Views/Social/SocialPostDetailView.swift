import FirebaseAuth
import SwiftUI

/// The immersive reading view for a shared Moment. The image and the people who experienced it
/// lead; metadata, reactions and conversation follow in one calm editorial flow.
struct SocialPostDetailView: View {
    let postID: String
    @StateObject private var store: SocialPostDetailStore
    @StateObject private var commentService: PostCommentService
    @State private var commentDraft = ""
    @State private var isPeopleSheetPresented = false
    @Environment(\.dismiss) private var dismiss

    init(postID: String) {
        self.postID = postID
        _store = StateObject(wrappedValue: SocialPostDetailStore(postID: postID))
        _commentService = StateObject(wrappedValue: PostCommentService(postID: postID))
    }

    var body: some View {
        PBScreenContainer {
            Group {
                if store.isLoading {
                    ProgressView().tint(PBTheme.textOnDark)
                } else if let errorMessage = store.errorMessage, store.post == nil {
                    PBEmptyState(
                        symbol: "sparkles",
                        title: "Moment nicht verfügbar",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen",
                        action: store.retryLoading
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let post = store.post {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xl) {
                            hero(post)
                            story(post)
                            conversation
                        }
                        .padding(.horizontal, PBTheme.Spacing.md)
                        .padding(.top, PBTheme.Spacing.sm)
                        .padding(.bottom, 112)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Moment")
                    .font(PBTheme.Typography.title.weight(.regular))
                    .foregroundStyle(PBTheme.textOnDark)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let authorUID = reportableAuthorUID {
                    Menu {
                        Button("Beitrag melden", systemImage: "exclamationmark.bubble") {
                            Task { await store.reportPost(authorUID: authorUID) }
                        }
                        Button("Profil blockieren", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                            Task {
                                if await store.blockAuthor(authorUID) { dismiss() }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                    }
                    .accessibilityLabel("Weitere Aktionen")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.post != nil {
                commentComposer
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.vertical, PBTheme.Spacing.sm)
                    .background(PBTheme.midnight.opacity(0.96))
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            }
        }
        .sheet(isPresented: $isPeopleSheetPresented) {
            NavigationStack {
                MomentPeopleView(
                    people: store.post?.visiblePeople ?? [],
                    viewerUID: Auth.auth().currentUser?.uid ?? ""
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { await store.refreshViewerReactionState() }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { store.errorMessage != nil && store.post != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "Unbekannter Fehler") }
        .alert("Kommentar-Aktion nicht möglich", isPresented: Binding(
            get: { commentService.actionError != nil },
            set: { if !$0 { commentService.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(commentService.actionError ?? "Unbekannter Fehler") }
        .alert("Danke für deinen Hinweis", isPresented: Binding(
            get: { commentService.confirmationMessage != nil || store.confirmationMessage != nil },
            set: {
                if !$0 {
                    commentService.confirmationMessage = nil
                    store.confirmationMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(commentService.confirmationMessage ?? store.confirmationMessage ?? "") }
    }

    private var reportableAuthorUID: String? {
        let currentUID = Auth.auth().currentUser?.uid
        let authorUID = store.post?.ownerUid ?? store.post?.creator?.uid
        guard let authorUID, authorUID != currentUID else { return nil }
        return authorUID
    }

    private func hero(_ post: SocialPost) -> some View {
        let visuals = postVisuals(post)
        return ZStack(alignment: .bottomLeading) {
            heroVisuals(visuals)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.12), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                HStack(alignment: .top) {
                    if !post.city.isEmpty {
                        Label(post.city, systemImage: "mappin.circle.fill")
                            .font(PBTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(PBTheme.midnight.opacity(0.72), in: Capsule())
                            .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 1) }
                    }
                    Spacer(minLength: 0)
                    if visuals.count > 1 {
                        Label("\(visuals.count)", systemImage: "rectangle.on.rectangle")
                            .font(PBTheme.Typography.micro.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(PBTheme.midnight.opacity(0.72), in: Capsule())
                    }
                }

                Spacer(minLength: 0)

                Button { isPeopleSheetPresented = true } label: {
                    HStack(spacing: PBTheme.Spacing.sm) {
                        SocialPeoplePresentation(people: post.visiblePeople, style: .compact)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PBTheme.midnight.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mitwirkende anzeigen")
            }
            .padding(PBTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 426)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 10)
    }

    @ViewBuilder
    private func heroVisuals(_ visuals: [PostVisual]) -> some View {
        if visuals.isEmpty {
            LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if visuals.count == 1, let visual = visuals.first {
            visualView(visual)
        } else {
            TabView {
                ForEach(visuals) { visual in
                    visualView(visual).tag(visual.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }

    private func story(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            HStack(spacing: 8) {
                if !post.categories.isEmpty {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    Text(post.categories.joined(separator: " · ").uppercased())
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .tracking(2.2)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text((post.publishedAt ?? post.createdAt).dateValue(), format: .dateTime.day().month(.abbreviated))
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.system(size: 27, weight: .regular, design: .default))
                    .tracking(-0.35)
                    .foregroundStyle(PBTheme.textOnDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                reactionButton(
                    title: "\(post.likesCount)",
                    symbol: store.isLiked ? "heart.fill" : "heart",
                    isActive: store.isLiked
                ) { Task { await store.toggleReaction(kind: .like) } }

                interactionDivider

                Label("\(post.commentsCount ?? commentService.comments.count)", systemImage: "bubble.right")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)

                interactionDivider

                reactionButton(
                    title: "\(post.savesCount)",
                    symbol: store.isSaved ? "bookmark.fill" : "bookmark",
                    isActive: store.isSaved
                ) { Task { await store.toggleReaction(kind: .save) } }
            }
            .font(PBTheme.Typography.body)
            .padding(.vertical, 4)

            if let image = post.licensedImages?.first {
                LicensedImageCredit(image: image, foregroundColor: PBTheme.textOnDarkSecondary.opacity(0.75))
            }
        }
    }

    private func reactionButton(title: String, symbol: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isActive ? PBTheme.accent : PBTheme.textOnDark)
        }
        .buttonStyle(.plain)
    }

    private var interactionDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(width: 1, height: 28)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gespräche")
                    .font(PBTheme.Typography.title.weight(.regular))
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer(minLength: 0)
                Text(commentService.comments.isEmpty ? "Noch keine" : "\(commentService.comments.count) Beiträge")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            if commentService.isLoading {
                ProgressView().tint(PBTheme.textOnDark).frame(maxWidth: .infinity, minHeight: 74)
            } else if commentService.comments.isEmpty {
                Text("Starte die Unterhaltung mit einem Gedanken zu diesem Moment.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .padding(.vertical, PBTheme.Spacing.sm)
            } else {
                ForEach(commentService.comments) { comment in commentRow(comment) }
            }
        }
    }

    private func commentRow(_ comment: SocialPostComment) -> some View {
        NavigationLink {
            PublicPersonProfileView(
                uid: comment.authorUid,
                viewerUid: Auth.auth().currentUser?.uid ?? ""
            )
        } label: {
            HStack(alignment: .top, spacing: PBTheme.Spacing.sm) {
                Group {
                    if let avatarPath = comment.author.avatarPath {
                        StorageImageView(path: avatarPath)
                    } else {
                        Text(String(comment.author.displayName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                    }
                }
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(comment.author.displayName)
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(comment.createdAt.dateValue(), format: .relative(presentation: .named))
                            .font(PBTheme.Typography.micro)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    Text(comment.body)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .buttonStyle(.plain)
        .padding(PBTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .contextMenu {
            if comment.authorUid == Auth.auth().currentUser?.uid {
                Button("Kommentar löschen", systemImage: "trash", role: .destructive) {
                    Task { await commentService.delete(comment) }
                }
            } else {
                Button("Kommentar melden", systemImage: "exclamationmark.bubble") {
                    Task { await commentService.report(comment) }
                }
            }
        }
    }

    private var commentComposer: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(PBTheme.textOnDarkSecondary)

            TextField("Teile einen Gedanken …", text: $commentDraft, axis: .vertical)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDark)
                .lineLimit(1...3)
                .tint(PBTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(PBTheme.routeSurfaceRaised, in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.14), lineWidth: 1) }

            Button {
                let body = commentDraft
                commentDraft = ""
                Task { await commentService.add(body: body) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 46, height: 46)
                    .background(PBTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || commentDraft.count > 500)
            .opacity(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
        }
        .padding(.top, 2)
    }

    private enum PostVisual: Identifiable {
        case licensed(LicensedImage)
        case storage(String)
        case video(path: String, posterPath: String?)

        var id: String {
            switch self {
            case .licensed(let image): return "licensed-\(image.url)"
            case .storage(let path): return "storage-\(path)"
            case .video(let path, _): return "video-\(path)"
            }
        }
    }

    private func postVisuals(_ post: SocialPost) -> [PostVisual] {
        let memberMedia = post.orderedMedia.map { media in
            media.kind == .video
                ? PostVisual.video(path: media.path, posterPath: media.thumbnailPath)
                : PostVisual.storage(media.path)
        }
        return (post.licensedImages ?? []).map(PostVisual.licensed) + memberMedia
    }

    @ViewBuilder
    private func visualView(_ visual: PostVisual) -> some View {
        switch visual {
        case .licensed(let image): LicensedImageView(image: image)
        case .storage(let path): StorageImageView(path: path)
        case .video(let path, let posterPath): StorageVideoPlayer(path: path, posterPath: posterPath)
        }
    }
}

/// A shared Moment has no lead author in the UI. This sheet makes everyone equally visible and
/// provides the natural next step into each member's public profile.
private struct MomentPeopleView: View {
    let people: [SocialPersonIdentity]
    let viewerUID: String

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Gemeinsam erlebt")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("\(people.count) \(people.count == 1 ? "Person" : "Menschen") haben diesen Moment geteilt.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    LazyVStack(spacing: PBTheme.Spacing.sm) {
                        ForEach(people) { person in
                            NavigationLink {
                                PublicPersonProfileView(uid: person.uid, viewerUid: viewerUID)
                            } label: {
                                MomentPersonRow(person: person)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct MomentPersonRow: View {
    let person: SocialPersonIdentity

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            Group {
                if let avatarPath = person.avatarPath {
                    StorageImageView(path: avatarPath)
                } else {
                    Text(String(person.displayName.prefix(1)).uppercased())
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(PBTheme.textOnDark)
                }
            }
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.12), in: Circle())
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName)
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text("@\(person.handle)")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PBTheme.accent)
        }
        .padding(PBTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}
