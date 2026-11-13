import SwiftUI

struct SavedDateHistoryView: View {
    let scope: DatePlanningScope
    @ObservedObject var savedDateService: SavedDateService
    @ObservedObject var postService: PostService
    @ObservedObject var groupEventService: GroupEventService
    let viewerUID: String
    let defaultCity: String
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date?

    /// Only a clear acceptance belongs beside someone's own dates. Pending and "maybe" plans
    /// remain in Activity until the person has explicitly chosen to join.
    private var acceptedGroupPlans: [GroupEvent] {
        groupEventService.events
            .filter { $0.status == .planned && $0.attendance(for: viewerUID) == .going }
            .sorted { $0.scheduledAt.dateValue() < $1.scheduledAt.dateValue() }
    }

    private var calendarEntries: [CalendarAgendaEntry] {
        let dates = savedDateService.savedDates.map(CalendarAgendaEntry.date)
        let groupPlans = acceptedGroupPlans.map(CalendarAgendaEntry.groupPlan)
        return (dates + groupPlans).sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var visibleAgenda: [CalendarAgendaEntry] {
        calendarEntries.filter { entry in
            guard Calendar.current.isDate(entry.scheduledAt, equalTo: displayedMonth, toGranularity: .month) else {
                return false
            }
            guard let selectedDay else { return true }
            return Calendar.current.isDate(entry.scheduledAt, inSameDayAs: selectedDay)
        }
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text("Dein Kalender")
                                .font(PBTheme.Typography.display)
                                .foregroundStyle(PBTheme.textOnDark)
                            Text("Alle Dates und bestätigten Pläne mit Freund:innen an einem Ort.")
                                .font(PBTheme.Typography.body)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        historyContent
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if savedDateService.isLoading && groupEventService.isLoading && calendarEntries.isEmpty {
            ProgressView()
                .tint(PBTheme.textOnDark)
                .frame(maxWidth: .infinity)
                .padding(.top, PBTheme.Spacing.xxl)
        } else if let loadErrorMessage = savedDateService.loadErrorMessage, savedDateService.savedDates.isEmpty && acceptedGroupPlans.isEmpty {
            PBEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Verlauf nicht erreichbar",
                message: loadErrorMessage,
                actionTitle: "Erneut versuchen",
                action: savedDateService.retryLoading
            )
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xxl)
        } else if calendarEntries.isEmpty {
            PBEmptyState(
                symbol: "calendar.badge.plus",
                title: "Noch keine Dates",
                message: scope.emptyHistoryDescription
            )
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xxl)
        } else {
            PersonalCalendarMonthView(
                displayedMonth: displayedMonth,
                selectedDay: selectedDay,
                entriesOnDay: { day in
                    calendarEntries.filter { Calendar.current.isDate($0.scheduledAt, inSameDayAs: day) }
                },
                onPreviousMonth: { moveMonth(by: -1) },
                onNextMonth: { moveMonth(by: 1) },
                onSelectDay: { selectedDay = $0 }
            )

            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                PBSectionTitle(title: agendaTitle, actionTitle: selectedDay == nil ? nil : "Monat zeigen", action: {
                    selectedDay = nil
                })
                if visibleAgenda.isEmpty {
                    Text("In diesem Zeitraum steht noch nichts an.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .padding(PBTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                } else {
                    ForEach(visibleAgenda) { entry in
                        agendaLink(entry)
                    }
                }
            }
        }
    }

    private func savedDateLink(for savedDate: SavedDate) -> some View {
        NavigationLink {
            SavedDateDetailView(
                scope: scope,
                savedDate: savedDate,
                savedDateService: savedDateService,
                postService: postService
            )
        } label: {
            SavedDateRow(savedDate: savedDate)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func agendaLink(_ entry: CalendarAgendaEntry) -> some View {
        switch entry {
        case .date(let savedDate):
            savedDateLink(for: savedDate)
        case .groupPlan(let plan):
            NavigationLink {
                GroupEventDetailView(event: plan, uid: viewerUID, service: groupEventService)
            } label: {
                GroupPlanHistoryRow(plan: plan)
            }
            .buttonStyle(.plain)
        }
    }

    private var agendaTitle: String {
        if let selectedDay {
            return selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
        }
        return "Termine im \(displayedMonth.formatted(.dateTime.month(.wide).locale(Locale(identifier: "de_DE"))))"
    }

    private func moveMonth(by offset: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        selectedDay = nil
    }
}

private enum CalendarAgendaEntry: Identifiable {
    case date(SavedDate)
    case groupPlan(GroupEvent)

    var id: String {
        switch self {
        case .date(let value): return "date-\(value.id ?? value.sourceSuggestionId)"
        case .groupPlan(let value): return "group-\(value.id ?? value.creatorUid)-\(value.scheduledAt.seconds)"
        }
    }

    var scheduledAt: Date {
        switch self {
        case .date(let value): return value.scheduledAt.dateValue()
        case .groupPlan(let value): return value.scheduledAt.dateValue()
        }
    }

    var dotColor: Color {
        switch self {
        case .date: return PBTheme.accent
        case .groupPlan: return PBTheme.success
        }
    }
}

private struct PersonalCalendarMonthView: View {
    let displayedMonth: Date
    let selectedDay: Date?
    let entriesOnDay: (Date) -> [CalendarAgendaEntry]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onSelectDay: (Date) -> Void

    private let calendar = PBLocalization.germanCalendar

    var body: some View {
        VStack(spacing: PBTheme.Spacing.md) {
            HStack {
                Button(action: onPreviousMonth) { Image(systemName: "chevron.left") }
                    .calendarMonthControl("Vorheriger Monat")
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))))
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Button(action: onNextMonth) { Image(systemName: "chevron.right") }
                    .calendarMonthControl("Nächster Monat")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(PBTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let entries = entriesOnDay(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        return Button { onSelectDay(day) } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day().locale(Locale(identifier: "de_DE"))))
                    .font(PBTheme.Typography.caption.weight(isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(PBTheme.textOnDark)
                HStack(spacing: 3) {
                    ForEach(Array(Set(entries.map(\.dotColor))), id: \.self) { color in
                        Circle().fill(color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? PBTheme.accent.opacity(0.46) : isToday ? .white.opacity(0.12) : .clear, in: Circle())
            .overlay { if isToday { Circle().stroke(.white.opacity(0.36), lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.day().month(.wide).year().locale(PBLocalization.germanLocale))), \(entries.count) Termine")
    }

    private var weekdaySymbols: [String] {
        PBLocalization.shortWeekdaySymbolsStartingMonday
    }

    private var monthCells: [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth),
              let days = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let values = days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }
        return Array(repeating: nil, count: leading) + values
    }
}

private extension View {
    func calendarMonthControl(_ label: String) -> some View {
        font(.system(size: 13, weight: .bold))
            .foregroundStyle(PBTheme.textOnDark)
            .frame(width: 34, height: 34)
            .background(PBTheme.routeSurfaceRaised, in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

private struct GroupPlanHistoryRow: View {
    let plan: GroupEvent

    private var goingCount: Int { plan.participants.filter { $0.status == .going }.count }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GroupEventCover(event: plan)

            LinearGradient(
                colors: [Color.black.opacity(0.04), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: PBTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                    Label("Mit Freund:innen", systemImage: "person.3.fill")
                        .font(PBTheme.Typography.micro)
                        .foregroundStyle(PBTheme.textOnDark)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(PBTheme.midnight.opacity(0.86), in: Capsule())

                    Text(plan.title)
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textOnDark)
                        .lineLimit(2)

                    HStack(spacing: PBTheme.Spacing.sm) {
                        Label("\(goingCount) dabei", systemImage: "person.2.fill")
                        Text(plan.scheduledAt.dateValue(), format: .dateTime.weekday(.abbreviated).hour().minute())
                        if !plan.city.isEmpty {
                            Circle().fill(PBTheme.textOnDarkSecondary.opacity(0.72)).frame(width: 3, height: 3)
                            Text(plan.city).lineLimit(1)
                        }
                    }
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                }

                Spacer(minLength: 0)

                VStack(spacing: 1) {
                    Text(plan.scheduledAt.dateValue(), format: .dateTime.day())
                        .font(.system(size: 20, weight: .medium))
                    Text(plan.scheduledAt.dateValue(), format: .dateTime.month(.abbreviated))
                        .font(PBTheme.Typography.micro.weight(.bold))
                }
                .foregroundStyle(PBTheme.midnight)
                .frame(width: 48, height: 48)
                .background(PBTheme.surface.opacity(0.96), in: Circle())
            }
            .padding(PBTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: PBTheme.Shadow.card, radius: 12, y: 6)
    }
}

private struct SavedDateRow: View {
    let savedDate: SavedDate

    private var firstPlaceName: String? {
        savedDate.stations.compactMap(\.resolvedPlace).first?.name
    }

    private var firstImage: LicensedImage? {
        savedDate.stations.compactMap(\.licensedImage).first
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardBackground

            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.80)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: PBTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                    dateBadge

                    Text(savedDate.title)
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textOnDark)
                        .lineLimit(2)

                    HStack(spacing: PBTheme.Spacing.sm) {
                        if let firstPlaceName {
                            Label(firstPlaceName, systemImage: "mappin.and.ellipse")
                                .lineLimit(1)
                        }
                        Label {
                            Text(savedDate.scheduledAt.dateValue(), format: .dateTime.weekday(.abbreviated).hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    }
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: PBTheme.Spacing.sm) {
                    if savedDate.status == .cancelled {
                        Text("Abgesagt")
                            .font(PBTheme.Typography.micro.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(PBTheme.destructive.opacity(0.74), in: Capsule())
                    } else if let rating = savedDate.rating {
                        Label("\(rating.stars)", systemImage: "star.fill")
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.warning)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    } else if savedDate.isInPast {
                        Text("Bewerten")
                            .font(PBTheme.Typography.micro.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.18), in: Capsule())
                    } else {
                        Text("Geplant")
                            .font(PBTheme.Typography.micro.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.18), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PBTheme.textOnDark)
                }
            }
            .padding(PBTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 138)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: PBTheme.Shadow.card, radius: 12, y: 6)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let firstImage {
            LicensedImageView(image: firstImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LinearGradient(
                colors: [PBTheme.midnightSoft, PBTheme.midnightRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var dateBadge: some View {
        HStack(spacing: 5) {
            Text(savedDate.scheduledAt.dateValue(), format: .dateTime.day())
                .font(PBTheme.Typography.caption.weight(.bold))
            Text(savedDate.scheduledAt.dateValue(), format: .dateTime.month(.abbreviated))
                .font(PBTheme.Typography.micro)
                .textCase(.uppercase)
        }
        .foregroundStyle(PBTheme.textOnDark)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
