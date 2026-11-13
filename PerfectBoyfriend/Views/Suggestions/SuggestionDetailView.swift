import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct SuggestionDetailView: View {
    let scope: DatePlanningScope
    let requestId: String
    let criteria: DateCriteria
    let audience: PlanningAudience
    let visualsAlreadyGenerated: Bool
    @State var suggestion: DateSuggestion
    let savedDateService: SavedDateService
    let onPlanSaved: (PlanningMode) -> Void

    @EnvironmentObject private var authManager: AuthManager
    @State private var isResolving = false
    @State private var geocodeFailed = false
    @State private var scheduledAt: Date
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var hasSaved = false
    @State private var isCalculatingTransfers = false
    @State private var transferRequestID = UUID()
    @State private var showsPlanningDetails = false
    // Do not reveal generic fallbacks while the route's own visual motifs are still made.
    @State private var isGeneratingVisuals = true
    @State private var visualGenerationStarted = false

    init(
        scope: DatePlanningScope,
        requestId: String,
        criteria: DateCriteria,
        audience: PlanningAudience = .date,
        suggestion: DateSuggestion,
        visualsAlreadyGenerated: Bool = false,
        savedDateService: SavedDateService,
        onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }
    ) {
        self.scope = scope
        self.requestId = requestId
        self.criteria = criteria
        self.audience = audience
        self.visualsAlreadyGenerated = visualsAlreadyGenerated
        self.savedDateService = savedDateService
        self.onPlanSaved = onPlanSaved
        _suggestion = State(initialValue: suggestion)
        _scheduledAt = State(initialValue: Self.scheduledAt(from: criteria))
        _isGeneratingVisuals = State(initialValue: !visualsAlreadyGenerated)
        _visualGenerationStarted = State(initialValue: visualsAlreadyGenerated)
    }

    var body: some View {
        DateRouteTimeline(
            stations: suggestion.stations,
            startingAt: scheduledAt,
            isResolving: isResolving,
            isGeneratingVisuals: isGeneratingVisuals,
            immersive: true,
            city: criteria.city,
            routeTitle: suggestion.title,
            onPlan: { showsPlanningDetails = true }
        )
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showsPlanningDetails) {
            NavigationStack {
                planningDetails
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { showsPlanningDetails = false }
                                .tint(PBTheme.textOnDark)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            // Both operations enrich the same value-type suggestion. Keep them ordered so a
            // late place lookup can never overwrite just-arrived generated visuals.
            await resolveStations()
            if !visualsAlreadyGenerated { await loadGeneratedVisuals() }
            // MapKit occasionally throttles or times out a lookup. Retry the still-open stops a
            // couple of times in the background instead of waiting for a manual tap.
            for _ in 0..<2 where !suggestion.hasConfirmedPlaces && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await resolveStations()
            }
        }
        .onChange(of: scheduledAt) { _, _ in
            Task { await refreshTransfers() }
        }
    }

    private var planningDetails: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        Text(suggestion.title)
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(suggestion.summary)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        HStack(spacing: PBTheme.Spacing.sm) {
                            Label(suggestion.estimatedBudgetLevel.label, systemImage: "eurosign.circle")
                            Label("ca. \(DateSchedule.totalMinutes(suggestion.stations)) Min", systemImage: "clock")
                            Label("\(suggestion.stations.count) Stopps", systemImage: "mappin.and.ellipse")
                        }
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Euer Ablauf")
                        Text("Eure Route startet um \(scheduledAt.miteTimeText).")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        Text(isCalculatingTransfers ? "Wege zwischen den Stationen werden berechnet …" : routeTimingNote)
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        if !isResolving, !suggestion.hasConfirmedPlaces {
                            PlaceVerificationCard(
                                resolvedStationCount: suggestion.resolvedStationCount,
                                totalStationCount: suggestion.stations.count,
                                isGeocodeFailure: geocodeFailed
                            ) {
                                Task { await resolveStations() }
                            }
                        }
                        if geocodeFailed {
                            Label("\"\(criteria.city)\" konnte nicht gefunden werden. Prüft bitte die Stadt im Formular.", systemImage: "exclamationmark.triangle")
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.warning)
                                .padding(PBTheme.Spacing.sm)
                                .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                        }
                        Label("Öffnungszeiten und Reservierung vor dem Start kurz in Apple Maps prüfen.", systemImage: "clock.badge.exclamationmark")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Wann soll's losgehen?")
                        DatePicker("Datum & Uhrzeit", selection: $scheduledAt, in: Date()...)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDark)
                            .tint(PBTheme.accent)
                            .environment(\.colorScheme, .dark)
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                                    .stroke(.white.opacity(0.13), lineWidth: 1)
                            }
                    }

                    PBPrimaryButton(
                        title: saveButtonTitle,
                        symbol: "checkmark",
                        isLoading: isSaving || isResolving
                    ) {
                        Task { await save() }
                    }
                    .disabled(!canSave)

                    ShareLink(item: DateSchedule.shareText(title: suggestion.title, stations: suggestion.stations, startingAt: scheduledAt)) {
                        Label("Ablauf teilen", systemImage: "square.and.arrow.up")
                            .foregroundStyle(PBTheme.textOnDark)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    if let saveError {
                        Text(saveError)
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
    }

    /// The generated route starts at exactly the day and time the couple selected in the
    /// interactive planner. If that timestamp passed while they were deciding, default forward
    /// to the next evening rather than creating an unsaveable past plan.
    private static func scheduledAt(from criteria: DateCriteria) -> Date {
        let calendar = Calendar.current
        let pieces = criteria.time.split(separator: ":").compactMap { Int($0) }
        let hour = pieces.first ?? 19
        let minute = pieces.dropFirst().first ?? 0
        let selected = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: criteria.date) ?? Date()
        if selected > Date() {
            return selected
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) ?? tomorrow
    }

    private func resolveStations() async {
        guard !isResolving else { return }
        let unresolvedStations = suggestion.stations.filter { $0.resolvedPlace == nil }
        isResolving = true
        geocodeFailed = false
        defer { isResolving = false }
        let city = criteria.city
        if !unresolvedStations.isEmpty {
            guard let coordinate = try? await withTimeout(seconds: 8, operation: {
                try await LocationService.geocodeCity(city)
            }) else {
                geocodeFailed = true
                return
            }
            let resolved = await PlaceResolver.resolveAll(stations: unresolvedStations, near: coordinate, radiusMeters: max(1500, criteria.radiusKm * 1000), city: city)
            guard !Task.isCancelled else { return }
            for station in resolved {
                if let index = suggestion.stations.firstIndex(where: { $0.id == station.id }) {
                    suggestion.stations[index].resolvedPlace = station.resolvedPlace
                }
            }
        }

        let visualizableStations = suggestion.stations
        let transferID = UUID()
        transferRequestID = transferID
        isCalculatingTransfers = true
        defer {
            if transferRequestID == transferID {
                isCalculatingTransfers = false
            }
        }
        let mobility = criteria.mobility
        let start = scheduledAt
        async let transfers = DateTransferResolver.resolve(stations: visualizableStations, mobility: mobility, startingAt: start)
        if let enriched = try? await withTimeout(seconds: 12, operation: {
            await DateSuggestionEnrichmentService.enrichStationVisuals(visualizableStations, city: city)
        }) {
            suggestion.stations = enriched
        }
        let timed = await transfers
        // A DatePicker change can start a newer ETA request while place resolution is still
        // in progress. Never let this older request write its timing back over the newer one.
        guard transferRequestID == transferID else {
            await refreshTransfers()
            return
        }
        guard !Task.isCancelled else { return }
        for station in timed {
            if let index = suggestion.stations.firstIndex(where: { $0.id == station.id }) {
                suggestion.stations[index].arrivalTransfer = station.arrivalTransfer
            }
        }
    }

    private func loadGeneratedVisuals() async {
        guard !visualGenerationStarted, !Task.isCancelled else { return }
        visualGenerationStarted = true
        defer { isGeneratingVisuals = false }
        do {
            let images = try await DateSuggestionImageService.generateImages(
                scope: scope,
                requestId: requestId,
                suggestionId: suggestion.id
            )
            guard !Task.isCancelled else { return }
            for index in suggestion.stations.indices {
                if let image = images[suggestion.stations[index].order] {
                    suggestion.stations[index].licensedImage = image
                }
            }
            PBImageCache.preload(urlStrings: Array(images.values.map(\.url)))
        } catch {
            // Visual enrichment is optional: existing licensed/local fallbacks remain usable.
        }
    }

    private func refreshTransfers() async {
        let stations = suggestion.stations
        guard stations.count > 1 else { return }

        let transferID = UUID()
        transferRequestID = transferID
        isCalculatingTransfers = true
        defer {
            if transferRequestID == transferID {
                isCalculatingTransfers = false
            }
        }
        let timed = await DateTransferResolver.resolve(
            stations: stations,
            mobility: criteria.mobility,
            startingAt: scheduledAt
        )
        guard !Task.isCancelled, transferRequestID == transferID else { return }

        for station in timed {
            if let index = suggestion.stations.firstIndex(where: { $0.id == station.id }) {
                suggestion.stations[index].arrivalTransfer = station.arrivalTransfer
            }
        }
    }

    private func save() async {
        guard let uid = authManager.firebaseUser?.uid else { return }
        guard canSave else { return }
        guard isStartTimeValid else {
            saveError = "Der Startzeitpunkt liegt zu nah oder in der Vergangenheit. Wähle bitte oben eine spätere Zeit."
            return
        }
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            if audience.mode == .group {
                let stops = suggestion.stations.map { "• \($0.title)" }.joined(separator: "\n")
                let note = [suggestion.summary, stops].filter { !$0.isEmpty }.joined(separator: "\n\n")
                // The server limits titles to 70 characters, plan steps to three of at most 100
                // characters, and cover images to https or generated-Storage sources. Fit the
                // payload to those limits here so a valid route is never rejected on a technicality.
                let steps = suggestion.stations.prefix(3).map { String($0.title.prefix(100)) }
                let cover = suggestion.stations.first?.licensedImage.flatMap { image in
                    (image.url.hasPrefix("https://") || image.url.hasPrefix("storage://generatedDateImages/")) ? image : nil
                }
                try await GroupEventService().create(
                    title: groupEventTitle,
                    city: criteria.city,
                    note: String(note.prefix(500)),
                    scheduledAt: scheduledAt,
                    invitees: audience.invitees,
                    planSteps: Array(steps),
                    coverLicensedImage: cover
                )
            } else {
                try await savedDateService.save(
                    scope: scope,
                    requestId: requestId,
                    suggestion: suggestion,
                    scheduledAt: scheduledAt,
                    createdByUid: uid
                )
            }
            hasSaved = true
            showsPlanningDetails = false
            onPlanSaved(audience.mode)
        } catch {
            saveError = "Konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private var canSave: Bool {
        !hasSaved && !isSaving && !isResolving
    }

    /// The server rejects group plans starting within five minutes; the couple rule requires a
    /// future time. A small margin also covers the time the person spent on this screen.
    private var isStartTimeValid: Bool {
        scheduledAt > Date().addingTimeInterval(6 * 60)
    }

    /// Route composition is allowed to omit a marketing-style title. The first selected
    /// activity is then the natural, stable event title used by the shared plan.
    private var groupEventTitle: String {
        let proposedTitle = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proposedTitle.isEmpty { return String(proposedTitle.prefix(70)) }
        if let firstStation = suggestion.stations.first?.title.trimmingCharacters(in: .whitespacesAndNewlines), !firstStation.isEmpty {
            return firstStation
        }
        return "Gemeinsamer Plan"
    }

    private var saveButtonTitle: String {
        if hasSaved { return audience.mode == .group ? "Treffen geplant" : "Date gespeichert" }
        if isResolving { return "Orte werden geprüft …" }
        return audience.mode == .group ? "Dieses Treffen planen" : "Dieses Date auswählen"
    }

    private var routeTimingNote: String {
        let complete = suggestion.stations.dropFirst().allSatisfy { $0.arrivalTransfer != nil }
        return complete
            ? "Zeiten einschließlich geschätzter Wege. Bei anderem Startzeitpunkt können sich die Wegezeiten ändern."
            : "Orientierung anhand der Aktivitäten. Noch nicht verfügbare Wegezeiten sind nicht eingerechnet."
    }
}

private struct PlaceVerificationCard: View {
    let resolvedStationCount: Int
    let totalStationCount: Int
    let isGeocodeFailure: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: PBTheme.Spacing.sm) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PBTheme.accent)
                .frame(width: 36, height: 36)
                .background(PBTheme.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isGeocodeFailure ? "Stadt noch nicht bestätigt" : "\(resolvedStationCount) von \(totalStationCount) Orten bestätigt")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text(isGeocodeFailure ? "Ihr könnt trotzdem planen und die Stadt später prüfen." : "Ihr könnt trotzdem planen – offene Orte findet ihr in Apple Maps.")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Erneut prüfen", action: retry)
                .font(PBTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(PBTheme.accent)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}

/// One station row — shows the resolved real place if MapKit found a good match, otherwise
/// Claude's own title/description plus a manual-search fallback. Never a broken/empty card.
struct StationRowView: View {
    let station: DateStation
    let isResolving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
            DateStationVisual(station: station)
                .frame(maxWidth: .infinity)
                .frame(height: 158)
                .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
            if let image = station.licensedImage {
                LicensedImageCredit(image: image)
                    .foregroundStyle(PBTheme.textOnDarkSecondary.opacity(0.82))
            }

            Text("\(station.order + 1). \(station.title)")
                .font(PBTheme.Typography.body.bold())
                .foregroundStyle(PBTheme.textOnDark)
            Text(station.description)
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)

            if isResolving {
                HStack(spacing: PBTheme.Spacing.xs) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PBTheme.accent)
                    Text("Suche Ort in der Nähe …")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
            } else if let place = station.resolvedPlace {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(PBTheme.Typography.caption.bold()).foregroundStyle(PBTheme.textOnDark)
                    Text(place.address).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    Button {
                        openInAppleMaps(place: place)
                    } label: {
                        Label("In Apple Maps öffnen", systemImage: "map")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.accent)
                    }
                    Text("Details wie Öffnungszeiten bitte in Apple Maps prüfen.")
                        .font(.system(size: 11))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keinen passenden Ort in der Nähe gefunden — bitte manuell suchen.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.warning)
                    Button {
                        openManualSearch()
                    } label: {
                        Label("In Apple Maps suchen", systemImage: "magnifyingglass")
                            .font(PBTheme.Typography.caption)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }

    private func openInAppleMaps(place: ResolvedPlace) {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = place.name
        mapItem.openInMaps()
    }

    private func openManualSearch() {
        let query = station.searchQueryHint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(query)") else { return }
        UIApplication.shared.open(url)
    }
}
