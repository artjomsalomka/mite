import SwiftUI

struct PersonDirectoryView: View {
    let viewerUid: String
    @StateObject private var store = PersonDirectoryStore()
    @StateObject private var followService = PersonFollowService()
    @State private var query = ""
    @State private var showsFollowing = false

    var body: some View {
        PBScreenContainer {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(query.isEmpty ? "Menschen entdecken" : "Treffer")
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Persönliche Profile · Paare sind besonders markiert")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(.horizontal, PBTheme.Spacing.md)

                HStack(spacing: 8) {
                    PBFilterChip(title: "Entdecken", symbol: "sparkles", isSelected: !showsFollowing) {
                        showsFollowing = false
                    }
                    PBFilterChip(title: "Folge ich", symbol: "person.2", isSelected: showsFollowing) {
                        showsFollowing = true
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)

                if showsFollowing {
                    followingContent
                } else if store.isLoading && store.profiles.isEmpty {
                    ProgressView("Profile laden …")
                        .tint(PBTheme.textOnDark)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage {
                    PBEmptyState(symbol: "wifi.exclamationmark", title: "Suche nicht erreichbar", message: error,
                                 actionTitle: "Erneut versuchen") {
                        store.search(query, excluding: viewerUid, immediate: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.profiles.isEmpty {
                    PBEmptyState(symbol: query.isEmpty ? "person.2" : "magnifyingglass",
                                 title: query.isEmpty ? "Noch keine Profile" : "Keine passenden Profile",
                                 message: query.isEmpty ? "Öffentliche Profile erscheinen hier." : "Suche nach Name oder @Handle.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.profiles.filter { !followService.blockedUIDs.contains($0.uid) }) { profile in
                                NavigationLink { PublicPersonProfileView(uid: profile.uid, viewerUid: viewerUid) } label: {
                                    PersonDirectoryRow(profile: profile)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, PBTheme.Spacing.md)
                        .padding(.bottom, PBTheme.Spacing.xxl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.top, PBTheme.Spacing.sm)
        }
        .navigationTitle("Suchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $query, prompt: "Name oder @Handle")
        .onChange(of: query) { _, text in
            if !showsFollowing { store.search(text, excluding: viewerUid) }
        }
        .task {
            store.search("", excluding: viewerUid, immediate: true)
            await followService.refresh()
        }
    }

    @ViewBuilder
    private var followingContent: some View {
        let people = followService.followingPeople.filter { person in
            query.isEmpty || person.displayName.localizedCaseInsensitiveContains(query) || person.handle.localizedCaseInsensitiveContains(query)
        }
        if followService.isRefreshing && people.isEmpty {
            ProgressView("Profile laden …").tint(PBTheme.textOnDark).foregroundStyle(PBTheme.textOnDarkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if people.isEmpty {
            PBEmptyState(symbol: "person.2", title: query.isEmpty ? "Du folgst noch niemandem" : "Keine passenden Profile",
                         message: query.isEmpty ? "Entdecke Menschen und stelle dir deinen eigenen Inspirationskreis zusammen." : "Versuche einen anderen Namen oder @Handle.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(people) { person in
                        NavigationLink { PublicPersonProfileView(uid: person.uid, viewerUid: viewerUid) } label: {
                            FollowedPersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct PersonDirectoryRow: View {
    let profile: PersonProfile

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                    if profile.linkedCoupleId != nil {
                        Image(systemName: "heart.link")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PBTheme.accent)
                            .accessibilityLabel("Als Paar verbunden")
                    }
                }
                Text("@\(profile.handle)")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                if !profile.city.isEmpty {
                    Text(profile.city)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .padding(.vertical, PBTheme.Spacing.sm)
    }

    private var avatar: some View {
        PersonDirectoryAvatar(displayName: profile.displayName, avatarPath: profile.avatarPath)
    }

    private var initials: String { String(profile.displayName.prefix(1)).uppercased() }
}

private struct FollowedPersonRow: View {
    let person: FollowedPerson
    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            PersonDirectoryAvatar(displayName: person.displayName, avatarPath: person.avatarPath)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.displayName).font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                    if person.linkedCoupleId != nil { Image(systemName: "heart.link").font(.system(size: 12, weight: .medium)).foregroundStyle(PBTheme.accent) }
                }
                Text("@\(person.handle)").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                if !person.city.isEmpty { Text(person.city).font(.system(size: 11, weight: .light)).foregroundStyle(PBTheme.textOnDarkSecondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .padding(.vertical, PBTheme.Spacing.sm)
    }
}

private struct PersonDirectoryAvatar: View {
    let displayName: String
    let avatarPath: String?

    var body: some View {
        Group {
            if let avatarPath { StorageImageView(path: avatarPath) }
            else { Text(String(displayName.prefix(1)).uppercased()).font(.system(size: 18, weight: .medium)).foregroundStyle(PBTheme.textOnDark) }
        }
        .frame(width: 52, height: 52)
        .background(.white.opacity(0.10), in: Circle())
        .clipShape(Circle())
    }
}
