import CoreLocation
import MapKit
import SwiftUI

/// Read-only view of a saved date — stations already carry their resolved places from the
/// moment the couple selected the suggestion, so no MapKit re-resolution happens here.
struct SavedDateDetailView: View {
    let scope: DatePlanningScope
    let savedDate: SavedDate
    @ObservedObject var savedDateService: SavedDateService
    @ObservedObject var postService: PostService

    @StateObject private var reminderService = DateReminderService()
    @State private var reminderDate: Date?
    @State private var reminderError: String?
    @State private var isUpdatingReminder = false
    @State private var isCalendarEditorPresented = false
    @State private var isScheduleEditorPresented = false
    @State private var calendarMessage: String?
    @State private var isCancellationConfirmationPresented = false
    @State private var isCancelling = false
    @State private var cancellationError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text(currentSavedDate.title)
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Label(
                            currentSavedDate.scheduledAt.dateValue().miteCompleteDateTimeText,
                            systemImage: "calendar"
                        )
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    if currentSavedDate.status == .cancelled {
                        cancellationStatusCard
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Euer Ablauf")
                        DateRouteTimeline(stations: currentSavedDate.stations, startingAt: currentSavedDate.scheduledAt.dateValue())
                        if currentSavedDate.status != .cancelled {
                            NavigationLink {
                                DateJourneyView(scope: scope, savedDate: currentSavedDate, savedDateService: savedDateService)
                            } label: {
                                Label("Date erleben", systemImage: "figure.walk")
                                    .font(PBTheme.Typography.body.weight(.semibold))
                                    .foregroundStyle(PBTheme.textOnDark)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(PBTheme.routeSurfaceRaised, in: Capsule())
                                    .overlay { Capsule().stroke(.white.opacity(0.20), lineWidth: 1) }
                            }.buttonStyle(.plain)
                        }
                    }

                    if currentSavedDate.isInPast, let linkedPostID {
                        NavigationLink {
                            SocialPostDetailView(postID: linkedPostID)
                        } label: {
                            Label("Geteilten Moment ansehen", systemImage: "rectangle.stack.person.crop")
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(PBTheme.routeSurfaceRaised, in: Capsule())
                                .overlay { Capsule().stroke(.white.opacity(0.20), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }

                    if scope.isFirstMeeting {
                        DetailInfoCard(
                            title: "Sicher unterwegs",
                            message: "Du entscheidest selbst, mit wem du Termin und Treffpunkt teilst. Es wird kein Live-Standort übertragen.",
                            symbol: "person.badge.shield.checkmark"
                        ) {
                            ShareLink(item: trustedPersonMessage, subject: Text("Mein Date-Plan")) {
                                Label("Plan mit Vertrauensperson teilen", systemImage: "square.and.arrow.up")
                                    .font(PBTheme.Typography.caption.weight(.semibold))
                                    .foregroundStyle(PBTheme.accent)
                            }
                        }
                    }

                    if !currentSavedDate.isInPast && currentSavedDate.status == .upcoming {
                        scheduleCard
                        reminderCard
                        calendarCard
                    }

                    if let rating = currentSavedDate.rating {
                        ratingCard(rating)
                    } else if currentSavedDate.canRate {
                        NavigationLink {
                            RateDateView(scope: scope, savedDate: currentSavedDate, savedDateService: savedDateService)
                        } label: {
                            Label("Date bewerten", systemImage: "star")
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .background(PBTheme.routeSurfaceRaised, in: Capsule())
                                .overlay { Capsule().stroke(.white.opacity(0.20), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }

                    if currentSavedDate.status == .upcoming && !currentSavedDate.isInPast {
                        Button("Date absagen", role: .destructive) {
                            isCancellationConfirmationPresented = true
                        }
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.destructive)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PBTheme.destructive.opacity(0.14), in: Capsule())
                        .disabled(isCancelling)
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
        .task(id: detailRefreshKey) {
            reminderDate = await reminderService.scheduledReminderDate(for: scope, savedDate: currentSavedDate)
        }
        .alert("Erinnerung nicht möglich", isPresented: Binding(
            get: { reminderError != nil },
            set: { if !$0 { reminderError = nil } }
        )) {
            Button("OK") { reminderError = nil }
        } message: {
            Text(reminderError ?? "")
        }
        .alert("Date absagen?", isPresented: $isCancellationConfirmationPresented) {
            Button("Absagen", role: .destructive) {
                Task { await cancelDate() }
            }
            Button("Behalten", role: .cancel) {}
        } message: {
            Text("Das Date bleibt in eurem Verlauf sichtbar, wird aber nicht mehr als bevorstehend geführt.")
        }
        .alert("Date konnte nicht abgesagt werden", isPresented: Binding(
            get: { cancellationError != nil },
            set: { if !$0 { cancellationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancellationError ?? "")
        }
        .sheet(isPresented: $isCalendarEditorPresented) {
            CalendarEventEditor(savedDate: currentSavedDate, isPresented: $isCalendarEditorPresented) { didSave in
                if didSave {
                    calendarMessage = "Zum Kalender hinzugefügt."
                }
            }
        }
        .sheet(isPresented: $isScheduleEditorPresented) {
            DateRescheduleEditor(
                scope: scope,
                savedDate: currentSavedDate,
                savedDateService: savedDateService
            ) {
                reminderService.removeReminder(for: scope, savedDate: currentSavedDate)
                reminderDate = nil
                calendarMessage = "Termin verschoben. Einen bestehenden Kalendereintrag passt du bitte dort an."
            }
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: "Termin")
            HStack(spacing: PBTheme.Spacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PBTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(PBTheme.accentMuted, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSavedDate.scheduledAt.dateValue().miteAbbreviatedDateTimeText)
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                    Text("Ändert nur Zeitpunkt und Datum, nicht euren Ablauf.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                Spacer(minLength: PBTheme.Spacing.sm)
                Button("Verschieben") {
                    isScheduleEditorPresented = true
                }
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.accent)
            }
            .midnightMomentPanel()
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: "Erinnerung")
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                if let scheduledReminderDate = reminderDate {
                    HStack {
                        Label("Geplant für", systemImage: "bell.badge")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        Spacer()
                        Text(scheduledReminderDate.miteAbbreviatedDateTimeText)
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                    }
                    Button("Erinnerung entfernen", role: .destructive) {
                        reminderService.removeReminder(for: scope, savedDate: currentSavedDate)
                        reminderDate = nil
                    }
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.destructive)
                } else {
                    Menu {
                        ForEach(DateReminderLeadTime.allCases) { leadTime in
                            Button(leadTime.label) {
                                Task { await scheduleReminder(leadTime) }
                            }
                            .disabled(leadTime.fireDate(for: currentSavedDate.scheduledAt.dateValue()) <= Date())
                        }
                    } label: {
                        HStack {
                            if isUpdatingReminder {
                                ProgressView().tint(PBTheme.accent)
                            } else {
                                Label("Erinnerung planen", systemImage: "bell.badge")
                                    .font(PBTheme.Typography.body.weight(.semibold))
                                    .foregroundStyle(PBTheme.accent)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                    }
                    .disabled(isUpdatingReminder)
                }
                Text("Die Erinnerung wird nur auf diesem Gerät gespeichert.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            .midnightMomentPanel()
        }
    }

    private var cancellationStatusCard: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PBTheme.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dieses Date wurde abgesagt")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text("Der Plan bleibt als Erinnerung im gemeinsamen Verlauf.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: "Kalender")
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                Button {
                    isCalendarEditorPresented = true
                } label: {
                    Label("Zum Kalender hinzufügen", systemImage: "calendar.badge.plus")
                        .font(PBTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(PBTheme.accent)
                }
                .buttonStyle(.plain)
                Text("Die App liest keine bestehenden Kalendereinträge.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                if let calendarMessage {
                    Text(calendarMessage)
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.success)
                }
            }
            .midnightMomentPanel()
        }
    }

    private func ratingCard(_ rating: DateRating) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: "Eure Bewertung")
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                HStack(spacing: PBTheme.Spacing.xs) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating.stars ? "star.fill" : "star")
                            .foregroundStyle(PBTheme.warning)
                    }
                }
                if let comment = rating.comment, !comment.isEmpty {
                    Text(comment)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDark)
                }
                if !rating.tags.isEmpty {
                    Text(rating.tags.joined(separator: " · "))
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.accent)
                }
            }
            .midnightMomentPanel()
        }
    }

    private var trustedPersonMessage: String {
        let dateText = currentSavedDate.scheduledAt.dateValue().miteLongDateTimeText
        let locations = currentSavedDate.stations.compactMap { station -> String? in
            guard let place = station.resolvedPlace else { return nil }
            return "• \(place.name), \(place.address)"
        }
        let locationText = locations.isEmpty
            ? "Treffpunkt bitte in der App beziehungsweise Apple Maps prüfen."
            : locations.joined(separator: "\n")
        return "Mein geplanter Date-Termin:\n\n\(currentSavedDate.title)\n\(dateText)\n\nTreffpunkte:\n\(locationText)\n\nBitte melde dich, falls du bis danach nichts von mir hörst."
    }

    private func scheduleReminder(_ leadTime: DateReminderLeadTime) async {
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }
        do {
            reminderDate = try await reminderService.schedule(
                for: scope,
                savedDate: currentSavedDate,
                leadTime: leadTime
            )
        } catch {
            reminderError = error.localizedDescription
        }
    }

    private func cancelDate() async {
        guard let savedDateId = currentSavedDate.id else {
            cancellationError = "Dieses Date konnte nicht eindeutig zugeordnet werden."
            return
        }

        isCancelling = true
        defer { isCancelling = false }
        do {
            try await savedDateService.cancel(scope: scope, savedDateId: savedDateId)
            reminderService.removeReminder(for: scope, savedDate: currentSavedDate)
            dismiss()
        } catch {
            cancellationError = error.localizedDescription
        }
    }

    /// Navigation links pass a value snapshot. Observing the shared service here ensures a
    /// reschedule, cancellation, or rating made on either partner's device updates this detail
    /// screen immediately instead of leaving controls for an outdated state visible.
    private var currentSavedDate: SavedDate {
        guard let savedDateId = savedDate.id,
              let refreshedDate = savedDateService.savedDates.first(where: { $0.id == savedDateId }) else {
            return savedDate
        }
        return refreshedDate
    }

    private var detailRefreshKey: String {
        "\(currentSavedDate.id ?? "missing")-\(currentSavedDate.scheduledAt.seconds)-\(currentSavedDate.status.rawValue)"
    }

    /// A shared Moment is linked through `sourceDateId`; finding it in the already live own-post
    /// listener avoids a second unrestricted posts query from this private history screen.
    private var linkedPostID: String? {
        guard let savedDateID = currentSavedDate.id else { return nil }
        return postService.posts.first(where: {
            $0.status == .published && $0.sourceDateId == savedDateID
        })?.id
    }
}

private struct DateRescheduleEditor: View {
    let scope: DatePlanningScope
    let savedDate: SavedDate
    let savedDateService: SavedDateService
    let onRescheduled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        scope: DatePlanningScope,
        savedDate: SavedDate,
        savedDateService: SavedDateService,
        onRescheduled: @escaping () -> Void
    ) {
        self.scope = scope
        self.savedDate = savedDate
        self.savedDateService = savedDateService
        self.onRescheduled = onRescheduled
        _selectedDate = State(initialValue: savedDate.scheduledAt.dateValue())
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Termin verschieben")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(savedDate.title)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    DatePicker(
                        "Neuer Termin",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(PBTheme.accent)
                    .padding(PBTheme.Spacing.md)
                    .background(PBTheme.routeSurfaceRaised, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))

                    Text("Eine eventuell geplante Erinnerung auf diesem Gerät wird entfernt, damit kein falscher Zeitpunkt erinnert wird.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)

                    PBPrimaryButton(title: "Termin speichern", symbol: "checkmark", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(isSaving || selectedDate <= Date())

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm)
                            .background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
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
    }

    private func save() async {
        guard let savedDateId = savedDate.id else {
            errorMessage = "Dieses Date konnte nicht eindeutig zugeordnet werden."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await savedDateService.reschedule(
                scope: scope,
                savedDateId: savedDateId,
                scheduledAt: selectedDate
            )
            onRescheduled()
            dismiss()
        } catch {
            errorMessage = "Termin konnte nicht verschoben werden: \(error.localizedDescription)"
        }
    }
}

private struct DetailInfoCard<Accessory: View>: View {
    let title: String
    let message: String
    let symbol: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack(spacing: PBTheme.Spacing.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(PBTheme.accent)
                Text(title)
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)
            }
            Text(message)
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
            accessory()
        }
        .midnightMomentPanel()
    }
}

private extension View {
    /// Date moments are content, not settings: a quiet dark glass panel retains hierarchy
    /// without breaking the Midnight canvas with the old ivory form-card treatment.
    func midnightMomentPanel() -> some View {
        padding(PBTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [PBTheme.routeSurfaceRaised, PBTheme.routeSurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}
