import Foundation

@MainActor
final class CoupleOnboardingViewModel: ObservableObject {
    @Published var joinCode = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var createdInviteCode: String?

    private let coupleService: CoupleService

    init(coupleService: CoupleService) {
        self.coupleService = coupleService
    }

    var canSubmitJoinCode: Bool {
        joinCode.count == 6 && joinCode.allSatisfy(\.isNumber)
    }

    func createCouple() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            createdInviteCode = try await coupleService.createCouple()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinCouple() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await coupleService.joinCouple(code: joinCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
