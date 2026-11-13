import FirebaseFunctions
import Foundation
import StripeIdentity
import UIKit

@MainActor
final class SingleVerificationService: ObservableObject {
    private struct StartResponse: Codable, Sendable {
        let status: String
        let verificationSessionClientSecret: String?
    }

    private struct StatusResponse: Codable, Sendable {
        let status: String
    }

    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published var errorMessage: String?

    private var verificationSheet: IdentityVerificationSheet?

    func start() async {
        isWorking = true
        errorMessage = nil
        message = nil
        do {
            let response: StartResponse = try await call("startSingleVerification", response: StartResponse.self)
            isWorking = false
            guard let clientSecret = response.verificationSessionClientSecret else {
                message = statusMessage(for: response.status)
                return
            }
            guard let presenter = topViewController() else {
                errorMessage = "Die Verifizierung konnte nicht geöffnet werden. Bitte versuche es erneut."
                return
            }

            let sheet = IdentityVerificationSheet(verificationSessionClientSecret: clientSecret)
            verificationSheet = sheet
            sheet.present(from: presenter) { [weak self] result in
                Task { @MainActor in
                    self?.verificationSheet = nil
                    await self?.handle(result)
                }
            }
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshStatus() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let response: StatusResponse = try await call("refreshSingleVerificationStatus", response: StatusResponse.self)
            message = statusMessage(for: response.status)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ result: IdentityVerificationSheet.VerificationFlowResult) async {
        switch result {
        case .flowCompleted:
            await refreshStatus()
            if errorMessage == nil {
                message = "Deine Unterlagen wurden übermittelt. Die Prüfung kann ein paar Minuten dauern."
            }
        case .flowCanceled:
            message = "Die Verifizierung wurde nicht abgeschlossen. Du kannst sie jederzeit erneut starten."
        case .flowFailed(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func call<T: Decodable & Sendable>(_ name: String, response: T.Type) async throws -> T {
        let callable = Functions.functions().httpsCallable(name)
        return try await withTimeout(seconds: 20) {
            let result = try await callable.call([:])
            guard let dictionary = result.data as? [String: Any] else {
                throw VerificationError.invalidResponse
            }
            let json = try JSONSerialization.data(withJSONObject: dictionary)
            return try JSONDecoder().decode(T.self, from: json)
        }
    }

    private func statusMessage(for rawStatus: String) -> String {
        switch VerificationStatus(rawValue: rawStatus) ?? .unverified {
        case .verified: return "Deine Identität wurde bestätigt."
        case .pending: return "Deine Unterlagen werden noch geprüft."
        case .requiresInput: return "Für die Prüfung werden noch einmal Unterlagen benötigt."
        case .unverified: return "Noch keine Verifizierung gestartet."
        }
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        return visibleViewController(from: root)
    }

    private func visibleViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return visibleViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return visibleViewController(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return visibleViewController(from: selected)
        }
        return controller
    }

    private enum VerificationError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "Die Verifizierungs-Antwort konnte nicht gelesen werden." }
    }
}
