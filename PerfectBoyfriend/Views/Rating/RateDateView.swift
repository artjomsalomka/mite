import SwiftUI

struct RateDateView: View {
    let scope: DatePlanningScope
    let savedDate: SavedDate
    let savedDateService: SavedDateService

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RatingViewModel
    @State private var ratedDateCountBeforeSubmission = 0
    @State private var unlockedMilestone: DateMilestone?

    init(scope: DatePlanningScope, savedDate: SavedDate, savedDateService: SavedDateService) {
        self.scope = scope
        self.savedDate = savedDate
        self.savedDateService = savedDateService
        // Writes through the couple-wide SavedDateService already running in MainTabView (its
        // savedDates listener will pick up the rating write automatically) rather than opening
        // a second, throwaway instance just for this one write.
        _viewModel = StateObject(wrappedValue: RatingViewModel(service: savedDateService, scope: scope, savedDateId: savedDate.id ?? ""))
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Wie war euer Moment?")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text(savedDate.title)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(spacing: PBTheme.Spacing.md) {
                        Text("Deine Bewertung")
                            .font(PBTheme.Typography.headline)
                            .foregroundStyle(PBTheme.textPrimary)
                        HStack(spacing: PBTheme.Spacing.sm) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    viewModel.stars = star
                                } label: {
                                    Image(systemName: star <= viewModel.stars ? "star.fill" : "star")
                                        .font(.system(size: 31, weight: .medium))
                                        .foregroundStyle(PBTheme.warning)
                                        .frame(width: 38, height: 42)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(star) Sterne")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(PBTheme.Spacing.lg)
                    .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Was bleibt hängen?")
                        FlowTagPicker(tags: RatingViewModel.availableTags, selected: viewModel.selectedTags) { tag in
                            viewModel.toggleTag(tag)
                        }
                        .padding(PBTheme.Spacing.md)
                        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                        PBSectionTitle(title: "Ein kurzer Gedanke")
                        TextField("Was war besonders gut oder schlecht?", text: $viewModel.comment, axis: .vertical)
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textPrimary)
                            .lineLimit(3...6)
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        HStack {
                            Spacer()
                            Text("\(viewModel.comment.count)/\(SavedDateService.maximumRatingCommentLength)")
                                .font(PBTheme.Typography.micro)
                                .foregroundStyle(viewModel.comment.count > SavedDateService.maximumRatingCommentLength ? PBTheme.destructive : PBTheme.textOnDarkSecondary)
                        }
                    }

                    PBPrimaryButton(title: "Bewertung speichern", symbol: "checkmark", isLoading: viewModel.isSubmitting) {
                        Task {
                            await submitRating()
                        }
                    }
                    .disabled(!viewModel.canSubmit || viewModel.isSubmitting)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
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
        .onChange(of: viewModel.didSubmit) { _, didSubmit in
            guard didSubmit else { return }
            if case .couple = scope,
               let milestone = CoupleMilestones.all.first(where: { $0.requiredRatedDates == ratedDateCountBeforeSubmission + 1 }) {
                unlockedMilestone = milestone
            } else {
                dismiss()
            }
        }
        .fullScreenCover(item: $unlockedMilestone) { milestone in
            MilestoneCelebrationView(milestone: milestone) {
                unlockedMilestone = nil
                dismiss()
            }
        }
    }

    private func submitRating() async {
        // Capture before the Firestore listener applies its optimistic update. Otherwise a fast
        // local snapshot could make the app believe the next milestone was already achieved.
        ratedDateCountBeforeSubmission = savedDateService.savedDates.filter { $0.rating != nil }.count
        await viewModel.submit(ratedByUid: authManager.firebaseUser?.uid ?? "")
    }
}

private struct MilestoneCelebrationView: View {
    let milestone: DateMilestone
    let dismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        PBScreenContainer {
            VStack(spacing: PBTheme.Spacing.lg) {
                Spacer()

                Image(systemName: milestone.symbolName)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(PBTheme.accent)
                    .frame(width: 108, height: 108)
                    .background(PBTheme.surface, in: Circle())
                    .scaleEffect(isVisible ? 1 : 0.78)
                    .opacity(isVisible ? 1 : 0)

                VStack(spacing: PBTheme.Spacing.sm) {
                    Text("Neuer Meilenstein")
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)
                    Text(milestone.title)
                        .font(PBTheme.Typography.display)
                        .foregroundStyle(PBTheme.textOnDark)
                    Text(milestone.subtitle)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 12)

                Spacer()

                PBPrimaryButton(title: "Weiter", symbol: "arrow.right", action: dismiss)
                    .padding(.bottom, PBTheme.Spacing.xl)
            }
            .padding(.horizontal, PBTheme.Spacing.lg)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.34)) {
                isVisible = true
            }
        }
    }
}

/// Simple wrapping multi-select chip grid — same visual language as the criteria form's mood
/// picker (MoodFlowLayout), generalized to arbitrary string tags.
private struct FlowTagPicker: View {
    let tags: [String]
    let selected: Set<String>
    let onToggle: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let isSelected = selected.contains(tag)
                Button {
                    onToggle(tag)
                } label: {
                    Text(tag)
                        .font(PBTheme.Typography.caption)
                        .padding(.horizontal, PBTheme.Spacing.sm)
                        .padding(.vertical, PBTheme.Spacing.xs)
                        .background(isSelected ? PBTheme.accent : PBTheme.surfaceMuted)
                        .foregroundStyle(isSelected ? PBTheme.textOnDark : PBTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.pill))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, PBTheme.Spacing.xs)
    }
}
