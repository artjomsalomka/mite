import SwiftUI

/// The couple's personal landing space. It gives the next shared plan the visual priority of a
/// social post while retaining the existing date-detail and social-post workflows.
struct CoupleHomeView: View {
    let couple: Couple
    let viewer: AppUser
    @ObservedObject var savedDateService: SavedDateService
    @ObservedObject var feedService: FeedService
    @ObservedObject var postService: PostService
    let onPlan: () -> Void
    let onShare: () -> Void
    let onDiscover: () -> Void
    let onNotifications: () -> Void
    let unreadActivityCount: Int

    private var scope: DatePlanningScope { .couple(id: couple.id ?? "") }

    private var upcomingDates: [SavedDate] {
        savedDateService.savedDates
            .filter { !$0.isInPast && $0.status == .upcoming }
            .sorted { $0.scheduledAt.dateValue() < $1.scheduledAt.dateValue() }
    }

    private var inspiration: [DiscoverablePost] {
        Array(feedService.posts.prefix(5))
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xl) {
                            header

                            if savedDateService.isLoading && savedDateService.savedDates.isEmpty {
                                NextDateLoadingCard()
                            } else if let loadErrorMessage = savedDateService.loadErrorMessage, savedDateService.savedDates.isEmpty {
                                NextDateRetryCard(message: loadErrorMessage, retry: savedDateService.retryLoading)
                            } else if !upcomingDates.isEmpty {
                                upcomingDateCarousel(width: max(0, proxy.size.width - (PBTheme.Spacing.md * 2)))
                            } else {
                                EmptyNextDateCard(onPlan: onPlan)
                            }

                            quickActions

                            if feedService.isLoading && inspiration.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(PBTheme.textOnDark)
                                    Spacer()
                                }
                            } else if let loadErrorMessage = feedService.loadErrorMessage, inspiration.isEmpty {
                                PBEmptyState(
                                    symbol: "wifi.exclamationmark",
                                    title: "Momente nicht erreichbar",
                                    message: loadErrorMessage,
                                    actionTitle: "Erneut versuchen",
                                    action: feedService.retryLoading
                                )
                                .frame(maxWidth: .infinity)
                            } else if !inspiration.isEmpty {
                                inspirationSection
                            }
                        }
                        // A vertical ScrollView does not constrain a child to its horizontal
                        // viewport by itself. Remote images may otherwise advertise their
                        // original (very wide) size and shift the entire screen sideways.
                        .frame(width: max(0, proxy.size.width - (PBTheme.Spacing.md * 2)), alignment: .leading)
                        .padding(.horizontal, PBTheme.Spacing.md)
                        .padding(.top, PBTheme.Spacing.md)
                        .padding(.bottom, PBTheme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: PBTheme.Spacing.sm) {
                Text("Hi, " + greetingName)
                    .font(PBTheme.Typography.greeting)
                    .foregroundStyle(PBTheme.textOnDark)
                    .tracking(-0.45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: PBTheme.Spacing.sm)
                PBNotificationButton(action: onNotifications, unreadCount: unreadActivityCount)
            }

            HStack(alignment: .center) {
                Text("Bereit für heute?")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                Spacer(minLength: 0)
                PBMemberAvatarStack(members: couple.members, avatarSize: 34)
            }
        }
    }

    private var greetingName: String {
        let trimmed = viewer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? "du"
    }

    private var quickActions: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            HomeQuickAction(
                title: "Event planen",
                subtitle: "Date oder Runde",
                symbol: "calendar.badge.plus",
                isPrimary: true,
                action: onPlan
            )
            HomeQuickAction(
                title: "Moment teilen",
                subtitle: "Foto oder Video",
                symbol: "camera.fill",
                isPrimary: false,
                action: onShare
            )
        }
    }

    private func upcomingDateCarousel(width: CGFloat) -> some View {
        let cardWidth = max(280, width - 4)
        return VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Text(upcomingDates.count == 1 ? "Euer nächstes Date" : "Eure nächsten Dates")
                    .font(PBTheme.Typography.title.weight(.regular))
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Text("\(upcomingDates.count) geplant")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: PBTheme.Spacing.md) {
                    ForEach(Array(upcomingDates.enumerated()), id: \.element.id) { index, date in
                        NavigationLink {
                            SavedDateDetailView(
                                scope: scope,
                                savedDate: date,
                                savedDateService: savedDateService,
                                postService: postService
                            )
                        } label: {
                            NextDateHero(
                                savedDate: date,
                                members: couple.members,
                                position: index,
                                totalCount: upcomingDates.count
                            )
                            .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                        .scrollTargetLayout()
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var inspirationSection: some View {
        GeometryReader { proxy in
            // Two moments stay visible on a standard iPhone width. This makes the section feel
            // like a social stream rather than a single oversized promotion card.
            let cardWidth = min(168, max(148, proxy.size.width * 0.47))

            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                PBSectionTitle(title: "Momente aus eurer Stadt", actionTitle: "Alle ansehen", action: onDiscover)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: PBTheme.Spacing.sm) {
                        ForEach(inspiration) { post in
                            NavigationLink {
                                SocialPostDetailView(postID: post.id)
                            } label: {
                                HomeInspirationTile(post: post, width: cardWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Moment öffnen: \(post.caption.isEmpty ? post.categories.first ?? "Date-Moment" : post.caption)")
                                .scrollTargetLayout()
                        }
                    }
                    .padding(.horizontal, PBTheme.Spacing.xxs)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .frame(height: 230)
    }
}

private struct NextDateHero: View {
    let savedDate: SavedDate
    let members: [CoupleMember]
    let position: Int
    let totalCount: Int

    private var firstPlace: ResolvedPlace? {
        savedDate.stations.compactMap(\.resolvedPlace).first
    }

    private var firstImage: LicensedImage? {
        savedDate.stations.compactMap(\.licensedImage).first
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let firstImage {
                    LicensedImageView(image: firstImage)
                } else {
                    LinearGradient(
                        colors: [PBTheme.midnightSoft, PBTheme.midnight, Color.black.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 298)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.28), Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(dateLabel, systemImage: "calendar")
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PBTheme.midnight.opacity(0.90), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.24), lineWidth: 1) }

                    Spacer(minLength: 0)

                    Text("Gemeinsam")
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PBTheme.midnight.opacity(0.88), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 1) }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                    Text(savedDate.title)
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textOnDark)
                        .lineLimit(2)

                    HStack(spacing: PBTheme.Spacing.sm) {
                        PBMemberAvatarStack(members: members, avatarSize: 29)

                        Text(savedDate.scheduledAt.dateValue(), format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                            .lineLimit(1)

                        if let firstPlace {
                            Circle()
                                .fill(PBTheme.textOnDarkSecondary.opacity(0.72))
                                .frame(width: 3, height: 3)
                            Text(firstPlace.name)
                                .lineLimit(1)
                        }
                    }
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            }
            .padding(PBTheme.Spacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.hero)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: PBTheme.Shadow.card, radius: 16, y: 8)
        .frame(maxWidth: .infinity)
        .frame(height: 298)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nächstes Date: \(savedDate.title)")
        .accessibilityHint("Öffnet die Date-Details")
    }

    private var dateLabel: String {
        let date = savedDate.scheduledAt.dateValue()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Locale(identifier: "de_DE")))
    }
}

private struct HomeQuickAction: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 38, height: 38)
                    .background(isPrimary ? PBTheme.midnight.opacity(0.30) : PBTheme.midnightSoft.opacity(0.78), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PBTheme.Typography.caption.weight(.bold))
                    Text(subtitle)
                        .font(PBTheme.Typography.micro)
                        .opacity(0.72)
                }
                .foregroundStyle(PBTheme.textOnDark)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isPrimary ? PBTheme.controlSelected : PBTheme.controlSurface,
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(isPrimary ? .white.opacity(0.20) : PBTheme.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyNextDateCard: View {
    let onPlan: () -> Void

    var body: some View {
        Button(action: onPlan) {
            HStack(spacing: PBTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                    Text("Was macht ihr als Nächstes?")
                        .font(PBTheme.Typography.headline)
                    Text("Plant in weniger als einer Minute euer nächstes gemeinsames Erlebnis.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(PBTheme.textOnDark)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .padding(PBTheme.Spacing.md)
            .background(PBTheme.midnightRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card).stroke(.white.opacity(0.15), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

private struct NextDateLoadingCard: View {
    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            ProgressView()
                .tint(PBTheme.textOnDark)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                Text("Euer nächstes Date")
                    .font(PBTheme.Typography.headline)
                Text("Wird gerade aus eurem gemeinsamen Verlauf geladen …")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(PBTheme.textOnDark)
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.midnightRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card).stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}

private struct NextDateRetryCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Label("Nächstes Date nicht erreichbar", systemImage: "wifi.exclamationmark")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            Text(message)
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            Button("Erneut versuchen", action: retry)
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(PBTheme.surface, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.midnightRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card).stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}

private struct HomeInspirationTile: View {
    let post: DiscoverablePost
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = post.coverLicensedImage {
                    LicensedImageView(image: image)
                } else if let path = post.coverImagePath {
                    StorageImageView(path: path)
                } else {
                    LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.midnightRaised], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: width, height: 182)
            .clipped()

            LinearGradient(colors: [.clear, Color.black.opacity(0.74)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                if !post.city.isEmpty {
                    Text(post.city)
                        .font(PBTheme.Typography.micro)
                }
                Text(post.caption.isEmpty ? post.categories.first ?? "Date-Moment" : post.caption)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(PBTheme.textOnDark)
            .padding(PBTheme.Spacing.sm)
        }
        .frame(width: width, height: 182)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct PBRouteAccent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 10))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 8, y: rect.minY + 20),
            control1: CGPoint(x: rect.width * 0.30, y: rect.minY - 6),
            control2: CGPoint(x: rect.width * 0.66, y: rect.maxY + 22)
        )
        return path
    }
}
