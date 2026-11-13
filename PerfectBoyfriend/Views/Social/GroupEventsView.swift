import PhotosUI
import SwiftUI

/// Invitation-first group plans. A completed plan may later be shared as a co-authored Moment,
/// but no one is added to a social post merely because they were invited to the plan.
struct GroupEventsView: View {
    let uid: String
    let defaultCity: String
    @StateObject private var service = GroupEventService()
    @State private var isComposerPresented = false

    var body: some View {
        PBScreenContainer {
            Group {
                if service.isLoading {
                    ProgressView().tint(PBTheme.textOnDark)
                } else if let error = service.errorMessage, service.events.isEmpty {
                    PBEmptyState(symbol: "wifi.exclamationmark", title: "Pläne nicht erreichbar", message: error,
                                 actionTitle: "Erneut versuchen") { service.startListening(uid: uid) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Mit Freund:innen")
                                    .font(PBTheme.Typography.display).foregroundStyle(PBTheme.textOnDark)
                                Text("Plant gemeinsam – ein Moment kann später daraus entstehen.")
                                    .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                            }

                            if service.events.isEmpty {
                                PBEmptyState(symbol: "person.3", title: "Noch kein gemeinsamer Plan",
                                             message: "Lade Menschen ein und entscheide später gemeinsam, ob daraus ein Moment für euer Profil wird.",
                                             actionTitle: "Plan erstellen") { isComposerPresented = true }
                                    .frame(maxWidth: .infinity, minHeight: 330)
                            } else {
                                ForEach(service.events) { event in
                                    NavigationLink {
                                        GroupEventDetailView(event: event, uid: uid, service: service)
                                    } label: {
                                        GroupEventHeroCard(event: event, viewerUID: uid)
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
            }
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isComposerPresented = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(PBTheme.textOnDark)
                .accessibilityLabel("Plan mit Freund:innen erstellen")
            }
        }
        .task { service.startListening(uid: uid) }
        .sheet(isPresented: $isComposerPresented) {
            GroupEventComposerView(uid: uid, defaultCity: defaultCity, service: service)
        }
    }
}

/// Image-first hierarchy matches the next-date card on the home screen, with group attendance.
private struct GroupEventHeroCard: View {
    let event: GroupEvent
    let viewerUID: String

    private var attendance: GroupEventAttendance { event.attendance(for: viewerUID) ?? .invited }
    private var goingCount: Int { event.participants.filter { $0.status == .going }.count }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GroupEventCover(event: event)
            LinearGradient(
                colors: [Color.black.opacity(0.04), Color.black.opacity(0.30), Color.black.opacity(0.88)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Mit Freund:innen", systemImage: "person.3.fill")
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(PBTheme.midnight.opacity(0.88), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 1) }
                    Spacer(minLength: 0)
                    GroupEventStatusPill(attendance: attendance, isCancelled: event.status == .cancelled)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                    Text(event.title)
                        .font(PBTheme.Typography.title).foregroundStyle(PBTheme.textOnDark).lineLimit(2)

                    HStack(spacing: PBTheme.Spacing.sm) {
                        GroupEventAvatarStack(participants: event.participants, avatarSize: 29)
                        Text("\(goingCount) dabei")
                        Circle().fill(PBTheme.textOnDarkSecondary.opacity(0.72)).frame(width: 3, height: 3)
                        Text(event.scheduledAt.dateValue(), format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                            .lineLimit(1)
                    }
                    .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)

                    if !event.city.isEmpty {
                        Label(event.city, systemImage: "mappin.and.ellipse")
                            .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(1)
                    }
                }
            }
            .padding(PBTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity).frame(height: 258)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: PBTheme.Shadow.card, radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gruppenplan: \(event.title)")
        .accessibilityHint("Öffnet die Plan-Details")
    }
}

struct GroupEventDetailView: View {
    let event: GroupEvent
    let uid: String
    @ObservedObject var service: GroupEventService
    @State private var isUpdating = false
    @State private var errorMessage: String?

    private var currentEvent: GroupEvent {
        guard let id = event.id else { return event }
        return service.events.first(where: { $0.id == id }) ?? event
    }
    private var attendance: GroupEventAttendance { currentEvent.attendance(for: uid) ?? .invited }
    private var goingParticipants: [GroupEventParticipant] { currentEvent.participants.filter { $0.status == .going } }

    var body: some View {
        GroupEventPlanRoomView(event: currentEvent, uid: uid, service: service)
            .toolbar(.visible, for: .navigationBar)
    }

    private func detailSurface<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text(title).font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) { content() }
                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private func participantRow(_ person: GroupEventParticipant) -> some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            GroupEventAvatar(person: person, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                Text("@\(person.handle)").font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
            Text(person.status.title).font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    private func responseButton(_ title: String, attendance: GroupEventAttendance) -> some View {
        Button(title) { Task { await respond(attendance) } }
            .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.midnight)
            .frame(maxWidth: .infinity, minHeight: 42).background(PBTheme.surface, in: Capsule())
            .buttonStyle(.plain).disabled(isUpdating)
    }

    private func respond(_ status: GroupEventAttendance) async {
        isUpdating = true; errorMessage = nil; defer { isUpdating = false }
        do { try await service.respond(to: currentEvent, status: status) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cancel() async {
        isUpdating = true; errorMessage = nil; defer { isUpdating = false }
        do { try await service.cancel(currentEvent) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// The plan room keeps the actual itinerary above the conversation. It is intentionally not a
/// general messenger: every proposal is linked to this specific shared plan.
private enum GroupEventRoomTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case plan = "Plan"
    case availability = "Zeit"
    case expenses = "Kasse"

    var id: String { rawValue }
}

private struct GroupEventPlanRoomView: View {
    let event: GroupEvent
    let uid: String
    @ObservedObject var service: GroupEventService

    @StateObject private var chatService = GroupEventChatService()
    @State private var draft = ""
    @State private var isTimeProposalPresented = false
    @State private var selectedStep: GroupEventPlanStep?
    @State private var isResponding = false
    @State private var selectedCoverPickerItem: PhotosPickerItem?
    @State private var isUpdatingCover = false
    @State private var coverError: String?
    @State private var isInvitePickerPresented = false
    @State private var pendingInvitees: [PersonProfile] = []
    @State private var isLeaving = false
    @State private var isLeaveConfirmationPresented = false
    @State private var membershipError: String?
    @State private var selectedRoomTab: GroupEventRoomTab = .chat
    @FocusState private var isComposerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var eventID: String { event.id ?? "" }
    private var isCreator: Bool { event.creatorUid == uid }
    private var attendance: GroupEventAttendance { event.attendance(for: uid) ?? .invited }
    private var steps: [GroupEventPlanStep] {
        if let savedSteps = event.planSteps, !savedSteps.isEmpty { return savedSteps }
        let extracted = event.note
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("•") }
            .map { $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces) }
        let titles = extracted.isEmpty ? [event.title] : Array(extracted.prefix(3))
        return titles.enumerated().map { GroupEventPlanStep(id: "legacy-\($0.offset)", title: $0.element) }
    }

    var body: some View {
        PBScreenContainer {
            VStack(spacing: 0) {
                header
                roomTabs
                if event.status == .cancelled {
                    cancelledNotice
                } else if attendance == .invited {
                    invitationPrompt
                }
                Group {
                    switch selectedRoomTab {
                    case .chat:
                        chatTimeline
                        composer
                    case .plan:
                        planContent
                    case .availability:
                        GroupEventAvailabilityView(event: event, uid: uid) { date in
                            let success = await chatService.proposeTime(
                                eventId: eventID,
                                scheduledAt: date,
                                note: "Vom Mite Zeitfinder vorgeschlagen"
                            )
                            if success { selectedRoomTab = .chat }
                            return success
                        }
                    case .expenses:
                        GroupEventExpenseView(event: event, uid: uid)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if isCreator {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedCoverPickerItem, matching: .images) {
                        Image(systemName: isUpdatingCover ? "arrow.triangle.2.circlepath" : "photo.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PBTheme.textOnDark)
                            .frame(width: 34, height: 34)
                    }
                    .disabled(isUpdatingCover)
                    .accessibilityLabel("Titelbild ändern")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isCreator {
                        Button {
                            pendingInvitees = []
                            isInvitePickerPresented = true
                        } label: {
                            Label("Personen einladen", systemImage: "person.badge.plus")
                        }
                    }
                    Button(role: .destructive) {
                        isLeaveConfirmationPresented = true
                    } label: {
                        Label("Plan verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                        .frame(width: 34, height: 34)
                }
                .disabled(isLeaving)
                .accessibilityLabel("Planoptionen")
            }
        }
        .task(id: eventID) {
            guard !eventID.isEmpty else { return }
            chatService.startListening(eventId: eventID)
            await service.markRead(eventId: eventID)
        }
        .onChange(of: chatService.messages.last?.id) { _, _ in
            guard !eventID.isEmpty else { return }
            Task { await service.markRead(eventId: eventID) }
        }
        .onDisappear { chatService.stopListening() }
        .onChange(of: selectedCoverPickerItem) { _, item in
            guard let item else { return }
            Task { await updateCover(using: item) }
        }
        .sheet(isPresented: $isTimeProposalPresented) {
            GroupEventTimeProposalSheet(event: event) { date, note in
                guard !eventID.isEmpty else { return false }
                return await chatService.proposeTime(eventId: eventID, scheduledAt: date, note: note)
            }
            .presentationDetents([.medium])
            .presentationBackground(PBTheme.midnightRaised)
        }
        .sheet(item: $selectedStep) { step in
            GroupEventStepProposalSheet(step: step) { title, note in
                guard !eventID.isEmpty else { return false }
                return await chatService.proposeStep(eventId: eventID, stepID: step.id, title: title, note: note)
            }
            .presentationDetents([.medium])
            .presentationBackground(PBTheme.midnightRaised)
        }
        .sheet(isPresented: $isInvitePickerPresented, onDismiss: inviteSelectedPeople) {
            CollaboratorPickerView(
                excluding: uid,
                selected: $pendingInvitees,
                title: "Zum Plan einladen",
                selectionLimit: max(0, 9 - event.participants.count),
                excludingUIDs: Set(event.participantUids)
            )
        }
        .confirmationDialog("Plan verlassen?", isPresented: $isLeaveConfirmationPresented, titleVisibility: .visible) {
            Button("Plan verlassen", role: .destructive) {
                Task { await leavePlan() }
            }
        } message: {
            Text(isCreator ? "Die Organisation wird automatisch an eine andere teilnehmende Person übergeben. Ist niemand mehr übrig, wird der Plan abgesagt." : "Der Plan verschwindet aus deinem Kalender und Nachrichtenbereich.")
        }
        .alert("Planraum", isPresented: Binding(get: { chatService.errorMessage != nil }, set: { if !$0 { chatService.errorMessage = nil } })) {
            Button("OK", role: .cancel) { chatService.errorMessage = nil }
        } message: { Text(chatService.errorMessage ?? "") }
        .alert("Titelbild konnte nicht aktualisiert werden", isPresented: Binding(get: { coverError != nil }, set: { if !$0 { coverError = nil } })) {
            Button("OK", role: .cancel) { coverError = nil }
        } message: { Text(coverError ?? "") }
        .alert("Plan konnte nicht aktualisiert werden", isPresented: Binding(get: { membershipError != nil }, set: { if !$0 { membershipError = nil } })) {
            Button("OK", role: .cancel) { membershipError = nil }
        } message: { Text(membershipError ?? "") }
    }

    private var header: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(1)
                Text("\(event.scheduledAt.dateValue().miteWeekdayText) · \(event.city.isEmpty ? event.scheduledAt.dateValue().miteAbbreviatedDateTimeText : event.city)")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            GroupEventAvatarStack(participants: event.participants, avatarSize: 31)
        }
        .padding(.horizontal, PBTheme.Spacing.md)
        .padding(.vertical, PBTheme.Spacing.sm)
    }

    private var roomTabs: some View {
        HStack(spacing: 0) {
            ForEach(GroupEventRoomTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selectedRoomTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(selectedRoomTab == tab ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 43)
                        .background(
                            selectedRoomTab == tab ? PBTheme.controlSelected : .clear,
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRoomTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 21).stroke(PBTheme.controlBorder, lineWidth: 1) }
        .padding(.horizontal, PBTheme.Spacing.md)
        .padding(.bottom, PBTheme.Spacing.sm)
    }

    private var planContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                ZStack(alignment: .bottomLeading) {
                    GroupEventCover(event: event)
                        .frame(maxWidth: .infinity).frame(height: 190)
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(PBTheme.Typography.title).foregroundStyle(PBTheme.textOnDark)
                        Text(event.scheduledAt.dateValue(), format: .dateTime.weekday(.wide).day().month().hour().minute())
                            .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    }
                    .padding(PBTheme.Spacing.md)
                }
                .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.hero).stroke(PBTheme.controlBorder, lineWidth: 1) }

                planStrip

                if !event.note.isEmpty {
                    Text(event.note)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PBTheme.Spacing.xs)
                }
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.bottom, PBTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var planStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                Button { if !step.id.hasPrefix("legacy-") { selectedStep = step } } label: {
                VStack(spacing: 7) {
                    GroupEventCover(event: event)
                    .frame(width: index == 1 && steps.count >= 3 ? 58 : 48, height: index == 1 && steps.count >= 3 ? 58 : 48)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
                    Text(stepTime(index: index)).font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                    Text(step.title).font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                if index < steps.count - 1 {
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 1).frame(width: 18).offset(y: -18)
                }
            }
            Button { isTimeProposalPresented = true } label: {
                Image(systemName: "pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(PBTheme.accent)
                    .frame(width: 39, height: 39).background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zeit vorschlagen")
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var chatTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: PBTheme.Spacing.md) {
                    if chatService.messages.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 26, weight: .light))
                            Text("Hier stimmt ihr euren gemeinsamen Plan ab.")
                                .font(PBTheme.Typography.caption)
                        }
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 130)
                    }
                    let messages = chatService.messages
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        GroupEventMessageRow(
                            message: message,
                            isOwn: message.senderUid == uid,
                            // A name appears once per run of messages from the same person.
                            showsSenderName: index == 0 || messages[index - 1].senderUid != message.senderUid,
                            isCreator: isCreator,
                            acceptTime: {
                                guard let messageID = message.id else { return }
                                Task { _ = await chatService.acceptTimeProposal(eventId: eventID, messageId: messageID) }
                            },
                            acceptStep: {
                                guard let messageID = message.id else { return }
                                Task { _ = await chatService.acceptStepProposal(eventId: eventID, messageId: messageID) }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.vertical, PBTheme.Spacing.sm)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chatService.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: PBTheme.Spacing.sm) {
            Button { isTimeProposalPresented = true } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .regular)).foregroundStyle(PBTheme.textOnDark)
                    .frame(width: 44, height: 44).background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            TextField("Etwas an die Gruppe schreiben …", text: $draft, axis: .vertical)
                .lineLimit(1...4).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                .padding(.horizontal, PBTheme.Spacing.md).padding(.vertical, 11)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                .focused($isComposerFocused)
            Button {
                Task {
                    let sentDraft = draft
                    guard await chatService.send(eventId: eventID, body: sentDraft) else { return }
                    // A slow response must not erase text edited while the message was sent.
                    if draft == sentDraft { draft = "" }
                    isComposerFocused = true
                }
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(PBTheme.midnight)
                    .frame(width: 44, height: 44).background(PBTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isSending || event.status == .cancelled)
        }
        .padding(.horizontal, PBTheme.Spacing.md)
        .padding(.vertical, 10)
        .background(PBTheme.midnight.opacity(0.96))
    }

    private var invitationPrompt: some View {
        HStack(spacing: 8) {
            Text("Bist du dabei?").font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
            Spacer()
            ForEach([GroupEventAttendance.going, .maybe, .declined], id: \.rawValue) { choice in
                Button(choice.title) { Task { await respond(choice) } }
                    .font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(choice == .going ? PBTheme.midnight : PBTheme.textOnDark)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(choice == .going ? PBTheme.surface : .white.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain).disabled(isResponding)
            }
        }
        .padding(.horizontal, PBTheme.Spacing.md).padding(.vertical, 8)
    }

    private var cancelledNotice: some View {
        Text("Dieser Plan wurde abgesagt.")
            .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(PBTheme.destructive.opacity(0.28))
    }

    private func stepTime(index: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: index * 75, to: event.scheduledAt.dateValue()) ?? event.scheduledAt.dateValue()
        return date.miteTimeText
    }
    private func routeSymbol(index: Int) -> String { ["figure.walk", "fork.knife", "moon.stars"][min(index, 2)] }
    private func respond(_ status: GroupEventAttendance) async {
        isResponding = true; defer { isResponding = false }
        do {
            try await service.respond(to: event, status: status)
        } catch {
            // An invitation response controls access to the whole private plan room. Never
            // swallow a failed response: the person must know that their state is unchanged.
            membershipError = error.localizedDescription
        }
    }

    private func updateCover(using item: PhotosPickerItem) async {
        guard !eventID.isEmpty, let data = try? await item.loadTransferable(type: Data.self) else {
            selectedCoverPickerItem = nil
            return
        }
        isUpdatingCover = true
        defer { isUpdatingCover = false; selectedCoverPickerItem = nil }
        do {
            let path = try await ImageUploadService.uploadGroupEventCover(data, eventId: eventID)
            try await service.updateCover(eventId: eventID, coverImagePath: path)
        } catch {
            coverError = error.localizedDescription
        }
    }

    private func inviteSelectedPeople() {
        let existing = Set(event.participantUids)
        let newProfiles = pendingInvitees.filter { !existing.contains($0.uid) }
        guard !newProfiles.isEmpty, !eventID.isEmpty else { return }
        Task {
            do {
                try await service.invite(eventId: eventID, profiles: newProfiles)
                pendingInvitees = []
            } catch {
                membershipError = error.localizedDescription
            }
        }
    }

    private func leavePlan() async {
        guard !eventID.isEmpty else { return }
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await service.leave(eventId: eventID)
            dismiss()
        } catch {
            membershipError = error.localizedDescription
        }
    }
}

private struct GroupEventMessageRow: View {
    let message: GroupEventChatMessage
    let isOwn: Bool
    let showsSenderName: Bool
    let isCreator: Bool
    let acceptTime: () -> Void
    let acceptStep: () -> Void

    private var firstName: String {
        let name = message.sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.components(separatedBy: " ").first.flatMap { $0.isEmpty ? nil : $0 } ?? "Mitglied"
    }

    /// Who proposed something reads as plain text in the card header ("von Anna"), not as an
    /// avatar tile next to it.
    private var proposerLabel: String { isOwn ? "von dir" : "von \(firstName)" }

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if showsSenderName && !isOwn {
                Text(firstName)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .padding(.horizontal, 4)
            }
            if message.kind == .timeProposal, let date = message.proposedScheduledAt {
                timeProposalCard(date: date.dateValue())
            } else if message.kind == .stepProposal, let title = message.proposedStepTitle {
                stepProposalCard(title: title)
            } else {
                Text(message.body).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(isOwn ? PBTheme.accent.opacity(0.74) : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            Text(message.createdAt.dateValue(), format: .dateTime.hour().minute())
                .font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: 310, alignment: isOwn ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    private func timeProposalCard(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Zeitvorschlag \(proposerLabel)", systemImage: "clock.arrow.circlepath")
                .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.accent)
            Text(date.miteAbbreviatedDateTimeText)
                .font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
            if !message.body.isEmpty { Text(message.body).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary) }
            if message.proposalStatus == .accepted {
                Label("In den Plan übernommen", systemImage: "checkmark.circle.fill")
                    .font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(PBTheme.success)
            } else if isCreator {
                Button("Übernehmen", action: acceptTime)
                    .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, minHeight: 38).background(PBTheme.surface, in: Capsule())
                    .buttonStyle(.plain)
            } else {
                Text("Der:die Organisator:in kann den Vorschlag übernehmen.")
                    .font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .padding(13)
        .frame(maxWidth: 290, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(PBTheme.accent.opacity(0.42), lineWidth: 1) }
    }

    private func stepProposalCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Änderung \(proposerLabel)", systemImage: "arrow.triangle.2.circlepath")
                .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.accent)
            Text(title).font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
            if !message.body.isEmpty { Text(message.body).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary) }
            if message.proposalStatus == .accepted {
                Label("In den Plan übernommen", systemImage: "checkmark.circle.fill").font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(PBTheme.success)
            } else if isCreator {
                Button("Übernehmen", action: acceptStep)
                    .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, minHeight: 38).background(PBTheme.surface, in: Capsule()).buttonStyle(.plain)
            } else {
                Text("Der:die Organisator:in kann den Vorschlag übernehmen.").font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .padding(13).frame(maxWidth: 290, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(PBTheme.accent.opacity(0.42), lineWidth: 1) }
    }
}

private struct GroupEventTimeProposalSheet: View {
    let event: GroupEvent
    let submit: (Date, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var note = ""
    @State private var isSubmitting = false

    init(event: GroupEvent, submit: @escaping (Date, String) async -> Bool) {
        self.event = event; self.submit = submit
        _date = State(initialValue: event.scheduledAt.dateValue())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
            Text("Zeit vorschlagen").font(.system(size: 27, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Text("Die Gruppe sieht deinen Vorschlag im Planraum. Organisierende übernehmen ihn, wenn er passt.")
                .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            DatePicker("Neuer Zeitpunkt", selection: $date, in: Date().addingTimeInterval(5 * 60)..., displayedComponents: [.date, .hourAndMinute])
                .tint(PBTheme.accent).foregroundStyle(PBTheme.textOnDark)
            TextField("Kurze Begründung (optional)", text: $note, axis: .vertical)
                .lineLimit(2...3).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                .padding(PBTheme.Spacing.md).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            Button {
                Task { if await submit(date, note) { dismiss() } }
            } label: {
                Text(isSubmitting ? "Wird gesendet …" : "Vorschlag in den Chat senden")
                    .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, minHeight: 48).background(PBTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain).disabled(isSubmitting)
        }
        .padding(PBTheme.Spacing.lg)
    }
}

private struct GroupEventStepProposalSheet: View {
    let step: GroupEventPlanStep
    let submit: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note = ""
    @State private var isSubmitting = false

    init(step: GroupEventPlanStep, submit: @escaping (String, String) async -> Bool) {
        self.step = step; self.submit = submit
        _title = State(initialValue: step.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
            Text("Baustein vorschlagen").font(.system(size: 27, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Text("Ändert „\(step.title)“ als Vorschlag für die Gruppe. Die organisierende Person kann ihn übernehmen.")
                .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            TextField("Neue Aktivität oder Ort", text: $title)
                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                .padding(PBTheme.Spacing.md).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            TextField("Warum passt das besser? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...3).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                .padding(PBTheme.Spacing.md).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            Button {
                Task {
                    isSubmitting = true; defer { isSubmitting = false }
                    if await submit(title, note) { dismiss() }
                }
            } label: {
                Text(isSubmitting ? "Wird gesendet …" : "Vorschlag in den Chat senden")
                    .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, minHeight: 48).background(PBTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(PBTheme.Spacing.lg)
    }
}

struct GroupEventCover: View {
    let event: GroupEvent

    var body: some View {
        Group {
            if let path = event.coverImagePath, !path.isEmpty {
                StorageImageView(path: path)
            } else if let image = event.coverLicensedImage {
                LicensedImageView(image: image)
            } else {
                // Events created before route covers existed should still feel like real plans,
                // never like a generic system placeholder. This remains clearly a contextual
                // activity image until the organiser chooses a dedicated title photo.
                LicensedImageView(image: DateVisualFallbackLibrary.image(for: fallbackCategory))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }

    private var fallbackCategory: StationCategory {
        let text = "\(event.title) \(event.note)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if text.contains("café") || text.contains("cafe") || text.contains("kaffee") || text.contains("kuchen") { return .cafe }
        if text.contains("pizza") || text.contains("tapas") || text.contains("essen") || text.contains("restaurant") { return .restaurant }
        if text.contains("kino") || text.contains("museum") || text.contains("schloss") || text.contains("theater") { return .sight }
        if text.contains("spazier") || text.contains("picknick") || text.contains("lahn") || text.contains("flohmarkt") { return .nature }
        return .activity
    }
}

private struct GroupEventStatusPill: View {
    let attendance: GroupEventAttendance
    let isCancelled: Bool

    var body: some View {
        Text(isCancelled ? "Abgesagt" : attendance.title)
            .font(PBTheme.Typography.micro).foregroundStyle(isCancelled ? PBTheme.textOnDark : PBTheme.textPrimary)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(isCancelled ? PBTheme.destructive.opacity(0.84) : PBTheme.surface.opacity(0.96), in: Capsule())
    }
}

struct GroupEventAvatarStack: View {
    let participants: [GroupEventParticipant]
    let avatarSize: CGFloat
    var maximumVisible: Int = 5

    var body: some View {
        HStack(spacing: -7) {
            ForEach(participants.prefix(maximumVisible)) { person in
                GroupEventAvatar(person: person, size: avatarSize)
                    .overlay { Circle().stroke(PBTheme.midnight, lineWidth: 2) }
            }
            if participants.count > maximumVisible {
                Text("+\(participants.count - maximumVisible)").font(.system(size: 10, weight: .bold)).foregroundStyle(PBTheme.midnight)
                    .frame(width: avatarSize, height: avatarSize).background(PBTheme.surface, in: Circle())
            }
        }
    }
}

private struct GroupEventAvatar: View {
    let person: GroupEventParticipant
    let size: CGFloat

    var body: some View {
        Group {
            if let path = person.avatarPath, !path.isEmpty {
                StorageImageView(path: path)
            } else {
                Text(String(person.displayName.prefix(1)).uppercased())
                    .font(.system(size: max(11, size * 0.36), weight: .bold)).foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(PBTheme.surface)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

struct GroupEventComposerView: View {
    let uid: String
    let defaultCity: String
    @ObservedObject var service: GroupEventService
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var city: String
    @State private var note = ""
    @State private var scheduledAt = Date().addingTimeInterval(24 * 60 * 60)
    @State private var invitees: [PersonProfile] = []
    @State private var isPickerPresented = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(uid: String, defaultCity: String, service: GroupEventService) {
        self.uid = uid; self.defaultCity = defaultCity; self.service = service
        _city = State(initialValue: defaultCity)
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Gemeinsamen Plan starten").font(PBTheme.Typography.display).foregroundStyle(PBTheme.textOnDark)
                            Text("Alle Eingeladenen entscheiden selbst, ob sie dabei sind.")
                                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        editorCard(title: "Worum geht's?") {
                            TextField("z. B. Spieleabend im Café", text: $title)
                            TextField("Stadt", text: $city)
                            TextField("Kurze Notiz (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                        }
                        editorCard(title: "Wann?") {
                            DatePicker("Zeitpunkt", selection: $scheduledAt, in: Date().addingTimeInterval(5 * 60)..., displayedComponents: [.date, .hourAndMinute])
                                .tint(PBTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                            HStack {
                                PBSectionTitle(title: "Menschen einladen")
                                Spacer()
                                Button { isPickerPresented = true } label: {
                                    Label("Hinzufügen", systemImage: "person.badge.plus")
                                        .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.accent)
                                }.buttonStyle(.plain)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                if invitees.isEmpty {
                                    Text("Bis zu acht öffentliche Profile können eingeladen werden.")
                                        .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textSecondary)
                                } else {
                                    ForEach(invitees) { person in
                                        HStack {
                                            Text("@\(person.handle)").font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textPrimary)
                                            Spacer()
                                            Button { invitees.removeAll { $0.uid == person.uid } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PBTheme.textSecondary) }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(PBTheme.Spacing.md).background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        }
                        PBPrimaryButton(title: "Einladungen senden", symbol: "paperplane.fill", isLoading: isSaving) { Task { await save() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        if let errorMessage { Text(errorMessage).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDark) }
                    }
                    .padding(PBTheme.Spacing.md).padding(.bottom, PBTheme.Spacing.xxl)
                }.scrollIndicators(.hidden)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundStyle(PBTheme.textOnDark) } }
            .toolbarBackground(PBTheme.midnight, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $isPickerPresented) {
            CollaboratorPickerView(excluding: uid, selected: $invitees, title: "Menschen einladen", selectionLimit: 8)
        }
    }

    private func editorCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: title)
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) { content() }
                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textPrimary)
                .padding(PBTheme.Spacing.md).background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        }
    }

    private func save() async {
        isSaving = true; errorMessage = nil; defer { isSaving = false }
        do {
            try await service.create(title: title, city: city, note: note, scheduledAt: scheduledAt, invitees: invitees)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
