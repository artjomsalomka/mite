import SwiftUI

/// The route is no longer a black-box suggestion. People choose one concrete option for each
/// moment of the afternoon/evening, then we compose and visualise only their final selection.
struct DateAssemblySelectionView: View {
    let scope: DatePlanningScope
    let requestId: String
    let criteria: DateCriteria
    let audience: PlanningAudience
    let candidates: [DateSuggestion]
    let savedDateService: SavedDateService
    let onPlanSaved: (PlanningMode) -> Void

    @State private var selectedCandidateIds: [String]
    @State private var showsFinalizing = false

    init(
        scope: DatePlanningScope,
        requestId: String,
        criteria: DateCriteria,
        audience: PlanningAudience,
        candidates: [DateSuggestion],
        savedDateService: SavedDateService,
        onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }
    ) {
        self.scope = scope
        self.requestId = requestId
        self.criteria = criteria
        self.audience = audience
        self.candidates = candidates
        self.savedDateService = savedDateService
        self.onPlanSaved = onPlanSaved
        let count = candidates.first?.stations.count ?? 0
        _selectedCandidateIds = State(initialValue: Array(candidates.prefix(1).map(\.id)).repeatingToCount(count))
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xl) {
                    header

                    ForEach(0..<slotCount, id: \.self) { slot in
                        DateAssemblySlot(
                            number: slot + 1,
                            title: slotTitle(for: slot),
                            options: options(for: slot),
                            selectedID: Binding(
                                get: { selectedCandidateIds.indices.contains(slot) ? selectedCandidateIds[slot] : "" },
                                set: { selectedCandidateIds[slot] = $0 }
                            )
                        )
                    }

                    Button { showsFinalizing = true } label: {
                        Label("Auswahl zusammensetzen", systemImage: "sparkles")
                            .font(PBTheme.Typography.body.weight(.semibold))
                            .foregroundStyle(PBTheme.midnight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(PBTheme.textOnDark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isComplete)
                    .opacity(isComplete ? 1 : 0.45)

                    Text("Danach verbinden wir eure Auswahl zu einem Ablauf und erstellen die Bilder erst für eure echten Stationen.")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationDestination(isPresented: $showsFinalizing) {
            DateAssemblyFinalizingView(
                scope: scope,
                requestId: requestId,
                criteria: criteria,
                audience: audience,
                candidateIds: selectedCandidateIds,
                savedDateService: savedDateService,
                onPlanSaved: onPlanSaved
            )
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Euer Ablauf")
                .font(PBTheme.Typography.display)
                .foregroundStyle(PBTheme.textOnDark)
            Text("Wählt für jeden Moment eine von fünf konkreten Ideen. Noch keine Bilder – erst eure Auswahl wird zu eurem Date.")
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }

    private var slotCount: Int {
        guard let count = candidates.first?.stations.count, (2...3).contains(count) else { return 0 }
        return count
    }

    private var isComplete: Bool {
        slotCount > 0 && selectedCandidateIds.count == slotCount && selectedCandidateIds.allSatisfy { !$0.isEmpty }
    }

    private func options(for slot: Int) -> [DateAssemblyOption] {
        candidates.compactMap { candidate in
            guard candidate.stations.indices.contains(slot) else { return nil }
            return DateAssemblyOption(id: candidate.id, station: candidate.stations[slot])
        }
    }

    private func slotTitle(for slot: Int) -> String {
        switch slot {
        case 0: return "Auftakt"
        case 1: return slotCount == 2 ? "Der zweite Moment" : "Mittendrin"
        default: return "Ausklang"
        }
    }
}

private struct DateAssemblyOption: Identifiable {
    let id: String
    let station: DateStation
}

private struct DateAssemblySlot: View {
    let number: Int
    let title: String
    let options: [DateAssemblyOption]
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Text(String(format: "%02d", number))
                    .font(PBTheme.Typography.micro.weight(.bold))
                    .foregroundStyle(PBTheme.midnight)
                    .frame(width: 29, height: 29)
                    .background(PBTheme.textOnDark, in: Circle())
                Text(title)
                    .font(PBTheme.Typography.title.weight(.regular))
                    .foregroundStyle(PBTheme.textOnDark)
            }

            ForEach(options) { option in
                Button { selectedID = option.id } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: option.station.category.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedID == option.id ? PBTheme.midnight : PBTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(selectedID == option.id ? PBTheme.textOnDark : PBTheme.accent.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.station.title)
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(option.station.description)
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                                .lineLimit(2)
                            Label("ca. \(option.station.estimatedDurationMinutes) Min", systemImage: "clock")
                                .font(PBTheme.Typography.micro)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selectedID == option.id ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(selectedID == option.id ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary.opacity(0.65))
                    }
                    .padding(13)
                    .background(selectedID == option.id ? PBTheme.accent.opacity(0.44) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(selectedID == option.id ? PBTheme.textOnDark.opacity(0.44) : .white.opacity(0.10), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1) }
    }
}

private struct DateAssemblyFinalizingView: View {
    let scope: DatePlanningScope
    let requestId: String
    let criteria: DateCriteria
    let audience: PlanningAudience
    let candidateIds: [String]
    let savedDateService: SavedDateService
    let onPlanSaved: (PlanningMode) -> Void

    @State private var result: Result<DateSuggestion, Error>?

    var body: some View {
        Group {
            if let result {
                switch result {
                case .success(let suggestion):
                    SuggestionDetailView(
                        scope: scope,
                        requestId: requestId,
                        criteria: criteria,
                        audience: audience,
                        suggestion: suggestion,
                        visualsAlreadyGenerated: true,
                        savedDateService: savedDateService,
                        onPlanSaved: onPlanSaved
                    )
                case .failure(let error):
                    PBScreenContainer {
                        PBEmptyState(
                            symbol: "wifi.exclamationmark",
                            title: "Euer Date konnte nicht zusammengesetzt werden",
                            message: error.localizedDescription,
                            actionTitle: "Erneut versuchen",
                            action: {
                                self.result = nil
                                Task { await assemble() }
                            }
                        )
                        .padding(PBTheme.Spacing.md)
                    }
                }
            } else {
                PBScreenContainer {
                    VStack(spacing: PBTheme.Spacing.lg) {
                        DateAssemblyLoadingAnimation(kind: audience.mode == .group ? .group : .date).frame(maxHeight: 540)
                        Text("Wir machen aus eurer Auswahl jetzt euren Ablauf und die passenden Bilder.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, PBTheme.Spacing.xl)
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await assemble() }
    }

    private func assemble() async {
        guard result == nil else { return }
        do {
            var suggestion = try await DateSuggestionService.composeSuggestion(scope: scope, requestId: requestId, candidateIds: candidateIds)
            let images = try await DateSuggestionImageService.generateImages(scope: scope, requestId: requestId, suggestionId: suggestion.id)
            guard images.count == suggestion.stations.count else { throw AssemblyVisualError.incomplete }
            for index in suggestion.stations.indices {
                if let image = images[suggestion.stations[index].order] {
                    suggestion.stations[index].licensedImage = image
                }
            }
            PBImageCache.preload(urlStrings: Array(images.values.map(\.url)))
            result = .success(suggestion)
        } catch {
            result = .failure(error)
        }
    }
}

private enum AssemblyVisualError: LocalizedError {
    case incomplete

    var errorDescription: String? {
        "Die Bilder für eure Route konnten noch nicht vollständig erstellt werden. Bitte versucht es erneut."
    }
}

private extension Array where Element == String {
    func repeatingToCount(_ count: Int) -> [String] {
        guard let first else { return [] }
        return Array(repeating: first, count: count)
    }
}

private extension StationCategory {
    var symbol: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .bar, .nightlife: return "wineglass.fill"
        case .park, .nature: return "leaf.fill"
        case .museum: return "building.columns.fill"
        case .cinema: return "film.fill"
        case .theater: return "theatermasks.fill"
        case .sight: return "binoculars.fill"
        case .activity: return "figure.run"
        case .shopping: return "bag.fill"
        case .other: return "sparkles"
        }
    }
}
