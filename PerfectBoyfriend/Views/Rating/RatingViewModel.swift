import Foundation

@MainActor
final class RatingViewModel: ObservableObject {
    /// Confirmed fixed set — kept in the service as the shared validation source of truth.
    static let availableTags = SavedDateService.ratingTags

    @Published var stars = 0
    @Published var comment = ""
    @Published var selectedTags: Set<String> = []
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var didSubmit = false

    private let service: SavedDateService
    private let scope: DatePlanningScope
    private let savedDateId: String

    init(service: SavedDateService, scope: DatePlanningScope, savedDateId: String) {
        self.service = service
        self.scope = scope
        self.savedDateId = savedDateId
    }

    var canSubmit: Bool {
        stars >= 1
            && stars <= 5
            && comment.count <= SavedDateService.maximumRatingCommentLength
            && selectedTags.count <= SavedDateService.maximumRatingTags
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
            if errorMessage == "Wähle höchstens fünf passende Tags aus." {
                errorMessage = nil
            }
        } else {
            guard selectedTags.count < SavedDateService.maximumRatingTags else {
                errorMessage = "Wähle höchstens fünf passende Tags aus."
                return
            }
            selectedTags.insert(tag)
        }
    }

    func submit(ratedByUid: String) async {
        guard canSubmit else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.submitRating(
                scope: scope,
                savedDateId: savedDateId,
                stars: stars,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment,
                tags: Array(selectedTags),
                ratedByUid: ratedByUid
            )
            didSubmit = true
        } catch {
            errorMessage = "Bewertung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
