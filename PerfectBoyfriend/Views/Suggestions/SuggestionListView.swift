import SwiftUI

struct SuggestionListView: View {
    let scope: DatePlanningScope
    let requestId: String
    let criteria: DateCriteria
    let audience: PlanningAudience
    let suggestions: [DateSuggestion]
    let savedDateService: SavedDateService

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text(audience.suggestionHeadline)
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("\(suggestions.count) echte Routen für \(criteria.city), bereit für \(audience.mode == .group ? "eure \(audience.participantCount)-köpfige Runde" : "euren Abend").")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    ForEach(suggestions) { suggestion in
                        NavigationLink {
                            SuggestionDetailView(scope: scope, requestId: requestId, criteria: criteria, audience: audience, suggestion: suggestion, savedDateService: savedDateService)
                        } label: {
                            SuggestionListCard(suggestion: suggestion)
                        }
                        .buttonStyle(.plain)
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
}

private struct SuggestionListCard: View {
    let suggestion: DateSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            routeVisual
            if let image = suggestion.stations.first?.licensedImage {
                LicensedImageCredit(image: image)
            }

            HStack(alignment: .top, spacing: PBTheme.Spacing.sm) {
                Text(suggestion.title)
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            Text(suggestion.summary)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .lineLimit(2)

            if suggestion.hasConfirmedPlaces {
                Label(concreteStops.joined(separator: "  ·  "), systemImage: "mappin.and.ellipse")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(2)
            } else {
                Label(placeVerificationLabel, systemImage: "location.magnifyingglass")
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.accent)
                    .lineLimit(2)
            }

            HStack(spacing: PBTheme.Spacing.sm) {
                Label(suggestion.estimatedBudgetLevel.label, systemImage: "eurosign.circle")
                Label("\(suggestion.estimatedTotalDurationMinutes) Min", systemImage: "clock")
                Label("\(suggestion.stations.count)", systemImage: "mappin.and.ellipse")
            }
            .font(PBTheme.Typography.caption)
            .foregroundStyle(PBTheme.textOnDarkSecondary)

            if !suggestion.moodTags.isEmpty {
                Text(suggestion.moodTags.joined(separator: " · "))
                    .font(PBTheme.Typography.caption.weight(.medium))
                    .foregroundStyle(PBTheme.accent)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var routeVisual: some View {
        ZStack(alignment: .bottomLeading) {
            if let station = suggestion.stations.first {
                DateStationVisual(station: station)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
    }

    private var concreteStops: [String] {
        suggestion.stations.compactMap(\.resolvedPlace?.name)
    }

    private var placeVerificationLabel: String {
        if suggestion.resolvedStationCount == 0 {
            return "Orte vor dem Speichern bestätigen"
        }
        return "\(suggestion.resolvedStationCount) von \(suggestion.stations.count) Orten bestätigt"
    }
}
