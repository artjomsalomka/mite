import PhotosUI
import SwiftUI

struct CoupleProfileView: View {
    let couple: Couple
    @ObservedObject var profileService: CoupleProfileService
    @ObservedObject var personProfileService: PersonProfileService
    @ObservedObject var authManager: AuthManager
    let savedDates: [SavedDate]
    @ObservedObject var postService: PostService
    @ObservedObject var personalPostService: PostService

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                Group {
                    if profileService.isLoading {
                        ProgressView()
                            .tint(PBTheme.textOnDark)
                    } else if let profile = profileService.profile {
                        ProfileDetailView(
                            profile: profile,
                            couple: couple,
                            profileService: profileService,
                            personProfileService: personProfileService,
                            authManager: authManager,
                            savedDates: savedDates,
                            postService: postService,
                            personalPostService: personalPostService
                        )
                    } else if let loadErrorMessage = profileService.loadErrorMessage {
                        PBEmptyState(
                            symbol: "wifi.exclamationmark",
                            title: "Profil nicht erreichbar",
                            message: loadErrorMessage,
                            actionTitle: "Erneut versuchen",
                            action: profileService.retryLoading
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProfileSetupView(couple: couple, profileService: profileService)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ProfileSetupView: View {
    let couple: Couple
    @ObservedObject var profileService: CoupleProfileService

    var body: some View {
        VStack(spacing: PBTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(PBTheme.accent)
            VStack(spacing: PBTheme.Spacing.sm) {
                Text("Macht euch auffindbar")
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                Text("Mit einem Profil könnt ihr später eigene Date-Momente teilen und andere Paare entdecken.")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PBTheme.Spacing.lg)
            }
            NavigationLink {
                CoupleProfileEditorView(couple: couple, profile: nil, profileService: profileService)
            } label: {
                Text("Profil einrichten")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PBTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, PBTheme.Spacing.lg)
            Spacer()
        }
        .padding(.horizontal, PBTheme.Spacing.md)
    }
}

private struct ProfileDetailView: View {
    let profile: CoupleProfile
    let couple: Couple
    @ObservedObject var profileService: CoupleProfileService
    @ObservedObject var personProfileService: PersonProfileService
    @ObservedObject var authManager: AuthManager
    let savedDates: [SavedDate]
    @ObservedObject var postService: PostService
    @ObservedObject var personalPostService: PostService
    @State private var selectedMoments: ProfileMomentFilter = .moments

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                profileNavigation
                personalHeader
                pairProfileLink
                momentSwitcher
                momentsGrid
            }
            .padding(.top, PBTheme.Spacing.md)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
    }

    private var profileNavigation: some View {
        HStack {
            Text("Profil").font(.system(size: 31, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Spacer()
            NavigationLink { ProfileSettingsView(authManager: authManager) } label: {
                Image(systemName: "gearshape").font(.system(size: 19, weight: .regular)).foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 42, height: 42).background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Konto und Einstellungen")
        }
        .padding(.horizontal, PBTheme.Spacing.md)
    }

    private var personalHeader: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            HStack(spacing: PBTheme.Spacing.md) {
                personalAvatar
                HStack(spacing: 0) {
                    ProfileStat(value: "\(personalPosts.count)", label: "Momente")
                    ProfileStat(value: "\(personProfileService.profile?.followerCount ?? 0)", label: "Follower")
                    ProfileStat(value: "\(personProfileService.profile?.followingCount ?? 0)", label: "Folgt")
                }.frame(maxWidth: .infinity)
            }
            Text(personName).font(.system(size: 24, weight: .light)).foregroundStyle(PBTheme.textOnDark).lineLimit(1)
            Text("@\(personHandle)").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            if let bio = personProfileService.profile?.bio, !bio.isEmpty { Text(bio).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary) }
            if let city = personProfileService.profile?.city, !city.isEmpty { Text(city).font(PBTheme.Typography.caption.weight(.medium)).foregroundStyle(PBTheme.textOnDarkSecondary) }
            NavigationLink { PublicIdentityEditorView(authManager: authManager, personProfileService: personProfileService) } label: {
                Text("Profil bearbeiten").font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                    .frame(maxWidth: .infinity, minHeight: 44).background(.white.opacity(0.11), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.15), lineWidth: 1) }
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, PBTheme.Spacing.md)
    }

    private var pairProfileLink: some View {
        NavigationLink {
            PublicCoupleProfileView(
                profile: profile,
                feedService: FeedService(),
                allowsFollowing: false,
                editableCouple: couple,
                profileService: profileService,
                viewerUID: authManager.firebaseUser?.uid
            )
        } label: {
            HStack(spacing: PBTheme.Spacing.md) {
                Group {
                    if let path = profile.avatarPath, !path.isEmpty {
                        StorageImageView(path: path)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.10), in: Circle())
                            .clipShape(Circle())
                    } else {
                        PBMemberAvatarStack(members: couple.members, avatarSize: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Verbunden mit").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    Text(profile.displayName).font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark).lineLimit(1)
                    Text("Paarprofil").font(PBTheme.Typography.caption.weight(.medium)).foregroundStyle(PBTheme.accent)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .padding(PBTheme.Spacing.md).background(PBTheme.midnightRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(.plain).padding(.horizontal, PBTheme.Spacing.md)
    }

    private var momentSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(ProfileMomentFilter.allCases) { filter in
                Button { withAnimation(.snappy(duration: 0.22)) { selectedMoments = filter } } label: {
                    VStack(spacing: 7) {
                        Image(systemName: filter.symbol).font(.system(size: 16, weight: .medium))
                        Text(filter.title).font(PBTheme.Typography.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedMoments == filter ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Capsule().fill(selectedMoments == filter ? PBTheme.accent : .clear).frame(width: 42, height: 2) }
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, PBTheme.Spacing.md)
    }

    private var momentsGrid: some View {
        Group {
            if displayedPosts.isEmpty {
                VStack(spacing: PBTheme.Spacing.sm) {
                    Image(systemName: selectedMoments == .moments ? "square.grid.3x3" : "person.2").font(.system(size: 27, weight: .light))
                    Text(selectedMoments == .moments ? "Deine Momente erscheinen hier." : "Noch keine gemeinsamen Markierungen.").font(PBTheme.Typography.caption)
                }.foregroundStyle(PBTheme.textOnDarkSecondary).frame(maxWidth: .infinity, minHeight: 170)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(displayedPosts) { post in
                        if let postID = post.id {
                            NavigationLink { SocialPostDetailView(postID: postID) } label: { ProfileMomentTile(post: post) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
            }
        }
    }

    @ViewBuilder private var personalAvatar: some View {
        Group {
            if let path = personProfileService.profile?.avatarPath, !path.isEmpty { StorageImageView(path: path) }
            else if let path = authManager.appUser?.avatarPath, !path.isEmpty { StorageImageView(path: path) }
            else { Text(personInitials).font(.system(size: 34, weight: .light)).foregroundStyle(PBTheme.textOnDark) }
        }
        .frame(width: 92, height: 92).background(.white.opacity(0.10), in: Circle()).clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.20), lineWidth: 1) }
    }

    private var personName: String { personProfileService.profile?.displayName ?? authManager.appUser?.displayName ?? "Dein Profil" }
    private var personHandle: String { personProfileService.profile?.handle ?? "moment" }
    private var personInitials: String { String(personName.prefix(1)).uppercased() }
    private var personalPosts: [SocialPost] {
        guard let uid = authManager.firebaseUser?.uid else { return postService.posts }
        let pairContributions = postService.posts.filter { $0.ownerUid == uid || $0.creator?.uid == uid }
        var merged = Dictionary(uniqueKeysWithValues: personalPostService.posts.compactMap { post in
            post.id.map { ($0, post) }
        })
        pairContributions.forEach { post in
            if let id = post.id { merged[id] = post }
        }
        return merged.values.sorted { $0.createdAt.dateValue() > $1.createdAt.dateValue() }
    }
    private var displayedPosts: [SocialPost] {
        switch selectedMoments {
        case .moments: return personalPosts
        case .tagged:
            guard let uid = authManager.firebaseUser?.uid else { return [] }
            let allPosts = postService.posts + personalPostService.posts
            return allPosts.filter { ($0.collaborators ?? []).contains { $0.uid == uid && $0.status == .accepted } }
        }
    }
}

private enum ProfileMomentFilter: CaseIterable, Identifiable {
    case moments
    case tagged

    var id: Self { self }
    var title: String { self == .moments ? "Momente" : "Markiert" }
    var symbol: String { self == .moments ? "square.grid.3x3" : "person.crop.rectangle" }
}

private struct ProfileStat: View {
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

private struct ProfileMomentTile: View {
    let post: SocialPost

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if let image = post.licensedImages?.first {
                    LicensedImageView(image: image)
                } else if let media = post.orderedMedia.first {
                    StorageImageView(path: media.previewPath)
                } else {
                    LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                if post.orderedMedia.count + (post.licensedImages?.count ?? 0) > 1 {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(7)
                        .shadow(radius: 3)
                }
                if post.orderedMedia.first?.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .shadow(radius: 3)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.66)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    if !post.city.isEmpty {
                        Text(post.city)
                            .font(.system(size: 11, weight: .semibold))
                    }
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
    }
}

struct ProfileSettingsView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                    Text("Einstellungen")
                        .font(.system(size: 31, weight: .light))
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.bottom, PBTheme.Spacing.sm)

                    NavigationLink { PersonalProfileEditorView(authManager: authManager) } label: {
                        ProfileActionRow(symbol: "person.crop.circle", title: "Persönliches Profil", subtitle: "Name und persönliches Foto")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { PushNotificationSettingsView(authManager: authManager) } label: {
                        ProfileActionRow(symbol: "bell", title: "Benachrichtigungen", subtitle: "Erinnerungen auf diesem Gerät")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { SavedMomentsView() } label: {
                        ProfileActionRow(symbol: "bookmark", title: "Gespeicherte Momente", subtitle: "Inspirationen für später")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { AccountManagementView(authManager: authManager) } label: {
                        ProfileActionRow(symbol: "lock.shield", title: "Konto & Sicherheit", subtitle: "Datenschutz, Regeln und Konto löschen")
                    }
                    .buttonStyle(.plain)

                    Button("Abmelden", role: .destructive) { try? authManager.signOut() }
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.destructive)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PBTheme.destructive.opacity(0.13), in: Capsule())
                        .padding(.top, PBTheme.Spacing.md)
                }
                .padding(PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct CoupleMilestonesSection: View {
    let savedDates: [SavedDate]

    private var ratedDateCount: Int {
        savedDates.filter { $0.rating != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
            HStack {
                Text("Gemeinsam bewertet")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                Spacer()
                Text("\(ratedDateCount) Dates")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
            }

            ForEach(CoupleMilestones.all) { milestone in
                let unlocked = milestone.isUnlocked(with: ratedDateCount)
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                    HStack(spacing: PBTheme.Spacing.sm) {
                        Image(systemName: milestone.symbolName)
                            .foregroundStyle(unlocked ? PBTheme.accent : PBTheme.textOnDarkSecondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title)
                                .font(PBTheme.Typography.body.bold())
                                .foregroundStyle(PBTheme.textOnDark)
                            Text(milestone.subtitle)
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        Spacer()
                        Text(unlocked ? "Erreicht" : "\(min(ratedDateCount, milestone.requiredRatedDates))/\(milestone.requiredRatedDates)")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(unlocked ? PBTheme.success : PBTheme.textOnDarkSecondary)
                    }

                    if !unlocked {
                        ProgressView(
                            value: Double(min(ratedDateCount, milestone.requiredRatedDates)),
                            total: Double(milestone.requiredRatedDates)
                        )
                        .tint(PBTheme.accent)
                    }
                }
                .padding(.vertical, PBTheme.Spacing.xs)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }
}

struct ProfileActionRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 38, height: 38)
                .background(PBTheme.accent.opacity(0.54), in: Circle())

            VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                Text(title)
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text(subtitle)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }
}

/// The individual identity within a shared couple. It intentionally uses the same restrained
/// Midnight panels as the profile overview while keeping personal images out of public feeds.
struct PersonalProfileEditorView: View {
    @ObservedObject var authManager: AuthManager

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var avatarPath: String?
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(authManager: AuthManager) {
        self.authManager = authManager
        _displayName = State(initialValue: authManager.appUser?.displayName ?? "")
        _avatarPath = State(initialValue: authManager.appUser?.avatarPath)
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    header
                    identityPanel

                    PBPrimaryButton(title: "Änderungen speichern", symbol: "checkmark", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PBTheme.destructive.opacity(0.72), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: pickedAvatar) { _, newValue in
            guard let newValue else { return }
            Task { avatarData = try? await newValue.loadTransferable(type: Data.self) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                Text("Dein Profil")
                    .font(PBTheme.Typography.display)
                    .foregroundStyle(PBTheme.textOnDark)
                Text("Dein Bild bleibt innerhalb eures verbundenen Paars.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: PBTheme.Spacing.sm)
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil schließen")
        }
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
            HStack(spacing: PBTheme.Spacing.md) {
                avatarPicker
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                    Text("Dein Foto")
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Nur du und dein:e Partner:in können es sehen.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                Text("Wie sollen wir dich nennen?")
                    .font(PBTheme.Typography.caption.weight(.medium))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                TextField("Dein Name", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(PBTheme.Typography.body.weight(.medium))
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .frame(height: 54)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedAvatar, matching: .images) {
            Group {
                if let avatarData, let image = UIImage(data: avatarData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let avatarPath, !avatarPath.isEmpty {
                    StorageImageView(path: avatarPath)
                } else {
                    Text(initials)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(PBTheme.textPrimary)
                }
            }
            .frame(width: 76, height: 76)
            .background(PBTheme.surface, in: Circle())
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.62), lineWidth: 1) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 27, height: 27)
                    .background(PBTheme.accent, in: Circle())
                    .overlay { Circle().stroke(PBTheme.midnightRaised, lineWidth: 2) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Persönliches Foto auswählen")
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func save() async {
        guard let uid = authManager.firebaseUser?.uid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var savedPath = avatarPath
            if let avatarData {
                savedPath = try await ImageUploadService.uploadPersonalAvatar(avatarData, uid: uid)
            }
            try await authManager.updatePersonalProfile(displayName: displayName, avatarPath: savedPath)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CoupleProfileEditorView: View {
    let couple: Couple
    let profile: CoupleProfile?
    @ObservedObject var profileService: CoupleProfileService

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CoupleProfileDraft
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @StateObject private var citySearch = CitySearchService()
    @FocusState private var isCityFieldFocused: Bool

    init(couple: Couple, profile: CoupleProfile?, profileService: CoupleProfileService) {
        self.couple = couple
        self.profile = profile
        self.profileService = profileService
        let suggestedName = couple.members.map(\.displayName).joined(separator: " & ")
        _draft = State(initialValue: profile.map(CoupleProfileDraft.init) ?? CoupleProfileDraft(suggestedName: suggestedName))
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text(profile == nil ? "Euer Auftritt" : "Profil bearbeiten")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("So entdeckt euch die Community – wenn ihr das möchtet.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text("Euer Profilbild")
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        HStack(spacing: PBTheme.Spacing.md) {
                            avatarPicker
                            VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                                Text("Ein Bild, das nach euch aussieht")
                                    .font(PBTheme.Typography.body.weight(.semibold))
                                    .foregroundStyle(PBTheme.textOnDark)
                                Text("Optional – Ortsmetadaten werden vor dem Speichern entfernt.")
                                    .font(PBTheme.Typography.caption)
                                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(PBTheme.Spacing.md)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text("So erscheint ihr")
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        VStack(spacing: PBTheme.Spacing.sm) {
                            profileField(
                                label: "Name eures Paarprofils",
                                hint: "So erscheint ihr im Feed und auf euren Momenten"
                            ) {
                                TextField("z. B. Alex & Sam", text: $draft.displayName)
                                    .profileEditorField()
                            }
                            profileField(
                                label: "Euer Handle",
                                hint: "Eindeutiger Name nach dem @ – nur Kleinbuchstaben und Punkte"
                            ) {
                                TextField("z. B. alex.sam", text: $draft.handle)
                                    .profileEditorField()
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            cityField
                            profileField(
                                label: "Über euch",
                                hint: "Optional – ein kurzer Satz, der zu euch passt"
                            ) {
                                TextField("Was macht eure gemeinsamen Momente aus?", text: $draft.bio, axis: .vertical)
                                    .profileEditorField()
                                    .lineLimit(2...4)
                            }
                        }
                        .padding(PBTheme.Spacing.md)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                    }

                    PBPrimaryButton(
                        title: profile == nil ? "Profil erstellen" : "Änderungen speichern",
                        symbol: "checkmark",
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }
                    .disabled(isSaving || draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm)
                            .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: pickedAvatar) { _, newValue in
            guard let newValue else { return }
            Task {
                avatarData = try? await newValue.loadTransferable(type: Data.self)
            }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedAvatar, matching: .images) {
            Group {
                if let avatarData, let image = UIImage(data: avatarData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let path = draft.avatarPath {
                    StorageImageView(path: path)
                } else {
                    Image(systemName: "camera.fill").foregroundStyle(PBTheme.accent)
                }
            }
            .frame(width: 88, height: 88)
            .background(.white.opacity(0.11), in: Circle())
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.20), lineWidth: 1) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 28, height: 28)
                    .background(PBTheme.accent, in: Circle())
                    .overlay { Circle().stroke(PBTheme.midnightRaised, lineWidth: 2) }
            }
        }
    }

    private func profileField<Content: View>(
        label: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.textOnDark)
            Text(hint)
                .font(PBTheme.Typography.micro)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            content()
        }
    }

    private var cityField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Eure Stadt")
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.textOnDark)
            Text("Optional – wird für lokale Entdeckungen und euren Profilort verwendet")
                .font(PBTheme.Typography.micro)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            HStack(spacing: PBTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PBTheme.accent)
                TextField("Stadt oder Ort suchen", text: $draft.city)
                    .textFieldStyle(.plain)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDark)
                    .focused($isCityFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        citySearch.clear()
                        isCityFieldFocused = false
                    }
                if citySearch.isSearching { ProgressView().tint(PBTheme.accent) }
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .frame(height: 52)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1) }

            if !citySearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(citySearch.suggestions.prefix(5)) { suggestion in
                        Button {
                            Task {
                                draft.city = await citySearch.selectedCity(for: suggestion)
                                citySearch.clear()
                                isCityFieldFocused = false
                            }
                        } label: {
                            HStack(spacing: PBTheme.Spacing.sm) {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(PBTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).font(PBTheme.Typography.body.weight(.semibold))
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(1)
                                    }
                                }
                                .foregroundStyle(PBTheme.textOnDark)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, PBTheme.Spacing.md)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if suggestion.id != citySearch.suggestions.prefix(5).last?.id { Divider().overlay(.white.opacity(0.10)) }
                    }
                }
                .background(PBTheme.midnightRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
            }
        }
        .onChange(of: draft.city) { _, city in
            if isCityFieldFocused { citySearch.update(query: city) }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let coupleId = couple.id else { return }
            if let avatarData {
                draft.avatarPath = try await ImageUploadService.uploadAvatar(avatarData, coupleId: coupleId)
                PBImageCache.remove("storage:\(draft.avatarPath ?? "")")
            }
            try await profileService.save(draft: draft, coupleId: coupleId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func profileEditorField() -> some View {
        self
            .font(PBTheme.Typography.body)
            .foregroundStyle(PBTheme.textOnDark)
            .padding(.horizontal, PBTheme.Spacing.md)
            .frame(minHeight: 52)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1) }
    }
}
