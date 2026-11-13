import SwiftUI

/// A compact vertical portrait group, with a fixed footprint independent of photo dimensions.
private struct InboxPortraitCluster: View {
    let participants: [GroupEventParticipant]

    var body: some View {
        ZStack(alignment: .top) {
            if let first = participants.first {
                InboxPortrait(person: first, size: 56)
            }
            HStack(spacing: 0) {
                ForEach(Array(participants.dropFirst().prefix(2))) { person in
                    InboxPortrait(person: person, size: 29)
                }
            }
            .offset(y: 44)
        }
        .frame(width: 58, height: 76, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(participants.map(\.displayName).joined(separator: ", "))
    }
}

private struct InboxPortrait: View {
    let person: GroupEventParticipant
    let size: CGFloat
    @StateObject private var profileService = PersonProfileService()

    private var avatarPath: String? {
        // A loaded profile is authoritative, including a deliberately removed avatar.
        if let profile = profileService.profile { return profile.avatarPath }
        return person.avatarPath
    }

    var body: some View {
        ZStack {
            PBTheme.controlSurfaceRaised
            if let path = avatarPath, !path.isEmpty {
                StorageImageView(path: path).id(path)
            } else {
                Text(String(person.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(PBTheme.textOnDark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.textOnDark.opacity(0.85), lineWidth: 0.7) }
        .task(id: person.uid) { profileService.startListening(uid: person.uid) }
    }
}

/// An invitation and the later group discussion remain one thread, so no one has to hunt
/// through a notification centre for their answer or the current plan.
@MainActor
struct ActivityInboxView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all, invitations, active
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Alle"
            case .invitations: return "Einladungen"
            case .active: return "Aktiv"
            }
        }
    }

    let uid: String
    let defaultCity: String
    @ObservedObject private var collaborationService: CollaborationInboxService
    @ObservedObject private var groupEventService: GroupEventService
    let initialEventID: String?
    @StateObject private var conversations = GroupEventConversationStore()
    @State private var selectedFilter: Filter = .all
    @State private var respondingPostID: String?
    @State private var respondingEventID: String?
    @State private var errorMessage: String?
    @State private var isComposerPresented = false
    @State private var deepLinkedEventID: String?

    private let inboxBackground = Color(red: 0.038, green: 0.077, blue: 0.125)
    private let inboxSecondary = Color(red: 0.60, green: 0.65, blue: 0.74)

    init(uid: String, defaultCity: String, collaborationService: CollaborationInboxService, groupEventService: GroupEventService, initialEventID: String? = nil) {
        self.uid = uid; self.defaultCity = defaultCity
        self.initialEventID = initialEventID
        _collaborationService = ObservedObject(wrappedValue: collaborationService)
        _groupEventService = ObservedObject(wrappedValue: groupEventService)
    }

    private var threadEvents: [GroupEvent] {
        groupEventService.events
            .filter { $0.status == .planned && $0.attendance(for: uid) != .declined }
            .filter { event in
                switch selectedFilter {
                case .all: true
                case .invitations: event.attendance(for: uid) == .invited
                case .active: [.going, .maybe].contains(event.attendance(for: uid) ?? .invited)
                }
            }
            .sorted { lastActivity(for: $0) > lastActivity(for: $1) }
    }

    private var loadingFailureMessage: String? {
        guard threadEvents.isEmpty, collaborationService.invitations.isEmpty else { return nil }
        return groupEventService.errorMessage ?? collaborationService.errorMessage
    }

    var body: some View {
        ZStack {
            inboxBackground.ignoresSafeArea()
            Group {
                if groupEventService.isLoading && collaborationService.isLoading {
                    ProgressView().tint(PBTheme.textOnDark)
                } else if let loadingFailureMessage {
                    PBEmptyState(
                        symbol: "wifi.exclamationmark",
                        title: "Nachrichten nicht erreichbar",
                        message: loadingFailureMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        groupEventService.retryLoading()
                        collaborationService.retryLoading()
                    }
                    .padding(PBTheme.Spacing.lg)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                            header
                            filterPicker
                            if threadEvents.isEmpty && (selectedFilter == .active || collaborationService.invitations.isEmpty) {
                                emptyState
                            } else {
                                eventThreads
                                if selectedFilter != .active && !collaborationService.invitations.isEmpty {
                                    collaborationInvitations
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, PBTheme.Spacing.xxl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isComposerPresented) {
            GroupEventComposerView(uid: uid, defaultCity: defaultCity, service: groupEventService)
        }
        .task { collaborationService.startListening(uid: uid); groupEventService.startListening(uid: uid) }
        .onAppear { conversations.startListening(events: groupEventService.events.filter { $0.status == .planned }) }
        .onChange(of: groupEventService.events.map { $0.id ?? "" }.joined(separator: ",")) { _, _ in
            conversations.startListening(events: groupEventService.events.filter { $0.status == .planned })
            openDeepLinkedEventIfAvailable()
        }
        .task { openDeepLinkedEventIfAvailable() }
        .navigationDestination(isPresented: Binding(
            get: { deepLinkedEventID != nil },
            set: { if !$0 { deepLinkedEventID = nil } }
        )) {
            if let event = groupEventService.events.first(where: { $0.id == deepLinkedEventID }) {
                GroupEventDetailView(event: event, uid: uid, service: groupEventService)
            } else {
                PBEmptyState(symbol: "calendar.badge.exclamationmark", title: "Plan nicht verfügbar", message: "Dieser Plan wurde möglicherweise entfernt oder du bist nicht mehr eingeladen.")
                    .padding(PBTheme.Spacing.lg)
            }
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Nachrichten")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Button { isComposerPresented = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Gemeinsamen Plan starten")
        }
        .padding(.bottom, 2)
    }

    private var filterPicker: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases) { filter in
                Button { withAnimation(.snappy(duration: 0.24)) { selectedFilter = filter } } label: {
                    Text(filter.title).font(.subheadline)
                        .foregroundStyle(selectedFilter == filter ? PBTheme.textOnDark : inboxSecondary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(selectedFilter == filter ? Color(red: 0.14, green: 0.20, blue: 0.30) : .clear, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
            }
        }
        .padding(3)
        .overlay { Capsule().stroke(inboxSecondary.opacity(0.30), lineWidth: 0.7) }
    }

    private var eventThreads: some View {
        LazyVStack(spacing: 0) {
            ForEach(threadEvents) { event in
                eventThread(event)
                if event.id != threadEvents.last?.id {
                    Rectangle().fill(inboxSecondary.opacity(0.20)).frame(height: 0.5)
                }
            }
        }
        .padding(.top, 2)
    }

    private var emptyState: some View {
        PBEmptyState(symbol: "bubble.left.and.bubble.right", title: selectedFilter == .invitations ? "Keine offenen Einladungen" : "Noch keine Nachrichten", message: "Sobald ihr gemeinsam etwas plant, findet ihr eure Abstimmung genau hier.")
            .frame(maxWidth: .infinity, minHeight: 310)
    }

    private func eventThread(_ event: GroupEvent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                GroupEventDetailView(event: event, uid: uid, service: groupEventService)
            } label: {
                HStack(alignment: .top, spacing: 16) {
                    InboxPortraitCluster(participants: event.participants)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.title)
                                .font(.system(.headline, weight: .regular))
                                .foregroundStyle(PBTheme.textOnDark)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(relativeTime(for: event))
                                .font(.caption).foregroundStyle(inboxSecondary)
                                .fixedSize()
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Text(threadPreview(for: event))
                                .font(.subheadline).foregroundStyle(inboxSecondary)
                                .lineSpacing(4).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if event.isUnread(for: uid, latestMessageAt: conversations.latestMessage(for: event)?.createdAt.dateValue()) {
                                Circle().fill(Color(red: 0.27, green: 0.55, blue: 0.96))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                    .accessibilityLabel("Ungelesen")
                            } else {
                                GroupEventCover(event: event)
                                    .frame(width: 78, height: 57)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if event.attendance(for: uid) == .invited {
                invitationCard(event)
            }
        }
        .padding(.vertical, 20)
    }

    private func invitationCard(_ event: GroupEvent) -> some View {
        HStack(spacing: 0) {
            // The image is an overlay so its original pixel dimensions cannot widen the row.
            Color.clear
                .frame(width: 126)
                .overlay {
                    NavigationLink {
                        GroupEventDetailView(event: event, uid: uid, service: groupEventService)
                    } label: {
                        GroupEventCover(event: event)
                    }
                    .buttonStyle(.plain)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    GroupEventDetailView(event: event, uid: uid, service: groupEventService)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Einladung", systemImage: "calendar")
                            .font(.caption).foregroundStyle(inboxSecondary)
                        Text(event.title).font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(PBTheme.textOnDark).lineLimit(2)
                        Text(event.scheduledAt.dateValue(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.caption).foregroundStyle(inboxSecondary)
                        Text(event.city).font(.caption).foregroundStyle(inboxSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { invitationActions(for: event) }
                    VStack(spacing: 6) { invitationActions(for: event) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13).stroke(inboxSecondary.opacity(0.22), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private func invitationActions(for event: GroupEvent) -> some View {
        inboxAction("Dabei", event: event, status: .going, filled: true)
        inboxAction("Vielleicht", event: event, status: .maybe, filled: false)
    }

    private func inboxAction(_ title: String, event: GroupEvent, status: GroupEventAttendance, filled: Bool) -> some View {
        Button(title) { Task { await respondToEvent(event, status: status) } }
            .font(.caption).foregroundStyle(PBTheme.textOnDark)
            .padding(.horizontal, 10).frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(filled ? Color(red: 0.37, green: 0.51, blue: 0.74) : .clear, in: Capsule())
            .overlay { Capsule().stroke(Color(red: 0.43, green: 0.59, blue: 0.83), lineWidth: filled ? 0 : 1) }
            .opacity(respondingEventID == event.id ? 0.5 : 1)
            .buttonStyle(.plain).disabled(respondingEventID == event.id)
    }

    private var collaborationInvitations: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Gemeinsam posten").font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
            ForEach(collaborationService.invitations) { post in
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill").foregroundStyle(PBTheme.textOnDark).frame(width: 38, height: 38).background(PBTheme.controlSurface, in: Circle())
                    Text("@\(post.creator?.handle ?? post.author.handle) möchte diesen Moment gemeinsam veröffentlichen.")
                        .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Annehmen") { Task { await respondToPost(post, accept: true) } }
                        .font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 10).frame(minHeight: 44).background(PBTheme.controlSelected, in: Capsule())
                        .buttonStyle(.plain).disabled(respondingPostID == post.id)
                }
                .padding(PBTheme.Spacing.sm).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            }
        }
    }

    private func threadPreview(for event: GroupEvent) -> String {
        if let message = conversations.latestMessage(for: event) {
            let prefix = message.senderUid == uid ? "Du" : message.sender.displayName
            switch message.kind {
            case .text: return "\(prefix): \(message.body.isEmpty ? "Nachricht" : message.body)"
            case .timeProposal: return "\(prefix): Neue Uhrzeit vorgeschlagen"
            case .stepProposal: return "\(prefix): Neuer Planbaustein vorgeschlagen"
            }
        }
        if event.attendance(for: uid) == .invited { return "Einladung · \(event.scheduledAt.dateValue().miteAbbreviatedDateTimeText)" }
        return event.creatorUid == uid ? "Du hast diesen Plan erstellt." : "Bereit, euren Plan gemeinsam abzustimmen?"
    }

    private func lastActivity(for event: GroupEvent) -> Date { conversations.latestMessage(for: event)?.createdAt.dateValue() ?? event.updatedAt.dateValue() }
    private func relativeTime(for event: GroupEvent) -> String {
        let date = lastActivity(for: event)
        if Calendar.current.isDateInToday(date) { return date.miteTimeText }
        if Calendar.current.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.day().month().locale(Locale(identifier: "de_DE")))
    }

    private func respondToPost(_ post: SocialPost, accept: Bool) async {
        respondingPostID = post.id; defer { respondingPostID = nil }
        do { try await collaborationService.respond(to: post, accept: accept) } catch { errorMessage = error.localizedDescription }
    }
    private func respondToEvent(_ event: GroupEvent, status: GroupEventAttendance) async {
        respondingEventID = event.id; defer { respondingEventID = nil }
        do { try await groupEventService.respond(to: event, status: status) } catch { errorMessage = error.localizedDescription }
    }

    private func openDeepLinkedEventIfAvailable() {
        guard let initialEventID, !initialEventID.isEmpty,
              groupEventService.events.contains(where: { $0.id == initialEventID }) else { return }
        deepLinkedEventID = initialEventID
    }
}
