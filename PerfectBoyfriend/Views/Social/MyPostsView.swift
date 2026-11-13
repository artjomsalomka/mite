import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The private "my posts" surface comes before discovery/feed work. It gives a couple ownership
/// and deletion controls from the first social release, independently of later follower features.
struct MyPostsView: View {
    let couple: Couple
    let creatorUid: String
    let savedDates: [SavedDate]
    let defaultCity: String
    @ObservedObject var postService: PostService
    @StateObject private var groupEventService = GroupEventService()

    @State private var isComposerPresented = false
    @State private var postPendingDeletion: SocialPost?
    @State private var postPendingPrivacyChange: SocialPost?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                                Text("Eure Momente")
                                    .font(PBTheme.Typography.display)
                                    .foregroundStyle(PBTheme.textOnDark)
                                Text("Kleine Erinnerungen, die bei euch bleiben dürfen.")
                                    .font(PBTheme.Typography.body)
                                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                            }
                            Spacer(minLength: PBTheme.Spacing.sm)
                            PBIconCircleButton(symbol: "plus", label: "Beitrag erstellen") {
                                isComposerPresented = true
                            }
                        }

                        postsContent
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isComposerPresented) {
                NavigationStack {
                    PostComposerView(
                        ownerID: couple.id ?? "",
                        creatorUid: creatorUid,
                        savedDates: savedDates,
                        groupEvents: groupEventService.events,
                        defaultCity: defaultCity,
                        postService: postService
                    )
                }
            }
            .sheet(item: $postPendingPrivacyChange) { post in
                NavigationStack {
                    PostVisibilityEditor(post: post, postService: postService)
                }
            }
            .alert(
                "Beitrag löschen?",
                isPresented: Binding(
                    get: { postPendingDeletion != nil },
                    set: { if !$0 { postPendingDeletion = nil } }
                ),
                presenting: postPendingDeletion
            ) { post in
                Button("Löschen", role: .destructive) {
                    Task { await delete(post) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { _ in
                Text("Der Beitrag, seine Fotos sowie mögliche Feed-Einträge werden dauerhaft entfernt.")
            }
            .alert("Beitrag konnte nicht gelöscht werden", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .overlay {
                if isDeleting {
                    ProgressView("Lösche Beitrag …")
                        .tint(PBTheme.textPrimary)
                        .padding(PBTheme.Spacing.md)
                        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                }
            }
        }
        .task { groupEventService.startListening(uid: creatorUid) }
    }

    @ViewBuilder
    private var postsContent: some View {
        if postService.isLoading && postService.posts.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(PBTheme.textOnDark)
                Spacer()
            }
            .padding(.vertical, PBTheme.Spacing.xxl)
        } else if let loadErrorMessage = postService.loadErrorMessage, postService.posts.isEmpty {
            PBEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Momente nicht erreichbar",
                message: loadErrorMessage,
                actionTitle: "Erneut versuchen",
                action: postService.retryLoading
            )
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xxl)
        } else if postService.posts.isEmpty {
            PBEmptyState(
                symbol: "camera.on.rectangle",
                title: "Noch kein geteilter Moment",
                message: "Haltet eine Date-Idee für euch, eure Follower:innen oder öffentlich fest.",
                actionTitle: "Moment festhalten"
            ) {
                isComposerPresented = true
            }
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xxl)
        } else {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                PBSectionTitle(title: "Eure Beiträge")
                ForEach(postService.posts) { post in
                    MyPostRow(post: post, sourceDate: sourceDate(for: post))
                        .contextMenu {
                            Button {
                                postPendingPrivacyChange = post
                            } label: {
                                Label("Sichtbarkeit ändern", systemImage: "lock.shield")
                            }
                            Button(role: .destructive) {
                                postPendingDeletion = post
                            } label: {
                                Label("Beitrag löschen", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func sourceDate(for post: SocialPost) -> SavedDate? {
        guard let sourceDateId = post.sourceDateId else { return nil }
        return savedDates.first { $0.id == sourceDateId }
    }

    private func delete(_ post: SocialPost) async {
        isDeleting = true
        defer {
            isDeleting = false
            postPendingDeletion = nil
        }
        do {
            try await postService.delete(post: post)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PostVisibilityEditor: View {
    let post: SocialPost
    @ObservedObject var postService: PostService

    @Environment(\.dismiss) private var dismiss
    @State private var visibility: SocialPostVisibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(post: SocialPost, postService: PostService) {
        self.post = post
        self.postService = postService
        _visibility = State(initialValue: post.visibility)
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Privatsphäre")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Du bestimmst, wer euren Moment sehen darf.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        ForEach(SocialPostVisibility.allCases) { option in
                            Button {
                                visibility = option
                            } label: {
                                HStack(spacing: PBTheme.Spacing.md) {
                                    Image(systemName: option.iconName)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(visibility == option ? PBTheme.accent : PBTheme.textSecondary)
                                        .frame(width: 38, height: 38)
                                        .background(visibility == option ? PBTheme.accentMuted : PBTheme.surfaceMuted, in: Circle())
                                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                                        Text(option.title)
                                            .font(PBTheme.Typography.body.weight(.semibold))
                                            .foregroundStyle(PBTheme.textPrimary)
                                        Text(option.explanation)
                                            .font(PBTheme.Typography.caption)
                                            .foregroundStyle(PBTheme.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: visibility == option ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(visibility == option ? PBTheme.accent : PBTheme.textSecondary)
                                }
                                .padding(PBTheme.Spacing.md)
                                .background(visibility == option ? PBTheme.surfaceMuted.opacity(0.8) : PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm)
                            .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }

                    PBPrimaryButton(title: "Sichtbarkeit speichern", symbol: "lock.shield", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(visibility == post.visibility)
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
                    .foregroundStyle(PBTheme.textOnDark)
                    .disabled(isSaving)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await postService.updateVisibility(of: post, to: visibility)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MyPostRow: View {
    let post: SocialPost
    let sourceDate: SavedDate?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            postBackground

            LinearGradient(
                colors: [Color.black.opacity(0.36), .clear, Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(post.visibility.title, systemImage: post.visibility.iconName)
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PBTheme.midnight.opacity(0.62), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
                    Spacer()
                    if post.orderedMedia.count > 1 {
                        Label("\(post.orderedMedia.count)", systemImage: "rectangle.on.rectangle")
                            .font(PBTheme.Typography.micro.weight(.bold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(PBTheme.midnight.opacity(0.62), in: Capsule())
                    }
                }
                Spacer(minLength: PBTheme.Spacing.xl)
                details
            }
            .padding(PBTheme.Spacing.md)

            if post.orderedMedia.first?.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PBTheme.midnight)
                    .frame(width: 50, height: 50)
                    .background(PBTheme.textOnDark.opacity(0.94), in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 9, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.24), lineWidth: 1) }
        .shadow(color: PBTheme.Shadow.card, radius: 16, y: 8)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
            if let sourceDate {
                Label(sourceDate.title, systemImage: "calendar")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .lineLimit(1)
            }
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(PBTheme.Typography.body.weight(.medium))
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(4)
            } else {
                Text("Ein Moment von euch")
                    .font(PBTheme.Typography.title.weight(.regular))
                    .foregroundStyle(PBTheme.textOnDark)
            }
            HStack(spacing: PBTheme.Spacing.sm) {
                if !post.categories.isEmpty {
                    Text(post.categories.joined(separator: " · "))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(post.createdAt.dateValue(), format: .dateTime.day().month().year())
            }
            .font(PBTheme.Typography.caption)
            .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    @ViewBuilder
    private var postBackground: some View {
        if let image = post.licensedImages?.first {
            LicensedImageView(image: image)
        } else if let media = post.orderedMedia.first {
            StorageImageView(path: media.previewPath)
        } else {
            LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.routeSurfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct PostComposerView: View {
    private static let availableCategories = ["Kulinarisch", "Entspannt", "Aktiv", "Kulturell", "Romantisch", "Abenteuer"]

    let ownerID: String
    let creatorUid: String
    let savedDates: [SavedDate]
    let groupEvents: [GroupEvent]
    let visibilityOptions: [SocialPostVisibility]
    @ObservedObject var postService: PostService

    @Environment(\.dismiss) private var dismiss
    @State private var sourceDateId: String?
    @State private var sourceEventId: String?
    @State private var caption = ""
    @State private var city: String
    @State private var visibility: SocialPostVisibility = .private
    @State private var categories: [String] = []
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var additionalPickerItems: [PhotosPickerItem] = []
    @State private var selectedMedia: [PostMediaDraft] = []
    @State private var isPreparingMedia = false
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var collaborators: [PersonProfile] = []
    @State private var isCollaboratorPickerPresented = false

    init(
        ownerID: String,
        creatorUid: String,
        savedDates: [SavedDate],
        groupEvents: [GroupEvent],
        defaultCity: String,
        visibilityOptions: [SocialPostVisibility] = SocialPostVisibility.allCases,
        postService: PostService
    ) {
        self.ownerID = ownerID
        self.creatorUid = creatorUid
        self.savedDates = savedDates
        self.groupEvents = groupEvents
        self.visibilityOptions = visibilityOptions
        self.postService = postService
        _city = State(initialValue: defaultCity)
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    composerHeader
                    mediaPicker
                    copyAndContext
                    peopleAndVisibility
                    locationAndTags

                    Button { Task { await publish() } } label: {
                        HStack(spacing: 10) {
                            if isPublishing { ProgressView().tint(PBTheme.midnight) }
                            Image(systemName: "paperplane.fill")
                            Text(isPublishing ? "Wird geteilt …" : "Moment veröffentlichen")
                        }
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.midnight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(PBTheme.textOnDark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPublishing || isPreparingMedia || caption.count > 500)
                    .opacity(isPublishing || isPreparingMedia ? 0.55 : 1)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm)
                            .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.sm)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $isCollaboratorPickerPresented) {
            CollaboratorPickerView(excluding: creatorUid, selected: $collaborators)
        }
        .onChange(of: selectedPickerItems) { _, items in
            Task { await prepareMedia(items, appending: false) }
        }
        .onChange(of: additionalPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await prepareMedia(items, appending: true)
                additionalPickerItems = []
            }
        }
        .onChange(of: sourceEventId) { _, eventId in
            guard let event = groupEvents.first(where: { $0.id == eventId }) else { return }
            collaborators = event.participants
                .filter { $0.uid != creatorUid && $0.status == .going }
                .map { PersonProfile(uid: $0.uid, displayName: $0.displayName, handle: $0.handle, bio: "", city: "", cityNormalized: "", avatarPath: nil, isDiscoverable: true, followerCount: nil, followingCount: nil, linkedCoupleId: nil, createdAt: event.createdAt, updatedAt: event.updatedAt) }
        }
    }

    private var composerHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Moment teilen")
                    .font(PBTheme.Typography.display)
                    .foregroundStyle(PBTheme.textOnDark)
                Text(selectedMedia.isEmpty ? "Foto oder Video auswählen" : "\(selectedMedia.count) von 8 Medien ausgewählt")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.10), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(isPublishing)
        }
    }

    private var mediaPicker: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            if isPreparingMedia {
                HStack(spacing: 12) {
                    ProgressView().tint(PBTheme.accent)
                    Text("Medien werden vorbereitet …")
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
            } else if selectedMedia.isEmpty {
                PhotosPicker(selection: $selectedPickerItems, maxSelectionCount: 8, matching: .any(of: [.images, .videos])) {
                    VStack(spacing: 13) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 31, weight: .medium))
                        Text("Fotos & Videos hinzufügen")
                            .font(PBTheme.Typography.body.weight(.semibold))
                        Text("Bis zu acht Erinnerungen, in eurer Reihenfolge.")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(maxWidth: .infinity, minHeight: 246)
                    .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [6, 6])) }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedMedia.enumerated()), id: \.element.id) { index, media in
                            composerMediaCard(media: media, index: index)
                        }
                        if selectedMedia.count < 8 {
                            PhotosPicker(selection: $additionalPickerItems, maxSelectionCount: max(1, 8 - selectedMedia.count), matching: .any(of: [.images, .videos])) {
                                Image(systemName: "plus")
                                    .font(.system(size: 23, weight: .medium))
                                    .foregroundStyle(PBTheme.textOnDark)
                                    .frame(width: 74, height: 112)
                                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Text("Die Reihenfolge bleibt im Beitrag erhalten. Fotos werden ohne Ortsmetadaten gespeichert; Clips erscheinen mit einem stillen Vorschaubild im Feed.")
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }

    private func composerMediaCard(media: PostMediaDraft, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = media.previewImage ?? UIImage(data: media.data) {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    PBTheme.routeSurfaceRaised
                }
            }
            .frame(width: 212, height: 286)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 7) {
                    Image(systemName: media.kind == .video ? "play.fill" : "photo.fill")
                    Text(media.kind == .video ? "VIDEO" : "FOTO")
                }
                .font(PBTheme.Typography.micro.weight(.bold))
                .foregroundStyle(PBTheme.textOnDark)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(PBTheme.midnight.opacity(0.72), in: Capsule())
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(PBTheme.Typography.micro.weight(.bold))
                    .foregroundStyle(PBTheme.midnight)
                    .frame(width: 27, height: 27)
                    .background(PBTheme.textOnDark, in: Circle())
                    .padding(11)
            }
            Button { selectedMedia.remove(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 33, height: 33)
                    .background(PBTheme.midnight.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private var copyAndContext: some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField("Was macht diesen Moment besonders?", text: $caption, axis: .vertical)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDark)
                .lineLimit(3...7)
            HStack {
                Text("\(caption.count)/500")
                Spacer()
                Picker("Erinnerung", selection: $sourceDateId) {
                    Text("Keine Verknüpfung").tag(String?.none)
                    ForEach(savedDates) { date in if let id = date.id { Text(date.title).tag(Optional(id)) } }
                }
                .labelsHidden()
                .tint(PBTheme.textOnDark)
            }
            .font(PBTheme.Typography.micro)
            .foregroundStyle(PBTheme.textOnDarkSecondary)
            if !completedGroupEvents.isEmpty {
                Picker("Gruppenplan", selection: $sourceEventId) {
                    Text("Kein Gruppenplan").tag(String?.none)
                    ForEach(completedGroupEvents) { event in if let id = event.id { Text(event.title).tag(Optional(id)) } }
                }
                .font(PBTheme.Typography.micro)
                .tint(PBTheme.textOnDark)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var peopleAndVisibility: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Gemeinsam teilen", systemImage: "person.2.fill")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Button("Hinzufügen") { isCollaboratorPickerPresented = true }
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.accent)
            }
            if collaborators.isEmpty {
                Text("Menschen können nach ihrer Zustimmung denselben Moment auf ihrem Profil zeigen.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) { ForEach(collaborators) { person in CollaboratorChip(person: person) { collaborators.removeAll { $0.uid == person.uid } } } }
                }.scrollIndicators(.hidden)
            }
            Divider().overlay(.white.opacity(0.12))
            Picker("Sichtbarkeit", selection: $visibility) {
                ForEach(visibilityOptions) { value in
                    Label(value.title, systemImage: value.iconName).tag(value)
                }
            }
            .tint(PBTheme.accent)
            Text(visibility.explanation)
                .font(PBTheme.Typography.micro)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var locationAndTags: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Ort", text: $city)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDark)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white.opacity(0.07), in: Capsule())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(Self.availableCategories, id: \.self) { category in
                    let selected = categories.contains(category)
                    Button { toggle(category) } label: {
                        Text(category)
                            .font(PBTheme.Typography.micro.weight(.semibold))
                            .foregroundStyle(selected ? PBTheme.midnight : PBTheme.textOnDark)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(selected ? PBTheme.textOnDark : .white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private func toggle(_ category: String) {
        if let index = categories.firstIndex(of: category) {
            categories.remove(at: index)
        } else if categories.count < 4 {
            categories.append(category)
        }
    }

    private func prepareMedia(_ items: [PhotosPickerItem], appending: Bool) async {
        isPreparingMedia = true
        defer { isPreparingMedia = false }
        do {
            var media: [PostMediaDraft] = []
            for item in items.prefix(8) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let contentType = item.supportedContentTypes.first { $0.conforms(to: .movie) }
                if let contentType {
                    let poster = try ImageUploadService.videoPoster(from: data)
                    media.append(PostMediaDraft(
                        data: data,
                        kind: .video,
                        filenameExtension: contentType.preferredFilenameExtension ?? "mov",
                        contentType: contentType.preferredMIMEType ?? "video/quicktime",
                        previewImage: poster
                    ))
                } else {
                    media.append(PostMediaDraft(data: data, kind: .image, previewImage: UIImage(data: data)))
                }
            }
            selectedMedia = appending ? Array((selectedMedia + media).prefix(8)) : media
        } catch {
            if !appending { selectedMedia = [] }
            errorMessage = "Mindestens eines der ausgewählten Medien konnte nicht geladen werden."
        }
    }

    private func publish() async {
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }
        do {
            try await postService.createAndPublish(
                sourceDateId: sourceDateId,
                sourceEventId: sourceEventId,
                caption: caption,
                visibility: visibility,
                city: city,
                categories: categories,
                media: selectedMedia,
                ownerID: ownerID,
                collaboratorUids: collaborators.map(\.uid)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var completedGroupEvents: [GroupEvent] {
        groupEvents.filter { $0.creatorUid == creatorUid && $0.status == .planned && $0.scheduledAt.dateValue() <= Date() }
    }
}

private struct CollaboratorChip: View {
    let person: PersonProfile
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            Label("@\(person.handle)", systemImage: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PBTheme.textOnDark)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
