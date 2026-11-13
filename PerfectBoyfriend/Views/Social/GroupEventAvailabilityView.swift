import EventKit
import SwiftUI

struct GroupEventAvailabilityView: View {
    let event: GroupEvent
    let uid: String
    let onPropose: (Date) async -> Bool

    @StateObject private var service = GroupEventAvailabilityService()
    @State private var rangeStart: Date
    @State private var selectedHour = 18
    @State private var columns: [SlotColumn]
    /// The effective answers for every slot: a manual override wins, otherwise the calendar.
    @State private var localStatuses: [String: GroupEventAvailabilityStatus] = [:]
    @State private var calendarStatuses: [String: GroupEventAvailabilityStatus] = [:]
    /// Hand-set answers that intentionally differ from the calendar. Kept on this device so the
    /// automatic calendar sync can keep running without ever erasing them.
    @State private var manualOverrides: [String: GroupEventAvailabilityStatus] = [:]
    @State private var calendarSummary: String?
    @State private var isShowingDiagnostics = false
    @State private var statusByUID: [String: [String: GroupEventAvailabilityStatus]] = [:]
    @State private var suggestions: [GroupEventTimeSuggestion] = []
    @State private var isSyncingCalendar = false
    @State private var proposedSlotID: String?
    @State private var proposingSlotID: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var editRevision = 0
    @State private var savedRevision = 0
    @State private var tapFeedback = 0
    @Environment(\.scenePhase) private var scenePhase

    private let durationMinutes = 120

    init(event: GroupEvent, uid: String, onPropose: @escaping (Date) async -> Bool) {
        self.event = event
        self.uid = uid
        self.onPropose = onPropose
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let start = Calendar.current.startOfDay(for: tomorrow)
        _rangeStart = State(initialValue: start)
        _columns = State(initialValue: Self.makeColumns(rangeStart: start, durationMinutes: 120))
    }

    private var eventID: String { event.id ?? "" }
    private var participants: [GroupEventParticipant] {
        event.participants.filter { $0.status != .declined }
    }
    private var selectedColumns: [SlotColumn] {
        columns.filter { $0.hour == selectedHour }
    }
    private var ownSavedResponse: GroupEventAvailability? {
        service.responses.first { $0.uid == uid }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                heading
                rangePicker
                hourPicker
                availabilityMatrix
                calendarRow
                suggestionsSection
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.top, PBTheme.Spacing.md)
            .padding(.bottom, PBTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: tapFeedback)
        .task(id: eventID) {
            isVisible = true
            service.startListening(eventId: eventID)
            rebuildDerived()
        }
        .onChange(of: service.hasLoaded) { _, loaded in
            guard loaded else { return }
            hydrateOwnResponse()
            Task { await autoSyncCalendarIfNeeded() }
        }
        .onChange(of: service.responses) { _, _ in rebuildDerived() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await autoSyncCalendarIfNeeded() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await autoSyncCalendarIfNeeded() }
        }
        .onChange(of: localStatuses) { _, _ in rebuildDerived() }
        .onChange(of: columns) { _, _ in rebuildDerived() }
        .onDisappear {
            isVisible = false
            saveTask?.cancel()
            // Capture the pending snapshot before SwiftUI removes this view. Closing during
            // the debounce window must not discard the last tap.
            if editRevision != savedRevision {
                let statuses = statusesForSave()
                let source: GroupEventAvailabilitySource = manualOverrides.isEmpty ? .calendar : .manual
                let id = eventID
                Task { _ = await service.save(eventId: id, statuses: statuses, durationMinutes: durationMinutes, source: source) }
            }
            service.stopListening()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            CalendarDiagnosticsSheet(
                start: columns.first?.slot.start ?? Date(),
                end: columns.last?.slot.end ?? Date()
            )
        }
        .alert("Zeitfinder", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Wann können alle?")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
            Label("Kalender werden nur auf diesem Gerät geprüft.", systemImage: "lock.shield")
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    private var rangePicker: some View {
        HStack {
            Button { moveRange(by: -14) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(rangeTitle)
                .font(PBTheme.Typography.body.weight(.medium))
            Spacer()
            Button { moveRange(by: 14) } label: {
                Image(systemName: "chevron.right")
            }
        }
        .foregroundStyle(PBTheme.textOnDark)
        .padding(.horizontal, PBTheme.Spacing.md)
        .frame(height: 46)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small).stroke(PBTheme.controlBorder, lineWidth: 1) }
    }

    private var hourPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: PBTheme.Spacing.sm) {
                ForEach(GroupEventTimeFinder.hours, id: \.self) { hour in
                    Button { selectedHour = hour } label: {
                        Text(String(format: "%02d:00", hour))
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(selectedHour == hour ? PBTheme.midnight : PBTheme.textOnDarkSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(selectedHour == hour ? PBTheme.surfaceOnDark : PBTheme.routeSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var availabilityMatrix: some View {
        let visibleColumns = selectedColumns
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gemeinsame Übersicht")
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Text("\(selectedHour):00 · \(durationMinutes / 60) Std.")
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Color.clear.frame(width: 94, height: 30)
                        ForEach(visibleColumns) { column in
                            VStack(spacing: 1) {
                                Text(column.weekday)
                                Text(column.day)
                            }
                            .font(PBTheme.Typography.micro)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                            .frame(width: 34, height: 30)
                        }
                    }

                    ForEach(participants) { participant in
                        let isOwnRow = participant.uid == uid
                        let statuses = statusByUID[participant.uid] ?? [:]
                        HStack(spacing: 6) {
                            HStack(spacing: 7) {
                                GroupEventParticipantAvatar(person: participant, size: 25)
                                Text(participant.displayName.components(separatedBy: " ").first ?? participant.displayName)
                                    .font(PBTheme.Typography.micro)
                                    .foregroundStyle(PBTheme.textOnDark)
                                    .lineLimit(1)
                            }
                            .frame(width: 94, alignment: .leading)

                            ForEach(visibleColumns) { column in
                                AvailabilityCell(
                                    status: statuses[column.slot.storageKey],
                                    isEditable: isOwnRow && service.hasLoaded && service.errorMessage == nil,
                                    isHighlighted: isOwnRow && manualOverrides[column.slot.storageKey] != nil,
                                    accessibilityText: "\(participant.displayName), \(column.spoken): \(statuses[column.slot.storageKey]?.title ?? "Keine Angabe")"
                                ) {
                                    cycle(column.slot)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 12) {
                legend(.available, title: "Frei")
                legend(.maybe, title: "Vielleicht")
                legend(.unavailable, title: "Belegt")
                Spacer()
                Text(saveStatusText)
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }

    private var saveStatusText: String {
        if service.isSaving { return "Speichert …" }
        if !manualOverrides.isEmpty { return "Umrandet = von dir geändert" }
        return "Tippe deine Felder"
    }

    @ViewBuilder
    private var calendarRow: some View {
        if CalendarAvailabilityService.hasFullAccess {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: PBTheme.Spacing.sm) {
                    Label(
                        isSyncingCalendar ? "Kalender wird abgeglichen …" : "Dein Kalender wird automatisch abgeglichen",
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    Spacer()
                    Button { Task { await syncCalendar(userInitiated: true) } } label: {
                        Image(systemName: isSyncingCalendar ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .frame(width: 28)
                    }
                    .buttonStyle(MiteTonalButtonStyle(prominent: false))
                    .disabled(isSyncingCalendar || service.isSaving)
                    .accessibilityLabel("Kalender neu abgleichen")
                }
                if let calendarSummary {
                    Text(calendarSummary)
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                Button { isShowingDiagnostics = true } label: {
                    Text("Was sieht Mite in meinem Kalender?")
                        .font(PBTheme.Typography.micro.weight(.semibold))
                        .foregroundStyle(PBTheme.accent)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button { Task { await syncCalendar(userInitiated: true) } } label: {
                    Label(isSyncingCalendar ? "Verbinde …" : "Kalender einmalig verbinden", systemImage: "calendar.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MiteTonalButtonStyle(prominent: true))
                .disabled(isSyncingCalendar || service.isSaving)
                Text("Danach schlägt Mite freie Zeitfenster automatisch vor – du musst nichts erneut prüfen.")
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text("Unsere besten Vorschläge")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            if suggestions.isEmpty {
                Text(statusByUID.isEmpty
                     ? "Sobald jemand Zeiten markiert oder seinen Kalender verbunden hat, erscheinen hier eure besten gemeinsamen Fenster."
                     : "In diesen zwei Wochen gibt es kein Zeitfenster, in dem niemand belegt ist. Blättere zu den nächsten Wochen oder ändere einzelne Felder.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .padding(.vertical, PBTheme.Spacing.md)
            } else {
                ForEach(suggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: GroupEventTimeSuggestion) -> some View {
        let isSent = proposedSlotID == suggestion.id
        let isSending = proposingSlotID == suggestion.id
        return HStack(spacing: 12) {
            Circle()
                .stroke(suggestion.everyoneCanAttend ? PBTheme.accent : PBTheme.textOnDarkSecondary, lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .overlay {
                    if suggestion.everyoneCanAttend { Circle().fill(PBTheme.accent).frame(width: 8, height: 8) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.slot.start, format: .dateTime.weekday(.wide).hour().minute())
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text(suggestion.summary)
                    .font(PBTheme.Typography.micro)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer()
            Button {
                propose(suggestion)
            } label: {
                Text(isSent ? "Gesendet" : (isSending ? "Sende …" : "Vorschlagen"))
                    .font(PBTheme.Typography.micro.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(PBTheme.controlSelected, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending || isSent)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small).stroke(PBTheme.controlBorder, lineWidth: 1) }
    }

    private var rangeTitle: String {
        guard let first = columns.first?.slot.start, let last = columns.last?.slot.start else { return "" }
        return "\(first.miteAbbreviatedDayMonthText) – \(last.miteAbbreviatedDayMonthText)"
    }

    private func legend(_ status: GroupEventAvailabilityStatus, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(AvailabilityCell.color(for: status)).frame(width: 11, height: 11)
            Text(title).font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    // MARK: - Derived state (computed once per change, never inside `body`)

    private static func makeColumns(rangeStart: Date, durationMinutes: Int) -> [SlotColumn] {
        GroupEventTimeFinder.slots(startingAt: rangeStart, durationMinutes: durationMinutes).map(SlotColumn.init)
    }

    /// One pass over the (small) answer set. Tapping a cell only changes `localStatuses`, so this
    /// stays cheap and the matrix re-renders immediately instead of recomputing dates and
    /// formatted strings for every participant on every tap.
    private func rebuildDerived() {
        var byUID: [String: [String: GroupEventAvailabilityStatus]] = [:]
        for response in service.responses where response.uid != uid && response.durationMinutes == durationMinutes {
            byUID[response.uid] = response.slotStatuses.compactMapValues(GroupEventAvailabilityStatus.init(rawValue:))
        }
        if !localStatuses.isEmpty {
            byUID[uid] = localStatuses
        } else if let own = ownSavedResponse, own.durationMinutes == durationMinutes {
            byUID[uid] = own.slotStatuses.compactMapValues(GroupEventAvailabilityStatus.init(rawValue:))
        }
        statusByUID = byUID

        var merged = service.responses.filter { $0.uid != uid }
        if let ownStatuses = byUID[uid] {
            merged.append(GroupEventAvailability(
                uid: uid,
                slotStatuses: ownStatuses.mapValues(\.rawValue),
                durationMinutes: durationMinutes,
                source: manualOverrides.isEmpty ? .calendar : .manual,
                updatedAt: .init(date: Date())
            ))
        }
        suggestions = GroupEventTimeFinder.suggestions(
            slots: columns.map(\.slot),
            responses: merged,
            eligibleUIDs: participants.map(\.uid)
        )
    }

    // MARK: - Layered answers: calendar first, hand-set overrides on top

    private var overridesDefaultsKey: String { "mite.availabilityOverrides.\(eventID).\(uid)" }

    private func loadPersistedOverrides() -> [String: GroupEventAvailabilityStatus] {
        let stored = UserDefaults.standard.dictionary(forKey: overridesDefaultsKey) as? [String: String] ?? [:]
        let now = Int64(Date().timeIntervalSince1970)
        return stored.reduce(into: [:]) { result, entry in
            guard let start = Int64(entry.key), start > now, let status = GroupEventAvailabilityStatus(rawValue: entry.value) else { return }
            result[entry.key] = status
        }
    }

    private func persistOverrides() {
        UserDefaults.standard.set(manualOverrides.mapValues(\.rawValue), forKey: overridesDefaultsKey)
    }

    /// Recomputes the effective answer for every slot of the visible range.
    private func applyEffective() {
        var effective = localStatuses.filter { key, _ in !columns.contains { $0.slot.storageKey == key } }
        for column in columns {
            let key = column.slot.storageKey
            if let status = manualOverrides[key] ?? calendarStatuses[key] { effective[key] = status }
        }
        localStatuses = effective
    }

    private func hydrateOwnResponse() {
        manualOverrides = loadPersistedOverrides()
        // Without calendar access the saved answers are the only source, so they act as the
        // person's own hand-set choices. With calendar access the calendar is the truth and
        // older clicks from before overrides existed must not shadow it.
        if !CalendarAvailabilityService.hasFullAccess, manualOverrides.isEmpty, let own = ownSavedResponse,
           own.durationMinutes == durationMinutes {
            manualOverrides = own.slotStatuses.compactMapValues(GroupEventAvailabilityStatus.init(rawValue:))
        }
        applyEffective()
        // A previous close/offline failure may have left local overrides newer than Firebase.
        if manualOverrides.contains(where: { ownSavedResponse?.slotStatuses[$0.key] != $0.value.rawValue }) {
            editRevision += 1
            scheduleSave()
        }
    }

    // MARK: - Actions

    private func cycle(_ slot: GroupEventTimeSlot) {
        let key = slot.storageKey
        let next: GroupEventAvailabilityStatus
        switch localStatuses[key] ?? statusByUID[uid]?[key] {
        case nil, .unavailable: next = .available
        case .available: next = .maybe
        case .maybe: next = .unavailable
        }
        if calendarStatuses[key] == next {
            manualOverrides.removeValue(forKey: key)
        } else {
            manualOverrides[key] = next
        }
        persistOverrides()
        applyEffective()
        tapFeedback += 1
        editRevision += 1
        scheduleSave()
    }

    /// Manual edits are saved automatically shortly after the last tap, so there is no separate
    /// confirmation step to forget.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func moveRange(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: rangeStart), next > Calendar.current.startOfDay(for: Date()) else { return }
        rangeStart = next
        columns = Self.makeColumns(rangeStart: next, durationMinutes: durationMinutes)
        applyEffective()
        Task { await autoSyncCalendarIfNeeded() }
    }

    private func propose(_ suggestion: GroupEventTimeSuggestion) {
        // Optimistic: the button reacts on the tap itself instead of after the network round trip.
        proposingSlotID = suggestion.id
        tapFeedback += 1
        Task {
            let success = await onPropose(suggestion.slot.start)
            proposingSlotID = nil
            if success { proposedSlotID = suggestion.id }
        }
    }

    /// Silent sync: whenever the screen opens, the app returns to the foreground, the range
    /// changes, or the calendar itself changes. Only runs after the one-time permission.
    private func autoSyncCalendarIfNeeded() async {
        guard isVisible, CalendarAvailabilityService.hasFullAccess, service.hasLoaded, service.errorMessage == nil else { return }
        await syncCalendar(userInitiated: false)
    }

    private func syncCalendar(userInitiated: Bool) async {
        guard !isSyncingCalendar else { return }
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }
        do {
            if userInitiated, !CalendarAvailabilityService.hasFullAccess {
                guard try await CalendarAvailabilityService.shared.requestAccess() else {
                    throw CalendarAvailabilityError.accessDenied
                }
            }
            let evaluatedColumns = columns
            let evaluation = try await CalendarAvailabilityService.shared.evaluate(evaluatedColumns.map(\.slot))
            guard isVisible else { return }
            guard evaluatedColumns == columns else {
                // The person changed weeks while EventKit was querying. Do not attach that
                // result to the new range; retry for the currently displayed columns.
                isSyncingCalendar = false
                Task { await autoSyncCalendarIfNeeded() }
                return
            }
            for (key, status) in evaluation.statuses { calendarStatuses[key] = status }
            // Overrides that now equal the calendar are redundant.
            manualOverrides = manualOverrides.filter { calendarStatuses[$0.key] != $0.value }
            persistOverrides()
            applyEffective()
            calendarSummary = summary(for: evaluation)

            let saved = ownSavedResponse?.slotStatuses ?? [:]
            let unchanged = localStatuses.allSatisfy { saved[$0.key] == $0.value.rawValue }
            if userInitiated || !unchanged { await save() }
        } catch {
            if userInitiated { service.errorMessage = error.localizedDescription }
        }
    }

    private func summary(for evaluation: CalendarAvailabilityService.Evaluation) -> String {
        var text = "\(evaluation.calendarCount) Kalender · \(evaluation.consideredEvents) Termine berücksichtigt"
        if evaluation.ignoredEvents > 0 {
            text += " (\(evaluation.ignoredEvents) übersprungen: abgesagt, abgelehnt oder ganztägig „Frei“)"
        }
        return text
    }

    private func save() async {
        let revision = editRevision
        let statuses = statusesForSave()
        guard !statuses.isEmpty else { return }
        let success = await service.save(
            eventId: eventID,
            statuses: statuses,
            durationMinutes: durationMinutes,
            source: manualOverrides.isEmpty ? .calendar : .manual
        )
        if success { savedRevision = max(savedRevision, revision) }
    }

    /// The server replaces the whole answer set and rejects slots that are (almost) in the past
    /// or more than 90 days out, so keep still-valid answers from other weeks and drop the rest.
    private func statusesForSave() -> [String: GroupEventAvailabilityStatus] {
        GroupEventAvailabilityPayload.make(local: localStatuses,
            saved: ownSavedResponse?.durationMinutes == durationMinutes ? ownSavedResponse?.slotStatuses ?? [:] : [:],
            preferredKeys: Set(columns.map { $0.slot.storageKey }))
    }
}

private struct SlotColumn: Identifiable, Hashable {
    let slot: GroupEventTimeSlot
    let hour: Int
    let weekday: String
    let day: String
    let spoken: String

    var id: String { slot.id }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = PBLocalization.germanLocale
        formatter.calendar = PBLocalization.germanCalendar
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = PBLocalization.germanLocale
        formatter.calendar = PBLocalization.germanCalendar
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
    private static let spokenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = PBLocalization.germanLocale
        formatter.calendar = PBLocalization.germanCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(slot: GroupEventTimeSlot) {
        self.slot = slot
        hour = Calendar.current.component(.hour, from: slot.start)
        weekday = Self.weekdayFormatter.string(from: slot.start)
        day = Self.dayFormatter.string(from: slot.start)
        spoken = Self.spokenFormatter.string(from: slot.start)
    }
}

private struct AvailabilityCell: View {
    let status: GroupEventAvailabilityStatus?
    let isEditable: Bool
    let isHighlighted: Bool
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Self.color(for: status))
                .frame(width: 34, height: 31)
                .overlay {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.28), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel(accessibilityText)
    }

    static func color(for status: GroupEventAvailabilityStatus?) -> Color {
        switch status {
        case .available: return PBTheme.accent.opacity(0.95)
        case .maybe: return PBTheme.surfaceMuted.opacity(0.88)
        case .unavailable: return PBTheme.routeSurfaceRaised
        case nil: return PBTheme.routeSurface
        }
    }
}

private struct MiteTonalButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PBTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(PBTheme.textOnDark)
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .background(prominent ? PBTheme.controlSelected : PBTheme.routeSurfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}


private struct CalendarDiagnosticsSheet: View {
    let start: Date
    let end: Date

    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics: CalendarAvailabilityService.Diagnostics?
    @State private var errorText: String?

    private var groupedEvents: [(day: Date, events: [CalendarAvailabilityService.DiagnosticEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: diagnostics?.events ?? []) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else if let diagnostics {
                    Section {
                        Text("Nur auf diesem Gerät sichtbar. Titel werden nie hochgeladen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Kalender, die Mite lesen kann (\(diagnostics.calendars.count))") {
                        ForEach(diagnostics.calendars, id: \.self) { Text($0).font(.footnote) }
                    }
                    if diagnostics.events.isEmpty {
                        Section { Text("In den nächsten zwei Wochen wurden keine Termine gefunden.") }
                    }
                    ForEach(groupedEvents, id: \.day) { group in
                        Section(group.day.miteLongDayMonthText) {
                            ForEach(group.events) { event in
                                let timing = diagnosticTiming(for: event)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(timing)
                                            .font(.footnote)
                                    }
                                    Text(event.calendarName).font(.caption).foregroundStyle(.secondary)
                                    Text(event.verdict).font(.caption.weight(.medium))
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Dein Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .task {
                do {
                    diagnostics = try await CalendarAvailabilityService.shared.diagnostics(from: start, to: end)
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func diagnosticTiming(for event: CalendarAvailabilityService.DiagnosticEvent) -> String {
        if event.isAllDay {
            let days = max(1, Int((event.end.timeIntervalSince(event.start) / 86_400).rounded()))
            return "ganztägig · \(days) \(days == 1 ? "Tag" : "Tage")"
        }
        return "\(event.start.miteTimeText)–\(event.end.miteTimeText)"
    }
}
