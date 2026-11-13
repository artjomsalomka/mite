import SwiftUI

struct SuggestionLoadingView: View {
    let scope: DatePlanningScope
    let criteria: DateCriteria
    let audience: PlanningAudience
    let savedDateService: SavedDateService
    let onPlanSaved: (PlanningMode) -> Void
    @StateObject private var viewModel = SuggestionsViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                PBScreenContainer {
                    DateAssemblyLoadingAnimation(kind: audience.mode == .group ? .group : .date)
                    .padding(.horizontal, PBTheme.Spacing.xl)
                }
            case .loaded(let requestId, let suggestions):
                DateAssemblySelectionView(scope: scope, requestId: requestId, criteria: criteria, audience: audience, candidates: suggestions, savedDateService: savedDateService, onPlanSaved: onPlanSaved)
            case .failed(let failure):
                PBScreenContainer {
                    PBEmptyState(
                        symbol: failure.symbol,
                        title: failure.title,
                        message: failure.message,
                        actionTitle: failure.retryIsAvailable ? "Erneut versuchen" : nil,
                        action: failure.retryIsAvailable ? {
                            Task { await viewModel.load(scope: scope, criteria: criteria) }
                        } : nil
                    )
                    .padding(.horizontal, PBTheme.Spacing.md)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded(scope: scope, criteria: criteria)
        }
    }
}
